import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;
import 'package:dji_waypoint_engine/engine.dart';
import 'package:latlong2/latlong.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/main.dart';
import 'package:ymapper/presets/preset_manager.dart';
import 'package:ymapper/shared/mission_summary.dart';
import 'package:ymapper/shared/value_listeneables.dart';

/// Dirección de la API de misiones. Se puede cambiar al compilar con
/// --dart-define=API_URL=https://...
const String apiBaseUrl = String.fromEnvironment('API_URL',
    defaultValue: 'https://mapper-api-production.up.railway.app');

/// Resumen de una misión guardada, para la lista.
class SavedMission {
  final String id;
  final String name;
  final DateTime updatedAt;
  final Map<String, dynamic> summary;

  SavedMission(
      {required this.id,
      required this.name,
      required this.updatedAt,
      required this.summary});

  factory SavedMission.fromJson(Map<String, dynamic> j) => SavedMission(
        id: j['id'] as String,
        name: j['name'] as String,
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '')
                ?.toLocal() ??
            DateTime.now(),
        summary: (j['summary'] as Map?)?.cast<String, dynamic>() ?? {},
      );
}

class MissionApiException implements Exception {
  final String message;
  MissionApiException(this.message);
  @override
  String toString() => message;
}

/// Código de sincronización guardado en este dispositivo.
class SyncKey {
  static const _prefsKey = "syncKey";
  static const _alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

  static String? get current => prefs.getString(_prefsKey);

  static String generate() {
    final r = Random.secure();
    final groups = List.generate(
        5,
        (_) => List.generate(4, (_) => _alphabet[r.nextInt(_alphabet.length)])
            .join());
    return groups.join("-");
  }

  /// Normaliza lo que el usuario escribe: mayúsculas, sin espacios, con guiones.
  static String? normalize(String input) {
    final raw = input.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    if (raw.length != 20) return null;
    return [
      for (int i = 0; i < 20; i += 4) raw.substring(i, i + 4),
    ].join("-");
  }

  static Future<void> save(String key) => prefs.setString(_prefsKey, key);

  /// Enlace que vincula otro dispositivo con este código (para el QR).
  static String linkFor(String key) {
    final base = Uri.base;
    return Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: base.path.isEmpty ? "/" : base.path,
        queryParameters: {"vincular": key}).toString();
  }

  /// Si la app se abrió desde un enlace de vinculación (?vincular=CODIGO),
  /// guarda ese código, limpia la dirección y devuelve `true`.
  static Future<bool> linkFromUrl() async {
    final raw = Uri.base.queryParameters["vincular"];
    if (raw == null) return false;
    final key = normalize(raw);
    if (kIsWeb) {
      // Quitar el código de la barra de direcciones y del historial
      try {
        final clean = Uri.base.replace(queryParameters: {}).toString()
            .replaceFirst(RegExp(r'\?(?=#|$)'), '');
        html.window.history.replaceState(null, "", clean);
      } catch (_) {}
    }
    if (key == null) return false;
    await save(key);
    return true;
  }

  /// Devuelve el código actual o crea uno nuevo.
  static Future<String> ensure() async {
    final existing = current;
    if (existing != null) return existing;
    final key = generate();
    await save(key);
    return key;
  }
}

class MissionApi {
  static Dio _client(String key) => Dio(BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {"X-Workspace-Key": key},
      ));

  static Never _fail(Object e) {
    if (e is DioException) {
      final msg = (e.response?.data is Map)
          ? (e.response!.data['error'] as String?)
          : null;
      if (msg != null) throw MissionApiException(msg);
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw MissionApiException("Sin conexión con el servidor de misiones");
      }
    }
    throw MissionApiException("No se pudo completar la operación");
  }

  static Future<List<SavedMission>> list() async {
    final key = await SyncKey.ensure();
    try {
      final r = await _client(key).get("/missions");
      return (r.data as List)
          .map((e) => SavedMission.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _fail(e);
    }
  }

  static Future<Map<String, dynamic>> get(String id) async {
    final key = await SyncKey.ensure();
    try {
      final r = await _client(key).get("/missions/$id");
      return (r.data as Map).cast<String, dynamic>();
    } catch (e) {
      _fail(e);
    }
  }

  static Future<String> create(String name, Map<String, dynamic> data) async {
    final key = await SyncKey.ensure();
    try {
      final r = await _client(key)
          .post("/missions", data: {"name": name, "data": data});
      return r.data['id'] as String;
    } catch (e) {
      _fail(e);
    }
  }

  static Future<void> update(String id,
      {String? name, Map<String, dynamic>? data}) async {
    final key = await SyncKey.ensure();
    try {
      await _client(key).put("/missions/$id", data: {
        if (name != null) "name": name,
        if (data != null) "data": data,
      });
    } catch (e) {
      _fail(e);
    }
  }

  static Future<void> delete(String id) async {
    final key = await SyncKey.ensure();
    try {
      await _client(key).delete("/missions/$id");
    } catch (e) {
      _fail(e);
    }
  }
}

/// Convierte el estado de la app en un documento guardable y viceversa.
class MissionDoc {
  static const int version = 1;

