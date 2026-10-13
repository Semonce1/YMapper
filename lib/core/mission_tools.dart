import 'dart:math';

import 'package:latlong2/latlong.dart';

/// Herramientas de OrigenLabs: puntos de control (GCP), proyecciones de
/// Colombia, estadísticas de la misión y división en varias misiones.

/// Sistemas de coordenadas aceptados para importar puntos de control.
enum GcpCrs { ctm12, magnaBogota, wgs84 }

extension GcpCrsInfo on GcpCrs {
  String get label {
    switch (this) {
      case GcpCrs.ctm12:
        return "CTM12 · Origen Nacional (EPSG:9377)";
      case GcpCrs.magnaBogota:
        return "MAGNA-SIRGAS Bogotá (EPSG:3116)";
      case GcpCrs.wgs84:
        return "Lat/Lon WGS84 (EPSG:4326)";
    }
  }

  String get shortLabel {
    switch (this) {
      case GcpCrs.ctm12:
        return "CTM12";
      case GcpCrs.magnaBogota:
        return "MAGNA Bogotá";
      case GcpCrs.wgs84:
        return "Lat/Lon";
    }
  }

  String get epsg {
    switch (this) {
      case GcpCrs.ctm12:
        return "EPSG:9377";
      case GcpCrs.magnaBogota:
        return "EPSG:3116";
      case GcpCrs.wgs84:
        return "EPSG:4326";
    }
  }
}

/// Punto de control o de chequeo medido en campo.
class GroundControlPoint {
  final String name;

  /// Norte (o latitud en WGS84)
  final double north;

  /// Este (o longitud en WGS84)
  final double east;

  /// Cota en metros
  final double elevation;

  /// `true` si es punto de chequeo (no se usa para amarrar el modelo)
  final bool isCheck;

  /// Posición en el mapa
  final LatLng position;

  GroundControlPoint({
    required this.name,
    required this.north,
    required this.east,
    required this.elevation,
    required this.isCheck,
    required this.position,
  });
}

class GcpParseResult {
  final List<GroundControlPoint> points;
  final List<String> errors;
  GcpParseResult(this.points, this.errors);
}

/// Proyección Transversa de Mercator inversa (GRS80), validada contra PROJ
/// con error menor a 1 mm para CTM12 y MAGNA Bogotá.
class ColombiaProjection {
  static const double _a = 6378137.0;
  static const double _f = 1 / 298.257222101;

  static LatLng toWgs84(GcpCrs crs, double north, double east) {
    switch (crs) {
      case GcpCrs.wgs84:
        return LatLng(north, east);
      case GcpCrs.ctm12:
        return _inverseTM(north, east,
            lat0: 4.0, lon0: -73.0, k0: 0.9992, fe: 5000000, fn: 2000000);
      case GcpCrs.magnaBogota:
        return _inverseTM(north, east,
            lat0: 4.596200416666666,
            lon0: -74.07750791666666,
            k0: 1.0,
            fe: 1000000,
            fn: 1000000);
    }
  }

