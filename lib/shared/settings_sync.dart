import 'package:ymapper/shared/aircraft_settings.dart';
import 'package:ymapper/shared/value_listeneables.dart';

/// Guarda en el dispositivo los ajustes de vuelo actuales.
void saveFlightSettings(ValueListenables l) {
  AircraftSettings.saveAircraftSettings(AircraftSettings(
    altitude: l.altitude,
    groundOffset: l.groundOffset,
    speed: l.speed,
    forwardOverlap: l.forwardOverlap,
    sideOverlap: l.sideOverlap,
    rotation: l.rotation,
    delay: l.delayAtWaypoint,
    cameraAngle: l.cameraAngle,
    finishAction: l.onFinished,
    rcLostAction: l.rcLostAction,
    lineExtension: l.lineExtension,
    batteryMinutes: l.batteryMinutes,
    turnMode: l.turnMode,
  ));
}
