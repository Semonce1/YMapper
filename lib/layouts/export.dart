import 'dart:convert';

import 'package:ymapper/core/drone_mapper_format.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ymapper/core/djifly_kmz.dart';
import 'package:ymapper/core/mission_store.dart';
import 'package:ymapper/core/file_saver.dart';
import 'package:ymapper/core/share/share_file.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/layouts/missions_page.dart';
import 'package:ymapper/components/origen_widgets.dart';
import 'package:ymapper/shared/mission_summary.dart';
import 'package:ymapper/theme/origen_theme.dart';
import 'package:geoxml/geoxml.dart';
import 'package:ymapper/components/popups/dji_load_alert.dart';
import 'package:ymapper/components/popups/litchi_load_alert.dart';
import 'package:ymapper/main.dart';
import 'package:litchi_waypoint_engine/engine.dart' as litchi;
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:provider/provider.dart';

class ExportBar extends StatefulWidget {
  const ExportBar({super.key});

  @override
  State<ExportBar> createState() => ExportBarState();
}

class ExportBarState extends State<ExportBar> {
  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _isPhoto(ValueListenables l, int i) =>
      l.createCameraPoints &&
      (i < l.photoFlags.length ? l.photoFlags[i] : true);

  List<MissionSegment> _segments(ValueListenables l) => MissionStats.split(
        points: l.photoLocations,
        photoFlags: l.photoFlags,
        home: l.homePoint,
        speed: l.speed,
        delaySec: l.delayAtWaypoint,
        batteryMinutes: l.batteryMinutes,
      );

  /// Genera el KMZ de DJI Fly para los puntos [start]..[end] (inclusivos),
  /// con la misma estructura que el archivo que produce DJI Fly.
  Uint8List _buildDjiKmz(ValueListenables listenables, int start, int end,
      {TurnMode? turnMode}) {
    final flags = [
      for (int i = start; i <= end; i++) _isPhoto(listenables, i),
    ];
    return DjiFlyKmz.build(
      points: listenables.photoLocations.sublist(start, end + 1),
      photoFlags: flags,
      altitude: listenables.altitude,
      speed: listenables.speed,
      gimbalPitch: listenables.cameraAngle,
      turnMode: turnMode ?? listenables.turnMode,
      hoverSeconds: listenables.delayAtWaypoint,
      finishAction: listenables.onFinished.name,
      rcLostAction: listenables.rcLostAction.name,
    );
  }

  Uint8List _buildLitchiCsv(ValueListenables listenables, int start, int end) {
    var waypoints = <litchi.Waypoint>[];
    for (int i = start; i <= end; i++) {
      final location = listenables.photoLocations[i];
      final photo = _isPhoto(listenables, i);
      waypoints.add(litchi.Waypoint(
          latitude: location.latitude,
          longitude: location.longitude,
          altitude: listenables.altitude,
          speed: listenables.speed.toInt(),
          gimbalPitch: listenables.cameraAngle,
          gimbalMode: litchi.GimbalMode.interpolate,
          actions: [
            if (listenables.delayAtWaypoint > 0 && photo)
              litchi.Action(
                  actionType: litchi.ActionType.stayFor,
                  // Litchi usa milisegundos
                  actionParam: listenables.delayAtWaypoint.toDouble() * 1000),
            if (photo) litchi.Action(actionType: litchi.ActionType.takePhoto)
          ]));
    }
    return Uint8List.fromList(
        utf8.encode(litchi.LitchiCsv.generateCsv(waypoints)));
  }