  static double _meridianArc(double phi, double e2) {
    return _a *
        ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256) * phi -
            (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * e2 * e2 * e2 / 1024) *
                sin(2 * phi) +
            (15 * e2 * e2 / 256 + 45 * e2 * e2 * e2 / 1024) * sin(4 * phi) -
            (35 * e2 * e2 * e2 / 3072) * sin(6 * phi));
  }

  static LatLng _inverseTM(double n, double e,
      {required double lat0,
      required double lon0,
      required double k0,
      required double fe,
      required double fn}) {
    final e2 = 2 * _f - _f * _f;
    final ep2 = e2 / (1 - e2);
    final m0 = _meridianArc(lat0 * pi / 180, e2);
    final m = m0 + (n - fn) / k0;
    final mu = m / (_a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256));
    final e1 = (1 - sqrt(1 - e2)) / (1 + sqrt(1 - e2));
    final p1 = mu +
        (3 * e1 / 2 - 27 * pow(e1, 3) / 32) * sin(2 * mu) +
        (21 * e1 * e1 / 16 - 55 * pow(e1, 4) / 32) * sin(4 * mu) +
        (151 * pow(e1, 3) / 96) * sin(6 * mu) +
        (1097 * pow(e1, 4) / 512) * sin(8 * mu);
    final c1 = ep2 * pow(cos(p1), 2);
    final t1 = pow(tan(p1), 2);
    final n1 = _a / sqrt(1 - e2 * pow(sin(p1), 2));
    final r1 = _a * (1 - e2) / pow(1 - e2 * pow(sin(p1), 2), 1.5);
    final d = (e - fe) / (n1 * k0);
    final lat = p1 -
        (n1 * tan(p1) / r1) *
            (d * d / 2 -
                (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * ep2) * pow(d, 4) / 24 +
                (61 + 90 * t1 + 298 * c1 + 45 * t1 * t1 - 252 * ep2 - 3 * c1 * c1) *
                    pow(d, 6) /
                    720);
    final lon = lon0 * pi / 180 +
        (d -
                (1 + 2 * t1 + c1) * pow(d, 3) / 6 +
                (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * ep2 + 24 * t1 * t1) *
                    pow(d, 5) /
                    120) /
            cos(p1);
    return LatLng(lat * 180 / pi, lon * 180 / pi);
  }
}

/// Lee un CSV de topografía en orden P, N, E, Z (o P, Lat, Lon, Z en WGS84).
/// Acepta separadores coma, punto y coma, tabulación o espacios, y una quinta
/// columna opcional con el tipo ("control" o "chequeo").
class GcpParser {
  static GcpParseResult parse(String text, GcpCrs crs) {
    final points = <GroundControlPoint>[];
    final errors = <String>[];
    final lines = text.split(RegExp(r'\r?\n'));

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i].trim();
      if (raw.isEmpty) continue;

      List<String> cols;
      bool commaDecimals = false;
      if (raw.contains(';')) {
        cols = raw.split(';');
        commaDecimals = true;
      } else if (raw.contains('\t')) {
        cols = raw.split('\t');
        commaDecimals = true;
      } else if (raw.contains(',')) {
        cols = raw.split(',');
      } else {
        cols = raw.split(RegExp(r'\s+'));
      }
      cols = cols.map((c) => c.trim()).toList();

      if (cols.length < 4) {
        errors.add("Línea ${i + 1}: se esperaban al menos 4 columnas");
        continue;
      }

      double? num(String s) =>
          double.tryParse(commaDecimals ? s.replaceAll(',', '.') : s);

      final n = num(cols[1]);
      final e = num(cols[2]);
      final z = num(cols[3]);
      if (n == null || e == null || z == null) {
        // Probablemente el encabezado
        if (points.isEmpty && i == 0) continue;
        errors.add("Línea ${i + 1}: coordenadas no numéricas");
        continue;
      }

      final name = cols[0];
      final typeText = cols.length > 4 ? cols[4].toLowerCase() : "";
      final upperName = name.toUpperCase();
      final isCheck = typeText.contains("cheq") ||
          typeText.contains("check") ||
          typeText.contains("chk") ||
          upperName.startsWith("CHK") ||
          upperName.startsWith("CHQ");

      if (crs == GcpCrs.wgs84 && (n.abs() > 90 || e.abs() > 180)) {
        errors.add(
            "Línea ${i + 1}: valores fuera de rango para Lat/Lon. ¿Elegiste el sistema correcto?");
        continue;
      }
      if (crs != GcpCrs.wgs84 && (n.abs() < 1000 || e.abs() < 1000)) {
        errors.add(
            "Línea ${i + 1}: parecen grados, no metros. ¿Elegiste el sistema correcto?");
        continue;
      }

