import 'dart:convert';

import 'package:ymapper/core/drone_mapper_format.dart';
import 'package:ymapper/core/file_saver.dart';
import 'package:ymapper/core/share/share_file.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/components/origen_widgets.dart';
import 'package:ymapper/shared/mission_summary.dart';
import 'package:ymapper/theme/origen_theme.dart';
import 'package:geoxml/geoxml.dart';
import 'package:ymapper/components/popups/dji_load_alert.dart';
import 'package:ymapper/components/popups/litchi_load_alert.dart';
import 'package:ymapper/main.dart';
import 'package:litchi_waypoint_engine/engine.dart' as litchi;
import 'package:archive/archive.dart';
import 'package:dji_waypoint_engine/engine.dart';
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

  /// Genera el KMZ de DJI Fly para los puntos [start]..[end] (inclusivos).
  Uint8List _buildDjiKmz(ValueListenables listenables, int start, int end,
      {TurnMode? turnMode}) {
    final mode = turnMode ?? listenables.turnMode;
    final segmentPoints = listenables.photoLocations.sublist(start, end + 1);
    final damping = TurnTools.dampingDistances(segmentPoints);
    var missionConfig = MissionConfig(
        flyToWaylineMode: FlyToWaylineMode.safely,
        finishAction: listenables.onFinished,
        // Por normativa: ejecutar la acción de pérdida de señal, no continuar
        exitOnRCLost: ExitOnRCLost.executeLostAction,
        rcLostAction: listenables.rcLostAction,
        globalTransitionalSpeed: listenables.speed,
        // Valor que espera DJI Fly
        droneInfo: DroneInfo(droneEnumValue: 68));

    var template = TemplateKml(
        document: KmlDocumentElement(
            author: "fly",
            creationTime: DateTime.now(),
            modificationTime: DateTime.now(),
            missionConfig: missionConfig));

    var placemarks = <Placemark>[];
    for (int i = start; i <= end; i++) {
      final location = listenables.photoLocations[i];
      final id = i - start;
      placemarks.add(Placemark(
          point: WaypointPoint(
              longitude: location.longitude, latitude: location.latitude),
          index: id,
          height: listenables.altitude,
          speed: listenables.speed,
          headingParam: HeadingParam(
              headingMode: HeadingMode.followWayline,
              headingPathMode: HeadingPathMode.followBadArc),
          // Curvo: "pasa por el punto y gira antes" (líneas rectas, esquinas
          // redondeadas). Parada: se detiene en cada punto.
          turnParam: mode == TurnMode.curved
              ? TurnParam(
                  waypointTurnMode:
                      WaypointTurnMode.toPointAndPassWithContinuityCurvature,
                  turnDampingDistance: damping[id])
              : TurnParam(
                  waypointTurnMode:
                      WaypointTurnMode.toPointAndStopWithDiscontinuityCurvature,
                  turnDampingDistance: 0),
          useStraightLine: true,
          actionGroup: ActionGroup(
              id: 0,
              startIndex: id,
              endIndex: id,
              actions: [
                if (id == 0)
                  Action(
                      id: id,
                      actionFunction: ActionFunction.gimbalEvenlyRotate,
                      actionParams: GimbalRotateParams(
                          pitch: listenables.cameraAngle.toDouble(),
                          payloadPosition: 0)),
                if (listenables.delayAtWaypoint > 0 && _isPhoto(listenables, i))
                  Action(
                      id: id,
                      actionFunction: ActionFunction.hover,
                      actionParams:
                          HoverParams(hoverTime: listenables.delayAtWaypoint)),
                if (_isPhoto(listenables, i))
                  Action(
                      id: id,
                      actionFunction: ActionFunction.takePhoto,
                      actionParams: CameraControlParams(payloadPosition: 0)),
              ],
              mode: ActionMode.sequence,
              trigger: ActionTriggerType.reachPoint)));
    }

    var waylines = WaylinesWpml(
        document: WpmlDocumentElement(
            missionConfig: missionConfig,
            folderElement: FolderElement(
                templateId: 0,
                waylineId: 0,
                speed: listenables.speed,
                placemarks: placemarks)));

    final templateBytes = utf8.encode(template.toXmlString(pretty: true));
    final waylinesBytes = utf8.encode(waylines.toXmlString(pretty: true));

    var archive = Archive();
    archive.addFile(
        ArchiveFile('template.kml', templateBytes.length, templateBytes));
    archive.addFile(
        ArchiveFile('waylines.wpml', waylinesBytes.length, waylinesBytes));
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
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
      final name = segments.length == 1
          ? baseName
          : "${baseName}_m${(index + 1).toString().padLeft(2, '0')}";
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
    final base = (l.currentMissionName ?? "origenlabs_mision")
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áéíóúñ]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safe = base.isEmpty ? "origenlabs_mision" : base;
    return total == 1
        ? "$safe.kmz"
        : "${safe}_m${(index + 1).toString().padLeft(2, '0')}.kmz";
  }

  /// Abre el menú de compartir del iPhone con el KMZ para enviarlo al Atajo
  /// "Enviar a DJI Fly". Debe llamarse directamente desde un toque.
  Future<void> _sendToDjiFly(ValueListenables l, MissionSegment seg,
      int index, int total) async {
    final bytes = _buildDjiKmz(l, seg.start, seg.end);
    final name = _kmzName(l, index, total);
    final result = await shareFile(bytes, name,
        mimeType: "application/vnd.google-earth.kmz");
    switch (result) {
      case ShareResult.shared:
        _snack("Misión enviada. Abre DJI Fly y cárgala.");
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

  void _shortcutGuide() {
    Widget item(String n, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 24,
                  child: Text("$n.",
                      style: const TextStyle(
                          color: OrigenColors.accent,
                          fontWeight: FontWeight.w600))),
              Expanded(
                  child: Text(text,
                      style: const TextStyle(fontSize: 13, height: 1.4))),
            ],
          ),
        );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Crear el Atajo \"Enviar a DJI Fly\""),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    "Se hace una sola vez en la app Atajos del iPhone (unos 5 minutos).",
                    style: TextStyle(
                        fontSize: 13, color: OrigenColors.textMuted)),
                const SizedBox(height: 8),
                item("1",
                    "Abre Atajos, toca + y nombra el atajo \"Enviar a DJI Fly\"."),
                item("2",
                    "Toca el ícono de información (i) y activa \"Mostrar en hoja para compartir\". En los tipos de entrada deja solo \"Archivos\"."),
                item("3",
                    "Agrega \"Obtener contenido de la carpeta\" y elige: En mi iPhone › DJI Fly › wayline_mission."),
                item("4",
                    "Agrega \"Filtrar archivos\": condición Nombre · no es · mission_db. Ordenar por Fecha de modificación, Más reciente primero. Activa Limitar: 1."),
                item("5",
                    "Agrega \"Obtener nombre\" del resultado anterior (es el nombre de la carpeta de la misión vacía)."),
                item("6",
                    "Agrega \"Establecer nombre\" de la Entrada del atajo como: [Nombre].kmz (usa la variable Nombre)."),
                item("7",
                    "Agrega \"Guardar archivo\" con el archivo renombrado. Desactiva \"Preguntar dónde guardar\", elige la carpeta wayline_mission, en Subruta escribe [Nombre]/[Nombre].kmz y activa \"Sobrescribir si el archivo existe\"."),
                item("8", "Agrega \"Abrir app\" y elige DJI Fly."),
                const SizedBox(height: 8),
                const Text(
                    "Uso: crea la misión vacía en DJI Fly y ciérrala; en esta app toca \"Enviar a DJI Fly\" y elige el atajo. Antes de volar, confirma en DJI Fly que la ruta es la correcta.",
                    style: TextStyle(
                        fontSize: 12, color: OrigenColors.textMuted)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Entendido")),
        ],
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
                      onPressed: _shortcutGuide,
                      icon: const Icon(Icons.bolt, size: 18),
                      label: const Text("Crear el Atajo")),
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
                  _step("1", "Crea una misión vacía en DJI Fly",
                      "Waypoints, 1 o 2 puntos cualesquiera. Guárdala y cierra la app por completo."),
                  _step("2", "Toca \"Enviar a DJI Fly\"",
                      "Elige el Atajo \"Enviar a DJI Fly\" en el menú de compartir. Reemplaza el archivo y abre DJI Fly por ti."),
                  _step("3", "Sin Atajo: reemplazo manual",
                      "Descarga el KMZ. En Archivos › DJI Fly › wayline_mission, entra a la carpeta más reciente, renombra el KMZ con el nombre de esa carpeta y reemplázalo."),
                  _step("4", "Abre la misión y vuela",
                      "Revisa la ruta en el mapa de DJI Fly antes de despegar. No la edites ni la guardes allí."),
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