  static Map<String, dynamic> fromState(ValueListenables l) {
    final s = MissionSummary.of(l);
    return {
      "version": version,
      "summary": {
        "areaHa": double.parse((s.areaM2 / 10000).toStringAsFixed(3)),
        "gsdCm": double.parse(s.gsdCm.toStringAsFixed(2)),
        "photos": s.photos,
        "minutes": s.totalMinutes.round(),
        "missions": s.segments.length,
        "altitude": l.altitude,
        "gcps": l.gcps.length,
      },
      "polygon": [
        for (final p in l.polygon) [p.latitude, p.longitude]
      ],
      "home": l.homePoint == null
          ? null
          : [l.homePoint!.latitude, l.homePoint!.longitude],
      "flight": {
        "altitude": l.altitude,
        "groundOffset": l.groundOffset,
        "forwardOverlap": l.forwardOverlap,
        "sideOverlap": l.sideOverlap,
        "rotation": l.rotation,
        "speed": l.speed,
        "cameraAngle": l.cameraAngle,
        "fillGrid": l.fillGrid,
        "createCameraPoints": l.createCameraPoints,
        "delay": l.delayAtWaypoint,
        "lineExtension": l.lineExtension,
        "batteryMinutes": l.batteryMinutes,
        "turnMode": l.turnMode.name,
        "finishAction": l.onFinished.name,
        "rcLostAction": l.rcLostAction.name,
      },
      "camera": {
        "preset": l.selectedCameraPreset?.name,
        "sensorWidth": l.sensorWidth,
        "sensorHeight": l.sensorHeight,
        "focalLength": l.focalLength,
        "imageWidth": l.imageWidth,
        "imageHeight": l.imageHeight,
      },
      "gcpCrs": l.gcpCrs.name,
      "gcps": [
        for (final g in l.gcps)
          {
            "name": g.name,
            "north": g.north,
            "east": g.east,
            "elevation": g.elevation,
            "isCheck": g.isCheck,
          }
      ],
    };
  }

  static double _d(dynamic v, double fallback) =>
      v is num ? v.toDouble() : fallback;
  static int _i(dynamic v, int fallback) => v is num ? v.round() : fallback;

  static T _enum<T extends Enum>(List<T> values, dynamic name, T fallback) =>
      values.firstWhere((e) => e.name == name, orElse: () => fallback);

  /// Carga un documento guardado en el estado de la app.
  static void applyTo(ValueListenables l, Map<String, dynamic> doc) {
    final f = (doc["flight"] as Map?)?.cast<String, dynamic>() ?? {};
    l.altitude = _i(f["altitude"], l.altitude);
    l.groundOffset = _i(f["groundOffset"], 0);
    l.forwardOverlap = _i(f["forwardOverlap"], l.forwardOverlap);
    l.sideOverlap = _i(f["sideOverlap"], l.sideOverlap);
    l.rotation = _i(f["rotation"], 0);
    l.speed = _d(f["speed"], l.speed);
    l.cameraAngle = _i(f["cameraAngle"], -90);
    l.fillGrid = f["fillGrid"] == true;
    l.createCameraPoints = f["createCameraPoints"] != false;
    l.delayAtWaypoint = _i(f["delay"], 0);
    l.lineExtension = _i(f["lineExtension"], l.lineExtension);
    l.batteryMinutes = _i(f["batteryMinutes"], l.batteryMinutes);
    l.turnMode = _enum(TurnMode.values, f["turnMode"], TurnMode.curved);
    l.onFinished =
        _enum(FinishAction.values, f["finishAction"], FinishAction.goHome);
    l.rcLostAction =
        _enum(RCLostAction.values, f["rcLostAction"], RCLostAction.goBack);

    final c = (doc["camera"] as Map?)?.cast<String, dynamic>() ?? {};
    final presets = PresetManager.getPresets();
    final matches = presets.where((p) => p.name == c["preset"]);
    final preset = matches.isEmpty ? null : matches.first;
    if (preset != null) {
      l.selectedCameraPreset = preset;
      prefs.setString("latestPreset", preset.name);
    }
    l.sensorWidth = _d(c["sensorWidth"], l.sensorWidth);
    l.sensorHeight = _d(c["sensorHeight"], l.sensorHeight);
    l.focalLength = _d(c["focalLength"], l.focalLength);
    l.imageWidth = _i(c["imageWidth"], l.imageWidth);
    l.imageHeight = _i(c["imageHeight"], l.imageHeight);

    final crs = _enum(GcpCrs.values, doc["gcpCrs"], GcpCrs.ctm12);
    l.gcpCrs = crs;
    l.gcps = [
      for (final g in (doc["gcps"] as List? ?? []))
        GroundControlPoint(
          name: "${g["name"]}",
          north: _d(g["north"], 0),
          east: _d(g["east"], 0),
          elevation: _d(g["elevation"], 0),
          isCheck: g["isCheck"] == true,
          position: ColombiaProjection.toWgs84(
              crs, _d(g["north"], 0), _d(g["east"], 0)),
        )
    ];

    final home = doc["home"] as List?;
    l.homePoint = home == null
        ? null
        : LatLng(_d(home[0], 0), _d(home[1], 0));
    l.polygon = [
      for (final p in (doc["polygon"] as List? ?? []))
        LatLng(_d(p[0], 0), _d(p[1], 0))
    ];
  }
}