      points.add(GroundControlPoint(
        name: name,
        north: n,
        east: e,
        elevation: z,
        isCheck: isCheck,
        position: ColombiaProjection.toWgs84(crs, n, e),
      ));
    }
    return GcpParseResult(points, errors);
  }

  /// Archivo de coordenadas: primera línea con la proyección y luego
  /// "nombre este norte cota" por punto, para cargar en el editor de GCP.
  static String toCoordinatesFile(List<GroundControlPoint> gcps, GcpCrs crs,
      {bool includeChecks = false}) {
    final buffer = StringBuffer();
    buffer.writeln(crs.epsg);
    for (final p in gcps) {
      if (p.isCheck && !includeChecks) continue;
      // Orden x (este / longitud), y (norte / latitud), z
      final decimals = crs == GcpCrs.wgs84 ? 8 : 3;
      buffer.writeln("${p.name}\t${p.east.toStringAsFixed(decimals)}\t"
          "${p.north.toStringAsFixed(decimals)}\t${p.elevation.toStringAsFixed(3)}");
    }
    return buffer.toString();
  }
}

/// Tramo de una misión dividida (índices inclusivos sobre la lista de puntos).
class MissionSegment {
  final int start;
  final int end;
  final int photos;
  final double distanceMeters;
  final double minutes;

  MissionSegment({
    required this.start,
    required this.end,
    required this.photos,
    required this.distanceMeters,
    required this.minutes,
  });

  int get waypointCount => end - start + 1;
}

class MissionStats {
  /// Límite práctico de waypoints por archivo en DJI Fly (el formato admite
  /// 101, pero DJI Fly se cierra con más de 99).
  static const int maxWaypointsPerMission = 99;

  /// Tiempo fijo por misión: despegue, ascenso, aterrizaje (segundos).
  static const double overheadSeconds = 90;

  /// GSD en cm/px
  static double gsdCm({
    required double altitude,
    required double sensorWidth,
    required double focalLength,
    required int imageWidth,
  }) {
    if (focalLength <= 0 || imageWidth <= 0) return 0;
    return altitude * sensorWidth * 100 / (focalLength * imageWidth);
  }

  /// Tamaño mínimo recomendado de la diana: 20 píxeles en la foto.
  static double targetSizeCm(double gsdCm) => gsdCm * 20;

  static double _dist(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Meter, a, b);

  /// Divide la ruta en misiones que respeten el límite de waypoints y la
  /// duración útil de la batería.
  static List<MissionSegment> split({
    required List<LatLng> points,
    required List<bool> photoFlags,
    required LatLng? home,
    required double speed,
    required int delaySec,
    required int batteryMinutes,
    int maxWaypoints = maxWaypointsPerMission,
  }) {
    final segments = <MissionSegment>[];
    if (points.isEmpty) return segments;
    final limitSeconds = batteryMinutes * 60.0;

    final v = max(speed, 0.1);
    bool isPhoto(int i) => i < photoFlags.length ? photoFlags[i] : true;
    double homeDist(int i) => home == null ? 0 : _dist(home, points[i]);

    int start = 0;
    while (start < points.length) {
      int end = start;
      double path = 0;
      int photos = isPhoto(start) ? 1 : 0;
      final toFirst = homeDist(start);

      while (end + 1 < points.length && (end + 2 - start) <= maxWaypoints) {
        final nextPath = path + _dist(points[end], points[end + 1]);
        final nextPhotos = photos + (isPhoto(end + 1) ? 1 : 0);
        final seconds = (toFirst + nextPath + homeDist(end + 1)) / v +
            nextPhotos * delaySec +
            overheadSeconds;
        if (seconds > limitSeconds) break;
        path = nextPath;
        photos = nextPhotos;
        end++;
      }

      final distance = toFirst + path + homeDist(end);
      final seconds = distance / v + photos * delaySec + overheadSeconds;
      segments.add(MissionSegment(
        start: start,
        end: end,
        photos: photos,
        distanceMeters: distance,
        minutes: seconds / 60,
      ));
      start = end + 1;
    }
    return segments;
  }
}
