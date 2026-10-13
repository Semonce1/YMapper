import 'dart:convert';

import 'package:ymapper/core/drone_mapper_format.dart';
import 'package:ymapper/core/file_saver.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/shared/map_provider.dart';
import 'package:flutter_map/flutter_map.dart' hide Polygon;
import 'package:geoxml/geoxml.dart';
import 'package:latlong2/latlong.dart';
import 'package:universal_io/io.dart';
import 'package:ymapper/components/popups/dji_load_alert.dart';
import 'package:ymapper/components/popups/litchi_load_alert.dart';
import 'package:ymapper/main.dart';
import 'package:litchi_waypoint_engine/engine.dart' as litchi;
import 'package:archive/archive.dart';
import 'package:dji_waypoint_engine/engine.dart';
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:file_picker/file_picker.dart';
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
  Uint8List _buildDjiKmz(ValueListenables listenables, int start, int end) {
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
          turnParam: TurnParam(
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

  Future<void> _export(ValueListenables listenables, {required bool dji}) async {
    if (listenables.photoLocations.isEmpty) {
      _snack("No hay ruta para exportar. Dibuja primero el área.");
      return;
    }
    final segments = _segments(listenables);
    final ext = dji ? "kmz" : "csv";
    final baseName = dji ? "origenlabs_mision" : "origenlabs_litchi";

    Future<bool> saveSegment(int index) {
      final seg = segments[index];
      final bytes = dji
          ? _buildDjiKmz(listenables, seg.start, seg.end)
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

  Future<void> _importFromKml(ValueListenables listenables) async {
    var file = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["kml"],
        withData: true,
        dialogTitle: "Cargar área");

    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("No se eligió archivo. Importación cancelada")));
      }
      return;
    }

    late DroneMapperXml kml;

    if (kIsWeb) {
      kml = await DroneMapperXml.fromKmlString(
          String.fromCharCodes(file.files.first.bytes!));
    } else {
      kml = await DroneMapperXml.fromKmlString(
          await File(file.files.single.path!).readAsString());
    }

    if (kml.polygons.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("El KML no tiene polígonos. Importación cancelada")));
      return;
    } else if (kml.polygons.length > 1) {
      if (mounted) {
        int selectedPolygon = 0;
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text("Elige el polígono"),
              content: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                          "El KML tiene varios polígonos, elige uno"),
                      const Divider(),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        width: 400,
                        child: ListView.separated(
                          itemCount: kml.polygons.length,
                          itemBuilder: (context, index) => CheckboxListTile(
                            value: selectedPolygon == index,
                            onChanged: (value) {
                              setState(() {
                                selectedPolygon = index;
                              });
                            },
                            title: Text(
                                kml.polygons[index].name ?? "Polígono $index"),
                          ),
                          separatorBuilder: (context, index) => const Divider(),
                          shrinkWrap: true,
                        ),
                      ),
                    ],
                  );
                },
              ),
              actions: [
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text("Cancelar")),
                FilledButton(
                    onPressed: () {
                      // Ensure a polygon is selected before proceeding
                      if (selectedPolygon >= 0 &&
                          selectedPolygon < kml.polygons.length) {
                        _loadPolygon(
                          kml.polygons[selectedPolygon].outerBoundaryIs.rtepts
                              .map((e) => LatLng(e.lat!, e.lon!))
                              .toList(),
                        );
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text("Cargar")),
              ],
            );
          },
        );
      }
      return;
    } else {
      _loadPolygon(kml.polygons.first.outerBoundaryIs.rtepts
          .map((e) => LatLng(e.lat!, e.lon!))
          .toList());
      return;
    }
  }

  Future<void> _loadPolygon(List<LatLng> polygon) async {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final mapController = mapProvider.mapController;

    Provider.of<ValueListenables>(context, listen: false).polygon = polygon;

    if (polygon.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(polygon);

      mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80),
          maxZoom: 18.0,
        ),
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Área importada")),
      );
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Consumer<ValueListenables>(builder: (context, listenables, child) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("Exportar la misión",
                  style: TextStyle(fontSize: 20)),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                  onPressed: () => _export(listenables, dji: true),
                  child: const Text("Guardar para DJI Fly (KMZ)")),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                  onPressed: () => _export(listenables, dji: false),
                  child: const Text("Guardar para Litchi (CSV)")),
            ),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("Importar o exportar el área",
                  style: TextStyle(fontSize: 20)),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Tooltip(
                    message: "Reemplaza el área actual",
                    child: ElevatedButton(
                        onPressed: () => _importFromKml(listenables),
                        child: const Text("Importar KML")),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: ElevatedButton(
                      onPressed: () => _exportAreaToKml(listenables),
                      child: const Text("Exportar KML")),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                    border: Border.all(
                        width: 3,
                        color:
                            Theme.of(context).colorScheme.error.withAlpha(127)),
                    color: Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withAlpha(25),
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Text(
                        "Advertencia",
                        style: TextStyle(
                            fontSize: 20,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Revisa la ruta en DJI Fly antes de despegar. Úsala bajo tu responsabilidad y cumple el RAC 100 de la Aerocivil.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Si notas cualquier problema durante el vuelo, detén la misión de inmediato.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            )
          ],
        );
      }),
    );
  }
}
