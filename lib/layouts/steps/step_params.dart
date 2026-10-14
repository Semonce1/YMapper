import 'package:dji_waypoint_engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ymapper/components/origen_widgets.dart';
import 'package:ymapper/core/drone_models.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/main.dart';
import 'package:ymapper/presets/camera_preset.dart';
import 'package:ymapper/presets/preset_manager.dart';
import 'package:ymapper/shared/mission_summary.dart';
import 'package:ymapper/shared/settings_sync.dart';
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:ymapper/theme/origen_theme.dart';

enum SurveyType { ortho, doubleGrid, oblique }

/// Carga un perfil de cámara en el estado de la app.
void applyCameraPreset(ValueListenables l, CameraPreset p) {
  l.selectedCameraPreset = p;
  l.sensorWidth = p.sensorWidth;
  l.sensorHeight = p.sensorHeight;
  l.focalLength = p.focalLength;
  l.imageWidth = p.imageWidth;
  l.imageHeight = p.imageHeight;
  prefs.setString("latestPreset", p.name);
}

/// Paso 2: tipo de levantamiento y parámetros de vuelo.
class StepParams extends StatelessWidget {
  const StepParams({super.key});

  static SurveyType currentType(ValueListenables l) {
    if (!l.fillGrid) return SurveyType.ortho;
    return l.cameraAngle <= -80 ? SurveyType.doubleGrid : SurveyType.oblique;
  }

