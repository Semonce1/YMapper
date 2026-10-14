import 'package:ymapper/core/drone_mapping_engine.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/shared/value_listeneables.dart';

/// Números de la misión calculados una sola vez a partir del estado actual.
class MissionSummary {
  final bool hasArea;
  final double areaM2;
  final double perimeterM;
  final double gsdCm;
  final double targetCm;
  final double footprintW;
  final double footprintH;
  final double lineSpacing;
  final double photoSpacing;
  final double intervalSec;
  final String shutter;
  final int photos;
  final int waypoints;
  final List<MissionSegment> segments;
  final bool selfIntersecting;
  final double blurCm;

  /// Tiempo mínimo entre fotos que soporta la cámara en vuelo (s)
  final double minIntervalSec;

  /// Velocidad máxima sugerida (m/s): respeta el intervalo mínimo entre
  /// fotos y un barrido ≤ ½ GSD con obturador de 1/1000 s.
  final double maxSpeed;

  MissionSummary._({
    required this.hasArea,
    required this.areaM2,
    required this.perimeterM,
    required this.gsdCm,
    required this.targetCm,
    required this.footprintW,
    required this.footprintH,
    required this.lineSpacing,
    required this.photoSpacing,
    required this.intervalSec,
    required this.shutter,
    required this.photos,
    required this.waypoints,
    required this.segments,
    required this.selfIntersecting,
    required this.blurCm,
    required this.minIntervalSec,
    required this.maxSpeed,
  });

  double get totalMinutes => segments.fold(0.0, (a, s) => a + s.minutes);
  double get totalKm => segments.fold(0.0, (a, s) => a + s.distanceMeters) / 1000;

  factory MissionSummary.of(ValueListenables l) {
    final hasArea = l.polygon.length > 2;
    final h = (l.altitude - l.groundOffset).toDouble();
    final gsd = MissionStats.gsdCm(
        altitude: h,
        sensorWidth: l.sensorWidth,
        focalLength: l.focalLength,
        imageWidth: l.imageWidth);
    final gsdM = gsd / 100;
    final fpW = gsdM * l.imageWidth;
    final fpH = (l.focalLength > 0 && l.imageHeight > 0)
        ? (h * l.sensorHeight / (l.imageHeight * l.focalLength)) * l.imageHeight
        : 0.0;
    // Igual que el motor: líneas separadas según el alto de la huella y fotos
    // según el ancho (cámara con el lado largo en el sentido de vuelo).
    final lineSpacing = fpH * (1 - l.sideOverlap / 100);
    final photoSpacing = fpW * (1 - l.forwardOverlap / 100);
    final interval = l.speed > 0 ? photoSpacing / l.speed : 0.0;

    List<MissionSegment> segments = [];
    if (hasArea && l.photoLocations.isNotEmpty) {
      segments = MissionStats.split(
        points: l.photoLocations,
        photoFlags: l.photoFlags,
        home: l.homePoint,
        speed: l.speed,
        delaySec: l.delayAtWaypoint,
        batteryMinutes: l.batteryMinutes,
        maxWaypoints: l.startAtHome && l.homePoint != null
            ? MissionStats.maxWaypointsPerMission - 1
            : MissionStats.maxWaypointsPerMission,
      );
    }

    final minInterval = MissionStats.minPhotoIntervalSec(l.imageWidth);
    // Con parada en cada punto la cámara no limita la velocidad, solo el barrido
    final maxSpeed = MissionStats.suggestedMaxSpeed(
        photoSpacing: photoSpacing,
        gsdCm: gsd,
        minIntervalSec: l.turnMode == TurnMode.curved ? minInterval : 1e-6);

    return MissionSummary._(
      hasArea: hasArea,
      areaM2: hasArea ? DroneMappingEngine.calculateArea(l.polygon) : 0,
      perimeterM: hasArea ? PolygonTools.perimeterMeters(l.polygon) : 0,
      gsdCm: gsd,
      targetCm: MissionStats.targetSizeCm(gsd),
      footprintW: fpW,
      footprintH: fpH,
      lineSpacing: lineSpacing,
      photoSpacing: photoSpacing,
      intervalSec: interval,
      shutter: DroneMappingEngine.calculateRecommendedShutterSpeed(
        altitude: l.altitude - l.groundOffset,
        sensorWidth: l.sensorWidth,
        focalLength: l.focalLength,
        imageWidth: l.imageWidth,
        droneSpeed: l.speed,
      ),
      photos: l.createCameraPoints
          ? l.photoFlags.where((f) => f).length
          : 0,
      waypoints: l.photoLocations.length,
      segments: segments,
      selfIntersecting: PolygonTools.isSelfIntersecting(l.polygon),
      // Desplazamiento durante una exposición de 1/1000 s
      blurCm: l.speed * 0.1,
      minIntervalSec: minInterval,
      maxSpeed: maxSpeed,
    );
  }
}

/// Formato numérico colombiano: coma decimal.
String fmtNum(double v, [int decimals = 1]) =>
    v.toStringAsFixed(decimals).replaceAll('.', ',');
