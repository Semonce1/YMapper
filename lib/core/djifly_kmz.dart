import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:latlong2/latlong.dart';
import 'package:ymapper/core/mission_tools.dart';

/// Genera el KMZ de una misión de waypoints con la misma estructura que
/// produce DJI Fly (verificada contra un archivo real del DJI Air 3):
///   - archivos dentro de la carpeta `wpmz/`
///   - espacio de nombres `http://www.uav.com/wpmz/1.0.2`
///   - primer y último punto con parada; intermedios según [TurnMode]
///   - gimbal: giro absoluto en el punto 0 y giro uniforme entre puntos
class DjiFlyKmz {
  static const _ns = 'http://www.uav.com/wpmz/1.0.2';

  /// Valor que DJI Fly escribe para el Air 3 (igual en el archivo real).
  static const int droneEnumValue = 68;

  static String _missionConfig({
    required String finishAction,
    required String rcLostAction,
    required double speed,
  }) {
    return '''
    <wpml:missionConfig>
      <wpml:flyToWaylineMode>safely</wpml:flyToWaylineMode>
      <wpml:finishAction>$finishAction</wpml:finishAction>
      <wpml:exitOnRCLost>executeLostAction</wpml:exitOnRCLost>
      <wpml:executeRCLostAction>$rcLostAction</wpml:executeRCLostAction>
      <wpml:globalTransitionalSpeed>${_num(speed)}</wpml:globalTransitionalSpeed>
      <wpml:droneInfo>
        <wpml:droneEnumValue>$droneEnumValue</wpml:droneEnumValue>
        <wpml:droneSubEnumValue>0</wpml:droneSubEnumValue>
      </wpml:droneInfo>
    </wpml:missionConfig>''';
  }

  static String _num(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  }

  static String _coord(double v) => v.toStringAsFixed(13);

  static String _gimbalRotate(int actionId, int pitch) => '''
          <wpml:action>
            <wpml:actionId>$actionId</wpml:actionId>
            <wpml:actionActuatorFunc>gimbalRotate</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:gimbalHeadingYawBase>aircraft</wpml:gimbalHeadingYawBase>
              <wpml:gimbalRotateMode>absoluteAngle</wpml:gimbalRotateMode>
              <wpml:gimbalPitchRotateEnable>1</wpml:gimbalPitchRotateEnable>
              <wpml:gimbalPitchRotateAngle>$pitch</wpml:gimbalPitchRotateAngle>
              <wpml:gimbalRollRotateEnable>0</wpml:gimbalRollRotateEnable>
              <wpml:gimbalRollRotateAngle>0</wpml:gimbalRollRotateAngle>
              <wpml:gimbalYawRotateEnable>0</wpml:gimbalYawRotateEnable>
              <wpml:gimbalYawRotateAngle>0</wpml:gimbalYawRotateAngle>
              <wpml:gimbalRotateTimeEnable>0</wpml:gimbalRotateTimeEnable>
              <wpml:gimbalRotateTime>0</wpml:gimbalRotateTime>
              <wpml:payloadPositionIndex>0</wpml:payloadPositionIndex>
            </wpml:actionActuatorFuncParam>
          </wpml:action>''';

  static String _takePhoto(int actionId) => '''
          <wpml:action>
            <wpml:actionId>$actionId</wpml:actionId>
            <wpml:actionActuatorFunc>takePhoto</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:payloadPositionIndex>0</wpml:payloadPositionIndex>
            </wpml:actionActuatorFuncParam>
          </wpml:action>''';

  static String _hover(int actionId, int seconds) => '''
          <wpml:action>
            <wpml:actionId>$actionId</wpml:actionId>
            <wpml:actionActuatorFunc>hover</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:hoverTime>$seconds</wpml:hoverTime>
            </wpml:actionActuatorFuncParam>
          </wpml:action>''';

  static String _evenly(int actionId, int pitch) => '''
          <wpml:action>
            <wpml:actionId>$actionId</wpml:actionId>
            <wpml:actionActuatorFunc>gimbalEvenlyRotate</wpml:actionActuatorFunc>
            <wpml:actionActuatorFuncParam>
              <wpml:gimbalPitchRotateAngle>$pitch</wpml:gimbalPitchRotateAngle>
              <wpml:gimbalRollRotateAngle>0</wpml:gimbalRollRotateAngle>
              <wpml:payloadPositionIndex>0</wpml:payloadPositionIndex>
            </wpml:actionActuatorFuncParam>
          </wpml:action>''';

  static String _group(int groupId, int start, int end, String trigger,
          String mode, String actions) =>
      '''
        <wpml:actionGroup>
          <wpml:actionGroupId>$groupId</wpml:actionGroupId>
          <wpml:actionGroupStartIndex>$start</wpml:actionGroupStartIndex>
          <wpml:actionGroupEndIndex>$end</wpml:actionGroupEndIndex>
          <wpml:actionGroupMode>$mode</wpml:actionGroupMode>
          <wpml:actionTrigger>
            <wpml:actionTriggerType>$trigger</wpml:actionTriggerType>
          </wpml:actionTrigger>
$actions
        </wpml:actionGroup>''';