  void _setType(ValueListenables l, SurveyType t) {
    switch (t) {
      case SurveyType.ortho:
        l.fillGrid = false;
        l.cameraAngle = -90;
      case SurveyType.doubleGrid:
        l.fillGrid = true;
        l.cameraAngle = -90;
      case SurveyType.oblique:
        l.fillGrid = true;
        l.cameraAngle = -60;
    }
    saveFlightSettings(l);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ValueListenables>(builder: (context, l, _) {
      final s = MissionSummary.of(l);
      final type = currentType(l);
      final typeHint = switch (type) {
        SurveyType.ortho =>
          "Cámara vertical (−90°). Para ortofoto, topografía y curvas de nivel.",
        SurveyType.doubleGrid =>
          "Dos pasadas cruzadas con cámara vertical. Mejor MDT y bordes más limpios; doble tiempo.",
        SurveyType.oblique =>
          "Dos pasadas cruzadas con cámara a −60°. Para modelos 3D con fachadas y taludes.",
      };

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DroneCard(l: l),
            const SizedBox(height: 12),
            SegmentedChoice<SurveyType>(
              options: const [
                (SurveyType.ortho, "Ortofoto"),
                (SurveyType.doubleGrid, "Doble grilla"),
                (SurveyType.oblique, "Oblicuo 3D"),
              ],
              selected: type,
              onSelected: (t) => _setType(l, t),
            ),
            const SizedBox(height: 6),
            Text(typeHint,
                style: const TextStyle(
                    fontSize: 12, color: OrigenColors.textMuted)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                  color: OrigenColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Resolución (GSD)",
                            style: TextStyle(
                                fontSize: 12, color: OrigenColors.textMuted)),
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: fmtNum(s.gsdCm, 2),
                              style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w600,
                                  color: OrigenColors.accent)),
                          const TextSpan(
                              text: " cm/px",
                              style: TextStyle(
                                  fontSize: 14,
                                  color: OrigenColors.textMuted)),
                        ])),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("Huella de la foto",
                          style: TextStyle(
                              fontSize: 12, color: OrigenColors.textMuted)),
                      Text(
                          "${fmtNum(s.footprintW, 0)} × ${fmtNum(s.footprintH, 0)} m",
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PanelSection(
              child: Column(
                children: [
                  LabeledSlider(
                    label: "Altura de vuelo",
                    unit: " m",
                    value: l.altitude.toDouble(),
                    min: 20,
                    max: 120,
                    divisions: 20,
                    onChanged: (v) {
                      l.altitude = v.round();
                      saveFlightSettings(l);
                    },
                  ),
                  LabeledSlider(
                    label: "Traslape frontal",
                    unit: " %",
                    value: l.forwardOverlap.toDouble(),
                    min: 60,
                    max: 90,
                    divisions: 6,
                    onChanged: (v) {
                      l.forwardOverlap = v.round();
                      saveFlightSettings(l);
                    },
                  ),
                  LabeledSlider(
                    label: "Traslape lateral",
                    unit: " %",
                    value: l.sideOverlap.toDouble(),
                    min: 50,
                    max: 85,
                    divisions: 7,
                    onChanged: (v) {
                      l.sideOverlap = v.round();
                      saveFlightSettings(l);
                    },
                  ),
                  LabeledSlider(
                    label: "Velocidad",
                    unit: " m/s",
                    decimals: 1,
                    value: l.speed,
                    min: 2,
                    max: 12,
                    divisions: 20,
                    onChanged: (v) {
                      l.speed = double.parse(v.toStringAsFixed(1));
                      saveFlightSettings(l);
                    },
                  ),
                  _SpeedHint(l: l, s: s),
                  LabeledSlider(
                    label: "Dirección de las líneas",
                    unit: "°",
                    value: l.rotation.toDouble(),
                    min: -90,
                    max: 90,
                    divisions: 36,
                    onChanged: (v) {
                      l.rotation = v.round();
                      saveFlightSettings(l);
                    },
                  ),
                  _AlignButton(l: l),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text("Tipo de giro",
                style: TextStyle(fontSize: 13, color: OrigenColors.textMuted)),
            const SizedBox(height: 6),
            SegmentedChoice<TurnMode>(
              options: const [
                (TurnMode.curved, "Curvo continuo"),
                (TurnMode.stop, "Parar en cada punto"),
              ],
              selected: l.turnMode,
              onSelected: (m) {
                l.turnMode = m;
                saveFlightSettings(l);
              },
            ),
            const SizedBox(height: 6),
            Text(
                l.turnMode == TurnMode.curved
                    ? "Igual que DJI Fly: el dron pasa por los puntos sin detenerse y suaviza los giros, que quedan fuera del área. Más rápido y rinde más la batería."
                    : "El dron se detiene en cada punto, toma la foto y sigue en línea recta. Más lento, máxima precisión de posición.",
                style: const TextStyle(
                    fontSize: 12, color: OrigenColors.textMuted)),
            const SizedBox(height: 12),
            StatGrid(columns: 2, children: [
              StatTile(
                  label: "Separación entre líneas",
                  value: fmtNum(s.lineSpacing),
                  unit: "m"),
              StatTile(
                  label: "Distancia entre fotos",
                  value: fmtNum(s.photoSpacing),
                  unit: "m"),
              StatTile(
                  label: "Obturador recomendado",
                  value: s.shutter,
                  hint: "o más rápido"),
              StatTile(
                  label: "Ángulo de cámara",
                  value: "${l.cameraAngle}",
                  unit: "°"),
            ]),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text("Ajustes avanzados",
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    "${l.selectedCameraPreset?.name ?? "Cámara"} · ${l.batteryMinutes} min por batería",
                    style: const TextStyle(
                        fontSize: 12, color: OrigenColors.textMuted)),
                children: [_Advanced(l: l)],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _Advanced extends StatelessWidget {
  const _Advanced({required this.l});
  final ValueListenables l;

  @override
  Widget build(BuildContext context) {
    final presets = PresetManager.getPresets();
    final selected = presets.firstWhere(
        (p) => p.name == l.selectedCameraPreset?.name,
        orElse: () => presets.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey("preset-${selected.name}"),
          initialValue: selected.name,
          isExpanded: true,
          decoration: const InputDecoration(labelText: "Cámara"),
          items: [
            for (final p in presets)
              DropdownMenuItem(value: p.name, child: Text(p.name)),
          ],
          onChanged: (name) {
            applyCameraPreset(l, presets.firstWhere((e) => e.name == name));
            l.droneId =
                DroneModels.forPreset(name)?.id ?? DroneModels.customId;
            saveFlightSettings(l);
          },
        ),
        const SizedBox(height: 4),
        const Text(
            "Para el Air 3 se recomienda 12 MP: fotos más livianas y disparo más rápido.",
            style: TextStyle(fontSize: 12, color: OrigenColors.textMuted)),
        const SizedBox(height: 12),
        PanelSection(
          child: Column(
            children: [
              LabeledSlider(
                label: "Minutos útiles por batería",
                unit: " min",
                value: l.batteryMinutes.toDouble(),
                min: 10,
                max: 40,
                divisions: 30,
                onChanged: (v) {
                  l.batteryMinutes = v.round();
                  saveFlightSettings(l);
                },
              ),
              LabeledSlider(
                label: "Extensión de líneas (giros)",
                unit: " m",
                value: l.lineExtension.toDouble(),
                min: 0,
                max: 50,
                divisions: 10,
                onChanged: (v) {
                  l.lineExtension = v.round();
                  saveFlightSettings(l);
                },
              ),
              LabeledSlider(
                label: "Margen de fotos fuera del área",
                unit: " m",
                value: l.areaMargin.toDouble(),
                min: 0,
                max: 40,
                divisions: 8,
                onChanged: (v) {
                  l.areaMargin = v.round();
                  saveFlightSettings(l);
                },
              ),
              LabeledSlider(
                label: "Altura del objeto sobre el suelo",
                unit: " m",
                value: l.groundOffset.toDouble(),
                min: 0,
                max: (l.altitude - 10).clamp(0, 100).toDouble(),
                onChanged: (v) {
                  l.groundOffset = v.round();
                  saveFlightSettings(l);
                },
              ),
              LabeledSlider(
                label: "Pausa en cada foto",
                unit: " s",
                value: l.delayAtWaypoint.toDouble(),
                min: 0,
                max: 5,
                divisions: 5,
                onChanged: (v) {
                  l.delayAtWaypoint = v.round();
                  saveFlightSettings(l);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
            l.areaMargin == 0
                ? "Margen 0: todos los centros de foto quedan dentro del área. Súbelo para que los bordes del modelo salgan completos (en oblicuo 3D usa 30–35 m)."
                : "Toma fotos hasta ${l.areaMargin} m por fuera del borde: bordes del modelo más completos, a cambio de más fotos.",
            style: const TextStyle(fontSize: 12, color: OrigenColors.textMuted)),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: l.startAtHome,
          title: const Text("Primer punto sobre el Home",
              style: TextStyle(fontSize: 14)),
          subtitle: Text(
              l.homePoint == null
                  ? "Marca el Home en el mapa para usar esta opción."
                  : "Cada misión arranca con un punto sin foto sobre el Home: el dron sube ahí antes de ir al área.",
              style: const TextStyle(
                  fontSize: 12, color: OrigenColors.textMuted)),
          onChanged: (v) {
            l.startAtHome = v;
            saveFlightSettings(l);
          },
        ),
        const SizedBox(height: 8),
        const Text("Al terminar la misión",
            style: TextStyle(fontSize: 13, color: OrigenColors.textMuted)),
        const SizedBox(height: 6),
        SegmentedChoice<FinishAction>(
          options: const [
            (FinishAction.goHome, "Regresar"),
            (FinishAction.noAction, "Quedarse"),
            (FinishAction.autoLand, "Aterrizar"),
          ],
          selected: l.onFinished,
          onSelected: (v) {
            l.onFinished = v;
            saveFlightSettings(l);
          },
        ),
        const SizedBox(height: 12),
        const Text("Si se pierde la señal",
            style: TextStyle(fontSize: 13, color: OrigenColors.textMuted)),
        const SizedBox(height: 6),
        SegmentedChoice<RCLostAction>(
          options: const [
            (RCLostAction.goBack, "Regresar"),
            (RCLostAction.hover, "Quedarse"),
            (RCLostAction.landing, "Aterrizar"),
          ],
          selected: l.rcLostAction,
          onSelected: (v) {
            l.rcLostAction = v;
            saveFlightSettings(l);
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}


/// Selector de dron y resolución de foto.
class _DroneCard extends StatelessWidget {
  const _DroneCard({required this.l});
  final ValueListenables l;

  void _selectDrone(String id) {
    final drone = DroneModels.byId(id);
    l.droneId = drone.id;
    final presets = PresetManager.getPresets();
    final match = presets.where((p) => drone.presets.contains(p.name));
    if (match.isNotEmpty) {
      // Perfil recomendado (12 MP)
      applyCameraPreset(
          l, presets.firstWhere((p) => p.name == drone.presets.first));
    }
    saveFlightSettings(l);
  }

  @override
  Widget build(BuildContext context) {
    final drone = DroneModels.byId(l.droneId);
    final presets = PresetManager.getPresets()
        .where((p) => drone.presets.contains(p.name))
        .toList();
    final selectedPreset = l.selectedCameraPreset?.name;
    final icon = switch (drone.support) {
      DroneSupport.verified => Icons.verified_outlined,
      DroneSupport.compatible => Icons.info_outline,
      DroneSupport.litchiOnly => Icons.warning_amber_rounded,
    };
    final color = switch (drone.support) {
      DroneSupport.verified => OrigenColors.ok,
      DroneSupport.compatible => OrigenColors.textMuted,
      DroneSupport.litchiOnly => OrigenColors.check,
    };

    return PanelSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey("drone-${drone.id}"),
            initialValue: drone.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: "Dron"),
            items: [
              for (final d in DroneModels.all)
                DropdownMenuItem(value: d.id, child: Text(d.name)),
            ],
            onChanged: (id) {
              if (id != null) _selectDrone(id);
            },
          ),
          if (presets.length > 1) ...[
            const SizedBox(height: 10),
            SegmentedChoice<String>(
              options: [
                for (final p in presets)
                  (
                    p.name,
                    p == presets.first
                        ? "${DroneModels.presetLabel(p.name)} (recom.)"
                        : DroneModels.presetLabel(p.name)
                  ),
              ],
              selected: presets.any((p) => p.name == selectedPreset)
                  ? selectedPreset!
                  : presets.first.name,
              onSelected: (name) {
                applyCameraPreset(
                    l, presets.firstWhere((p) => p.name == name));
              },
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(drone.supportText,
                    style: TextStyle(fontSize: 12, color: color)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Velocidad máxima sugerida bajo el control de velocidad.
class _SpeedHint extends StatelessWidget {
  const _SpeedHint({required this.l, required this.s});
  final ValueListenables l;
  final MissionSummary s;

  @override
  Widget build(BuildContext context) {
    if (s.maxSpeed <= 0) return const SizedBox.shrink();
    final tooFast = l.speed > s.maxSpeed + 0.01;
    final reason = l.turnMode == TurnMode.curved
        ? "foto cada ≥ ${fmtNum(s.minIntervalSec, 0)} s y nitidez a 1/1000 s"
        : "nitidez a 1/1000 s";
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(tooFast ? Icons.warning_amber_rounded : Icons.speed,
              size: 16,
              color: tooFast ? OrigenColors.check : OrigenColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                "Máx. sugerida ${fmtNum(s.maxSpeed)} m/s ($reason)",
                style: TextStyle(
                    fontSize: 12,
                    color:
                        tooFast ? OrigenColors.check : OrigenColors.textMuted)),
          ),
          if (tooFast)
            TextButton(
              onPressed: () {
                l.speed = s.maxSpeed.clamp(2.0, 12.0);
                saveFlightSettings(l);
              },
              child: Text("Usar ${fmtNum(s.maxSpeed.clamp(2.0, 12.0))}"),
            ),
        ],
      ),
    );
  }
}

/// Alinea las líneas de vuelo con los lados del área (del más largo al más
/// corto): menos giros y más batería útil.
class _AlignButton extends StatelessWidget {
  const _AlignButton({required this.l});
  final ValueListenables l;

  @override
  Widget build(BuildContext context) {
    final rots = PolygonTools.edgeRotations(l.polygon);
    if (rots.isEmpty) return const SizedBox.shrink();
    final current = l.rotation == -90 ? 90 : l.rotation;
    final idx = rots.indexOf(current);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          l.rotation = idx < 0 ? rots.first : rots[(idx + 1) % rots.length];
          saveFlightSettings(l);
        },
        icon: const Icon(Icons.straighten, size: 18),
        label: Text(idx < 0
            ? "Alinear con el lado más largo"
            : rots.length == 1
                ? "Alineado con el lado más largo"
                : "Alineado con el lado ${idx + 1} de ${rots.length} · siguiente"),
      ),
    );
  }
}
