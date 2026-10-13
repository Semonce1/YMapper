import 'package:ymapper/shared/aircraft_settings.dart';
import 'package:dji_waypoint_engine/engine.dart';
import 'package:ymapper/components/text_field.dart';
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AircraftBar extends StatefulWidget {
  const AircraftBar({super.key});

  @override
  State<AircraftBar> createState() => _AircraftBarState();
}

class _AircraftBarState extends State<AircraftBar> {
  void _updateSettings(ValueListenables listenables) {
    AircraftSettings.saveAircraftSettings(AircraftSettings(
      altitude: listenables.altitude,
      groundOffset: listenables.groundOffset,
      speed: listenables.speed,
      forwardOverlap: listenables.forwardOverlap,
      sideOverlap: listenables.sideOverlap,
      rotation: listenables.rotation,
      delay: listenables.delayAtWaypoint,
      cameraAngle: listenables.cameraAngle,
      finishAction: listenables.onFinished,
      rcLostAction: listenables.rcLostAction,
      lineExtension: listenables.lineExtension,
      batteryMinutes: listenables.batteryMinutes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ValueListenables>(builder: (context, listenables, child) {
      return SingleChildScrollView(
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomTextField(
                        labelText: "Altura de vuelo (m)",
                        min: listenables.groundOffset < 10
                            ? 10
                            : listenables.groundOffset + 1,
                        max: 500,
                        onChanged: (m) {
                          listenables.altitude = m.round();
                          _updateSettings(listenables);
                        },
                        defaultValue: listenables.altitude),
                    CustomTextField(
                        labelText: "Altura del objeto sobre el suelo (m)",
                        min: 0,
                        max: listenables.altitude - 1,
                        onChanged: (m) {
                          listenables.groundOffset = m.round();
                          _updateSettings(listenables);
                        },
                        defaultValue: listenables.groundOffset),
                    CustomTextField(
                        labelText: "Velocidad (m/s)",
                        min: 0.1,
                        max: 9,
                        defaultValue: listenables.speed,
                        onChanged: (speed) {
                          listenables.speed = speed;
                          _updateSettings(listenables);
                        },
                        decimals: 1),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomTextField(
                      labelText: "Traslape frontal (%)",
                      min: 1,
                      max: 90,
                      defaultValue: listenables.forwardOverlap,
                      onChanged: (percent) {
                        listenables.forwardOverlap = percent.round();
                        _updateSettings(listenables);
                      },
                    ),
                    CustomTextField(
                      labelText: "Traslape lateral (%)",
                      min: 1,
                      max: 90,
                      defaultValue: listenables.sideOverlap,
                      onChanged: (percent) {
                        listenables.sideOverlap = percent.round();
                        _updateSettings(listenables);
                      },
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      padding: EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Rotación de la grilla (°)"),
                              Text("${listenables.rotation}°"),
                            ],
                          ),
                          Slider(
                            value: listenables.rotation.toDouble(),
                            min: -180,
                            max: 180,
                            divisions: 360,
                            label:
                                '${listenables.rotation.toStringAsFixed(0)}°',
                            onChanged: (value) {
                              setState(() {
                                listenables.rotation = value.round();
                                _updateSettings(listenables);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    CustomTextField(
                      labelText: "Ángulo de cámara (°)",
                      min: -90,
                      max: 0,
                      defaultValue: listenables.cameraAngle,
                      onChanged: (degrees) {
                        listenables.cameraAngle = degrees.round();
                        _updateSettings(listenables);
                      },
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextField(
                      labelText: "Minutos útiles por batería",
                      min: 5,
                      max: 45,
                      defaultValue: listenables.batteryMinutes,
                      onChanged: (minutes) {
                        listenables.batteryMinutes = minutes.round();
                        _updateSettings(listenables);
                      },
                    ),
                    CustomTextField(
                      labelText: "Extensión de líneas fuera del área (m)",
                      min: 0,
                      max: 60,
                      defaultValue: listenables.lineExtension,
                      onChanged: (meters) {
                        listenables.lineExtension = meters.round();
                        _updateSettings(listenables);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        "La extensión agrega un punto de giro sin foto al inicio y al final "
                        "de cada línea, para que las curvas de DJI Fly (sobre todo en iPhone) "
                        "queden fuera del área. Usa 0 para desactivarla.",
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: CustomTextField(
                labelText: "Pausa en cada punto (s)",
                min: 0,
                max: 10,
                defaultValue: listenables.delayAtWaypoint,
                onChanged: (delaySeconds) {
                  listenables.delayAtWaypoint = delaySeconds.round();
                  _updateSettings(listenables);
                },
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    const Align(
                      child: Text(
                        "Al terminar:",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 5.0, runSpacing: 5.0, children: [
                      ChoiceChip(
                          label: const Text('Quedarse en el aire'),
                          selected:
                              listenables.onFinished == FinishAction.noAction,
                          onSelected: (bool selected) {
                            setState(() {
                              listenables.onFinished = FinishAction.noAction;
                            });
                            _updateSettings(listenables);
                          }),
                      ChoiceChip(
                          label: const Text('Regresar a casa'),
                          selected:
                              listenables.onFinished == FinishAction.goHome,
                          onSelected: (bool selected) {
                            setState(() {
                              listenables.onFinished = FinishAction.goHome;
                            });
                            _updateSettings(listenables);
                          }),
                      ChoiceChip(
                          label: const Text('Aterrizar'),
                          selected:
                              listenables.onFinished == FinishAction.autoLand,
                          onSelected: (bool selected) {
                            setState(() {
                              listenables.onFinished = FinishAction.autoLand;
                            });
                            _updateSettings(listenables);
                          }),
                      ChoiceChip(
                          label: const Text('Ir al primer punto'),
                          selected: listenables.onFinished ==
                              FinishAction.gotoFirstWaypoint,
                          onSelected: (bool selected) {
                            setState(() {
                              listenables.onFinished =
                                  FinishAction.gotoFirstWaypoint;
                            });
                            _updateSettings(listenables);
                          })
                    ]),
                    const Divider(),
                    const SizedBox(height: 10),
                    const Align(
                      child: Text(
                        "Si se pierde la señal:",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 5.0, runSpacing: 5.0, children: [
                      ChoiceChip(
                          label: const Text('Quedarse en el aire'),
                          selected:
                              listenables.rcLostAction == RCLostAction.hover,
                          onSelected: (bool selected) {
                            setState(() {
                              listenables.rcLostAction = RCLostAction.hover;
                            });
                            _updateSettings(listenables);
                          }),
                      ChoiceChip(
                          label: const Text('Regresar a casa'),
                          selected:
                              listenables.rcLostAction == RCLostAction.goBack,
                          onSelected: (bool selected) {
                            setState(() {
                              listenables.rcLostAction = RCLostAction.goBack;
                            });
                            _updateSettings(listenables);
                          }),
                      ChoiceChip(
                          label: const Text('Aterrizar'),
                          selected:
                              listenables.rcLostAction == RCLostAction.landing,
                          onSelected: (bool selected) {
                            setState(() {
                              listenables.rcLostAction = RCLostAction.landing;
                            });
                            _updateSettings(listenables);
                          }),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