  Future<void> _export(ValueListenables listenables,
      {required bool dji, TurnMode? turnMode, String suffix = ""}) async {
    if (listenables.photoLocations.isEmpty) {
      _snack("No hay ruta para exportar. Dibuja primero el área.");
      return;
    }
    final segments = _segments(listenables);
    final ext = dji ? "kmz" : "csv";
    final baseName =
        (dji ? "origenlabs_mision" : "origenlabs_litchi") + suffix;

    Future<bool> saveSegment(int index) {
      final seg = segments[index];
      final bytes = dji
          ? _buildDjiKmz(listenables, seg.start, seg.end, turnMode: turnMode)
          : _buildLitchiCsv(listenables, seg.start, seg.end);
      final slot = dji ? DjiFlySlot.current : null;
      final name = slot ??
          (segments.length == 1
              ? baseName
              : "${baseName}_m${(index + 1).toString().padLeft(2, '0')}");
      return FileSaver.save(
          bytes: bytes,
          fileName: name,
          extension: ext,
          mimeType: dji ? 'application/octet-stream' : 'text/csv',
          dialogTitle: "Guardar misión");
    }

    if (segments.length == 1) {
      final ok = await saveSegment(0);
      if (!ok) {
        _snack("Exportación cancelada");
        return;
      }
      _afterExport(dji);
      return;
    }

    // Varias misiones: un botón por archivo (iPhone solo permite una
    // descarga por toque).
    await showDialog(
      context: context,
      builder: (context) {
        final saved = <int>{};
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: Text("${segments.length} misiones"),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                        "La ruta supera el límite de waypoints o la duración de una batería. "
                        "Descarga cada misión y vuélalas en orden."),
                    const SizedBox(height: 8),
                    for (int i = 0; i < segments.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(child: Text("${i + 1}")),
                        title: Text(
                            "${segments[i].waypointCount} puntos · ${segments[i].photos} fotos"),
                        subtitle: Text(
                            "${segments[i].minutes.toStringAsFixed(0)} min · "
                            "${(segments[i].distanceMeters / 1000).toStringAsFixed(2).replaceAll('.', ',')} km"),
                        trailing: saved.contains(i)
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : IconButton(
                                tooltip: "Descargar misión ${i + 1}",
                                icon: const Icon(Icons.download),
                                onPressed: () async {
                                  final ok = await saveSegment(i);
                                  if (ok) setDialogState(() => saved.add(i));
                                }),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Listo")),
            ],
          );
        });
      },
    );
    _afterExport(dji);
  }

  String _kmzName(ValueListenables l, int index, int total) {
    // Con la misión fija de DJI Fly configurada, el archivo ya sale con el
    // nombre exacto que hay que reemplazar.
    final slot = DjiFlySlot.current;
    if (slot != null) return "$slot.kmz";
    final base = (l.currentMissionName ?? "origenlabs_mision")
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áéíóúñ]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safe = base.isEmpty ? "origenlabs_mision" : base;
    return total == 1
        ? "$safe.kmz"
        : "${safe}_m${(index + 1).toString().padLeft(2, '0')}.kmz";
  }

  /// Abre el menú de compartir del iPhone con el KMZ ("Guardar en
  /// Archivos"). Debe llamarse directamente desde un toque.
  Future<void> _sendToDjiFly(ValueListenables l, MissionSegment seg,
      int index, int total) async {
    final bytes = _buildDjiKmz(l, seg.start, seg.end);
    final name = _kmzName(l, index, total);
    final result = await shareFile(bytes, name,
        mimeType: "application/vnd.google-earth.kmz");
    switch (result) {
      case ShareResult.shared:
        _snack(DjiFlySlot.current == null
            ? "Listo. Guárdalo en la carpeta de la misión y reemplaza el archivo."
            : "Listo. Abre DJI Fly y carga la misión fija.");
      case ShareResult.cancelled:
        break;
      case ShareResult.unsupported:
      case ShareResult.error:
        // Computador u otro navegador: se descarga el archivo
        await FileSaver.save(
            bytes: bytes,
            fileName: name.replaceAll(".kmz", ""),
            extension: "kmz");
        _snack("Este dispositivo no permite compartir; se descargó el KMZ.");
    }
  }

  Future<void> _configureSlot() async {
    final controller = TextEditingController(text: DjiFlySlot.current ?? "");
    String? error;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          Future<void> pick() async {
            final picked = await FilePicker.pickFiles(
                type: FileType.any, dialogTitle: "Misión fija de DJI Fly");
            if (picked == null || picked.files.isEmpty) return;
            final id = DjiFlySlot.parse(picked.files.first.name);
            if (id == null) {
              setDialog(() => error =
                  "Ese archivo no es de una misión de DJI Fly. Elige el .kmz que está dentro de la carpeta de la misión.");
              return;
            }
            await DjiFlySlot.save(id);
            if (context.mounted) Navigator.pop(context);
            if (mounted) setState(() {});
            _snack("Misión fija configurada (${DjiFlySlot.short(id)}…)");
          }

          Future<void> saveTyped() async {
            final id = DjiFlySlot.parse(controller.text);
            if (id == null) {
              setDialog(() => error =
                  "El nombre debe verse así: F93B1A22-88E7-497B-A54E-B009C992A632");
              return;
            }
            await DjiFlySlot.save(id);
            if (context.mounted) Navigator.pop(context);
            if (mounted) setState(() {});
            _snack("Misión fija configurada (${DjiFlySlot.short(id)}…)");
          }

          return AlertDialog(
            title: const Text("Configurar DJI Fly (una sola vez)"),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _step("1", "Crea la misión fija en DJI Fly",
                        "Waypoints › 1 punto cualquiera › guárdala con un nombre como \"OrigenLabs\" y cierra DJI Fly."),
                    _step("2", "Selecciona su archivo aquí",
                        "Toca el botón y busca En mi iPhone › DJI Fly › wayline_mission › la carpeta más reciente › el archivo .kmz."),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                        onPressed: pick,
                        icon: const Icon(Icons.folder_open),
                        label: const Text("Seleccionar el archivo .kmz")),
                    const SizedBox(height: 14),
                    const Text("O pega el nombre de la carpeta:",
                        style: TextStyle(
                            fontSize: 12, color: OrigenColors.textMuted)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: controller,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      decoration: const InputDecoration(
                          hintText: "F93B1A22-88E7-497B-A54E-B009C992A632",
                          isDense: true),
                      onSubmitted: (_) => saveTyped(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!,
                          style: const TextStyle(
                              color: OrigenColors.dangerText, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (DjiFlySlot.current != null)
                TextButton(
                    onPressed: () async {
                      await DjiFlySlot.clear();
                      if (context.mounted) Navigator.pop(context);
                      if (mounted) setState(() {});
                    },
                    child: const Text("Quitar")),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar")),
              FilledButton(onPressed: saveTyped, child: const Text("Guardar")),
            ],
          );
        },
      ),
    );
  }

  void _afterExport(bool dji) {
    if (!mounted) return;
    _snack("Misión exportada");
    final key = dji ? "djiWarningDoNotShow" : "litchiWarningDoNotShow";
    if (!(prefs.getBool(key) ?? false)) {
      showDialog(
          context: context,
          builder: (context) =>
              dji ? const DjiLoadAlert() : const LitchiLoadAlert());
    }
  }

  Future<void> _exportAreaToKml(ValueListenables listenables) async {
    if (listenables.polygon.length < 3) {
      _snack("No hay área para exportar. Dibuja primero el polígono.");
      return;
    }
    var kml = DroneMapperXml();
    kml.polygons = [
      Polygon(
        name: "Área de levantamiento",
        outerBoundaryIs: Rte(
            rtepts: listenables.polygon
                .map((element) =>
                    Wpt(lat: element.latitude, lon: element.longitude))
                .toList()),
      )
    ];
    final ok = await FileSaver.save(
        bytes: Uint8List.fromList(utf8.encode(kml.toKmlString(pretty: true))),
        fileName: "area",
        extension: "kml",
        dialogTitle: "Guardar área");
    _snack(ok ? "Área exportada" : "Exportación cancelada");
  }

  Widget _step(String n, String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: OrigenColors.accent, width: 1.5),
            ),
            child: Text(n,
                style: const TextStyle(
                    color: OrigenColors.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: OrigenColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ValueListenables>(builder: (context, listenables, child) {
      final summary = MissionSummary.of(listenables);
      final missions = summary.segments.length;
      final hasRoute = listenables.photoLocations.isNotEmpty;

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                  color: OrigenColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: listenables.currentMissionId == null
                          ? OrigenColors.accent
                          : OrigenColors.border)),
              child: Row(
                children: [
                  Icon(
                      listenables.currentMissionId == null
                          ? Icons.cloud_off_outlined
                          : Icons.cloud_done_outlined,
                      color: listenables.currentMissionId == null
                          ? OrigenColors.accent
                          : OrigenColors.ok),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            listenables.currentMissionName ??
                                "Misión sin guardar",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                            listenables.currentMissionId == null
                                ? "Guárdala para abrirla luego desde el celular o el computador"
                                : "Disponible en Mis misiones en todos tus dispositivos",
                            style: const TextStyle(
                                fontSize: 12, color: OrigenColors.textMuted)),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => MissionActions.save(context, listenables),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(listenables.currentMissionId == null
                        ? "Guardar"
                        : "Actualizar"),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: OrigenColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: const Color(0xFF3A3218),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.flight_takeoff,
                        color: OrigenColors.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            missions > 1
                                ? "$missions misiones para DJI Fly"
                                : "Misión para DJI Fly",
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(
                            hasRoute
                                ? "${summary.waypoints} puntos · ${fmtNum(summary.totalMinutes, 0)} min · archivo KMZ"
                                : "Primero dibuja el área",
                            style: const TextStyle(
                                fontSize: 12, color: OrigenColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (missions <= 1)
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                    onPressed: hasRoute
                        ? () => _sendToDjiFly(
                            listenables, summary.segments.first, 0, 1)
                        : null,
                    icon: const Icon(Icons.ios_share),
                    label: const Text("Enviar a DJI Fly")),
              )
            else
              for (int i = 0; i < missions; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                        onPressed: () => _sendToDjiFly(listenables,
                            summary.segments[i], i, missions),
                        icon: const Icon(Icons.ios_share),
                        label: Text(
                            "Enviar misión ${i + 1} de $missions · ${summary.segments[i].photos} fotos")),
                  ),
                ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: hasRoute
                          ? () => _export(listenables, dji: true)
                          : null,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text("Descargar KMZ")),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: _configureSlot,
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text("Configurar DJI Fly")),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PanelSection(
              title: "Prueba de campo: comparar giros",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      "Descarga la misma misión en los dos modos de giro y vuela ambas para ver cuál respeta mejor DJI Fly.",
                      style: TextStyle(
                          fontSize: 12, color: OrigenColors.textMuted)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                            onPressed: hasRoute
                                ? () => _export(listenables,
                                    dji: true,
                                    turnMode: TurnMode.curved,
                                    suffix: "_curvo")
                                : null,
                            child: const Text("Giros curvos")),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                            onPressed: hasRoute
                                ? () => _export(listenables,
                                    dji: true,
                                    turnMode: TurnMode.stop,
                                    suffix: "_parada")
                                : null,
                            child: const Text("Parar en cada punto")),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            PanelSection(
              title: "En tu iPhone",
              child: Column(
                children: [
                  if (DjiFlySlot.current == null)
                    _step("0", "Una sola vez: configura DJI Fly",
                        "Toca \"Configurar DJI Fly\" para dejar una misión fija que se reemplaza en cada vuelo.")
                  else
                    _step("✓", "Misión fija: ${DjiFlySlot.short(DjiFlySlot.current!)}…",
                        "El archivo ya sale con el nombre de esa misión."),
                  _step("1", "Toca \"Enviar a DJI Fly\"",
                      "En el menú elige \"Guardar en Archivos\"."),
                  _step("2", "Guárdalo en la carpeta de la misión",
                      DjiFlySlot.current == null
                          ? "En mi iPhone › DJI Fly › wayline_mission › carpeta de la misión. Renombra el archivo igual que la carpeta y toca Reemplazar."
                          : "En mi iPhone › DJI Fly › wayline_mission › carpeta ${DjiFlySlot.short(DjiFlySlot.current!)}… › Guardar › Reemplazar."),
                  _step("3", "Abre DJI Fly y vuela",
                      "Carga la misión fija y revisa la ruta antes de despegar. No la edites ni la guardes dentro de DJI Fly."),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text("Otros formatos",
                style: TextStyle(fontSize: 13, color: OrigenColors.textMuted)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: hasRoute
                          ? () => _export(listenables, dji: false)
                          : null,
                      child: const Text("Litchi (CSV)")),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => _exportAreaToKml(listenables),
                      child: const Text("Área (KML)")),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              "Úsala bajo tu responsabilidad, cumple el RAC 100 de la Aerocivil y detén la misión ante cualquier comportamiento extraño.",
              style: TextStyle(fontSize: 12, color: OrigenColors.textMuted),
            ),
          ],
        ),
      );
    });
  }
}