  /// Construye el KMZ para [points] (ya recortados al tramo de la misión).
  static Uint8List build({
    required List<LatLng> points,
    required List<bool> photoFlags,
    required int altitude,
    required double speed,
    required int gimbalPitch,
    required TurnMode turnMode,
    required int hoverSeconds,
    required String finishAction,
    required String rcLostAction,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final config = _missionConfig(
        finishAction: finishAction, rcLostAction: rcLostAction, speed: speed);

    const d = Distance();
    double distance = 0;
    for (int i = 0; i + 1 < points.length; i++) {
      distance += d.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    final photos = photoFlags.where((f) => f).length;
    final duration = (distance / (speed > 0 ? speed : 1)).round() +
        photos * hoverSeconds;

    final template = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:wpml="$_ns">
  <Document>
    <wpml:author>OrigenLabs</wpml:author>
    <wpml:createTime>${now.toStringAsFixed(5)}</wpml:createTime>
    <wpml:updateTime>${now.toStringAsFixed(5)}</wpml:updateTime>
$config
  </Document>
</kml>
''';

    final buf = StringBuffer();
    int actionId = 0;
    final last = points.length - 1;
    for (int i = 0; i <= last; i++) {
      final p = points[i];
      final isPhoto = i < photoFlags.length ? photoFlags[i] : true;
      final endpoint = i == 0 || i == last;
      final turnName = (endpoint || turnMode == TurnMode.stop)
          ? 'toPointAndStopWithDiscontinuityCurvature'
          : 'toPointAndPassWithContinuityCurvature';

      final groups = StringBuffer();
      // Acciones al llegar al punto: gimbal (solo el primero), pausa, foto
      final reach = StringBuffer();
      if (i == 0) reach.write(_gimbalRotate(actionId++, gimbalPitch));
      if (isPhoto && hoverSeconds > 0) {
        reach.write(_hover(actionId++, hoverSeconds));
      }
      if (isPhoto) reach.write(_takePhoto(actionId++));
      if (reach.isNotEmpty) {
        groups.write(
            _group(0, i, i, 'reachPoint', 'sequence', reach.toString()));
      }
      // Gimbal uniforme hacia el siguiente punto (igual que DJI Fly)
      if (i < last) {
        groups.write(_group(1, i, i + 1, 'betweenAdjacentPoints', 'parallel',
            _evenly(actionId++, gimbalPitch)));
      }

      buf.write('''
      <Placemark>
        <Point>
          <coordinates>
            ${_coord(p.longitude)},${_coord(p.latitude)}
          </coordinates>
        </Point>
        <wpml:index>$i</wpml:index>
        <wpml:executeHeight>$altitude</wpml:executeHeight>
        <wpml:waypointSpeed>${_num(speed)}</wpml:waypointSpeed>
        <wpml:waypointHeadingParam>
          <wpml:waypointHeadingMode>followWayline</wpml:waypointHeadingMode>
          <wpml:waypointHeadingAngle>0</wpml:waypointHeadingAngle>
          <wpml:waypointPoiPoint>0.000000,0.000000,0.000000</wpml:waypointPoiPoint>
          <wpml:waypointHeadingAngleEnable>1</wpml:waypointHeadingAngleEnable>
          <wpml:waypointHeadingPathMode>followBadArc</wpml:waypointHeadingPathMode>
          <wpml:waypointHeadingPoiIndex>0</wpml:waypointHeadingPoiIndex>
        </wpml:waypointHeadingParam>
        <wpml:waypointTurnParam>
          <wpml:waypointTurnMode>$turnName</wpml:waypointTurnMode>
          <wpml:waypointTurnDampingDist>0</wpml:waypointTurnDampingDist>
        </wpml:waypointTurnParam>
        <wpml:useStraightLine>0</wpml:useStraightLine>
$groups
        <wpml:waypointGimbalHeadingParam>
          <wpml:waypointGimbalPitchAngle>$gimbalPitch</wpml:waypointGimbalPitchAngle>
          <wpml:waypointGimbalYawAngle>0</wpml:waypointGimbalYawAngle>
        </wpml:waypointGimbalHeadingParam>
      </Placemark>''');
    }

    final waylines = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:wpml="$_ns">
  <Document>
$config
    <Folder>
      <wpml:templateId>0</wpml:templateId>
      <wpml:executeHeightMode>relativeToStartPoint</wpml:executeHeightMode>
      <wpml:waylineId>0</wpml:waylineId>
      <wpml:distance>${distance.round()}</wpml:distance>
      <wpml:duration>$duration</wpml:duration>
      <wpml:autoFlightSpeed>${_num(speed)}</wpml:autoFlightSpeed>$buf
    </Folder>
  </Document>
</kml>
''';

    final t = utf8.encode(template);
    final w = utf8.encode(waylines);
    final archive = Archive()
      ..addFile(ArchiveFile('wpmz/template.kml', t.length, t))
      ..addFile(ArchiveFile('wpmz/waylines.wpml', w.length, w));
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }
}
