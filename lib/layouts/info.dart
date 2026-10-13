import 'package:ymapper/core/drone_mapping_engine.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Info extends StatefulWidget {
  const Info({super.key});

  @override
  State<Info> createState() => _InfoState();
}

class _InfoState extends State<Info> {
  String _fmt(double v, [int decimals = 1]) =>
      v.toStringAsFixed(decimals).replaceAll('.', ',');

  Widget _stat(BuildContext context, String label, String value,
      {String? hint, Color? valueColor}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? scheme.onSurface)),
          if (hint != null)
            Text(hint,
                style:
                    TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(child:
        Consumer<ValueListenables>(builder: (context, listenables, child) {
      final scheme = Theme.of(context).colorScheme;
      final hasArea = listenables.polygon.length > 2;

      final effectiveAltitude =
          (listenables.altitude - listenables.groundOffset).toDouble();
      final gsd = MissionStats.gsdCm(
        altitude: effectiveAltitude,
        sensorWidth: listenables.sensorWidth,
        focalLength: listenables.focalLength,
        imageWidth: listenables.imageWidth,
      );
      final target = MissionStats.targetSizeCm(gsd);

      var area = 0.0;
      var recommendedShutterSpeed = "-";
      var photoTimeInterval = 0.0;
      var photos = 0;
      final waypoints = listenables.photoLocations.length;
      List<MissionSegment> segments = [];

      if (hasArea) {
        area = DroneMappingEngine.calculateArea(listenables.polygon);
        recommendedShutterSpeed =
            DroneMappingEngine.calculateRecommendedShutterSpeed(
          altitude: listenables.altitude - listenables.groundOffset,
          sensorWidth: listenables.sensorWidth,
          focalLength: listenables.focalLength,
          imageWidth: listenables.imageWidth,
          droneSpeed: listenables.speed,
        );
        photoTimeInterval = DroneMappingEngine.calculatePhotoTimeInterval(
          altitude: listenables.altitude,
          sensorHeight: listenables.sensorHeight,
          focalLength: listenables.focalLength,
          imageHeight: listenables.imageHeight,
          forwardOverlap: listenables.forwardOverlap / 100.0,
          droneSpeed: listenables.speed,
          groundOffset: listenables.groundOffset,
        );
        if (listenables.createCameraPoints) {
          photos = listenables.photoFlags.where((f) => f).length;
        }
        segments = MissionStats.split(
          points: listenables.photoLocations,
          photoFlags: listenables.photoFlags,
          home: listenables.homePoint,
          speed: listenables.speed,
          delaySec: listenables.delayAtWaypoint,
          batteryMinutes: listenables.batteryMinutes,
        );
      }

      final totalMinutes = segments.fold<double>(0, (a, s) => a + s.minutes);
      final totalDistance =
          segments.fold<double>(0, (a, s) => a + s.distanceMeters);
      final tooManyPoints = segments.length > 1 &&
          waypoints > MissionStats.maxWaypointsPerMission;

      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasArea)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    "1. Toca el mapa para fijar el punto de despegue.\n"
                    "2. Toca de nuevo para marcar los vértices del área (mínimo 3).\n"
                    "3. Ajusta altura y traslapes en la pestaña Vuelo.",
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            GridView.count(
              crossAxisCount:
                  MediaQuery.of(context).size.width < 700 ? 3 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                _stat(context, "GSD", "${_fmt(gsd, 2)} cm/px"),
                _stat(context, "Diana GCP mín.", "${_fmt(target, 0)} cm"),
                _stat(context, "Área",
                    hasArea ? "${_fmt(area / 10000, 2)} ha" : "-"),
                _stat(context, "Duración",
                    hasArea ? "${_fmt(totalMinutes, 0)} min" : "-"),
                _stat(context, "Recorrido",
                    hasArea ? "${_fmt(totalDistance / 1000, 2)} km" : "-"),
                _stat(
                    context,
                    listenables.createCameraPoints ? "Fotos" : "Intervalo",
                    hasArea
                        ? (listenables.createCameraPoints
                            ? "$photos"
                            : "${_fmt(photoTimeInterval)} s")
                        : "-"),
                _stat(context, "Waypoints", hasArea ? "$waypoints" : "-",
                    hint: "máx. ${MissionStats.maxWaypointsPerMission} por misión",
                    valueColor: tooManyPoints ? scheme.error : null),
                _stat(context, "Misiones / baterías",
                    hasArea ? "${segments.length}" : "-",
                    hint: "${listenables.batteryMinutes} min por batería"),
                _stat(context, "Obturador", hasArea ? recommendedShutterSpeed : "-",
                    hint: "o más rápido"),
              ],
            ),
            if (segments.length > 1) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    "La ruta se dividirá en ${segments.length} misiones al exportar "
                    "(límite de waypoints de DJI Fly o duración de la batería). "
                    "Vuélalas en orden; cada una retoma donde terminó la anterior.",
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
                title: const Text("Tomar foto en cada punto"),
                subtitle: const Text(
                    "Recomendado. Si lo apagas, usa disparo por intervalo en la cámara."),
                value: listenables.createCameraPoints,
                onChanged: (value) {
                  setState(() {
                    listenables.createCameraPoints = value;
                  });
                }),
            SwitchListTile(
                title: Text((listenables.createCameraPoints)
                    ? "Mostrar puntos de foto"
                    : "Mostrar waypoints"),
                value: listenables.showPoints,
                onChanged: (value) {
                  setState(() {
                    listenables.showPoints = value;
                  });
                }),
            SwitchListTile(
                title: const Text("Doble grilla (cuadrícula cruzada)"),
                subtitle: const Text("Mejora el modelo 3D; duplica el tiempo de vuelo."),
                value: listenables.fillGrid,
                onChanged: (value) {
                  setState(() {
                    listenables.fillGrid = value;
                  });
                }),
          ],
        ),
      );
    }));
  }
}
