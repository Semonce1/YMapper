import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ymapper/components/origen_widgets.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/shared/mission_summary.dart';
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:ymapper/theme/origen_theme.dart';

/// Paso 3: resumen de la misión generada y validaciones.
class StepMission extends StatelessWidget {
  const StepMission({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ValueListenables>(builder: (context, l, _) {
      final s = MissionSummary.of(l);
      if (!s.hasArea || s.waypoints == 0) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
              "Todavía no hay ruta. Vuelve al paso Área y marca al menos 3 vértices.",
              style: TextStyle(color: OrigenColors.textMuted)),
        );
      }

      final missions = s.segments.length;
      final maxPerMission = s.segments.fold<int>(
          0, (m, seg) => seg.waypointCount > m ? seg.waypointCount : m);

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StatGrid(children: [
              StatTile(
                  label: "Duración",
                  value: fmtNum(s.totalMinutes, 0),
                  unit: "min"),
              StatTile(
                  label: "Recorrido", value: fmtNum(s.totalKm, 2), unit: "km"),
              StatTile(
                  label: l.createCameraPoints ? "Fotos" : "Intervalo",
                  value: l.createCameraPoints
                      ? "${s.photos}"
                      : fmtNum(s.intervalSec),
                  unit: l.createCameraPoints ? null : "s"),
              StatTile(
                  label: "Waypoints",
                  value: "${s.waypoints}",
                  hint: "máx. ${MissionStats.maxWaypointsPerMission} por misión"),
              StatTile(
                  label: "Baterías",
                  value: "$missions",
                  hint: "${l.batteryMinutes} min c/u"),
              StatTile(label: "GSD", value: fmtNum(s.gsdCm, 2), unit: "cm"),
            ]),
            if (missions > 1) ...[
              const SizedBox(height: 12),
              PanelSection(
                title: "Se divide en $missions misiones",
                child: Column(
                  children: [
                    for (int i = 0; i < missions; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 13,
                              backgroundColor: OrigenColors.accent,
                              child: Text("${i + 1}",
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: OrigenColors.onAccent,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                  "${s.segments[i].photos} fotos · ${s.segments[i].waypointCount} puntos",
                                  style: const TextStyle(fontSize: 13)),
                            ),
                            Text(
                                "${fmtNum(s.segments[i].minutes, 0)} min",
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: OrigenColors.textMuted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            PanelSection(
              title: "Validaciones",
              child: Column(
                children: [
                  StatusLine(
                    ok: !s.selfIntersecting,
                    text: s.selfIntersecting
                        ? "El área tiene lados cruzados. Corrígela en el paso Área."
                        : "Área bien definida",
                  ),
                  StatusLine(
                    ok: l.lineExtension > 0,
                    warn: true,
                    text: l.lineExtension > 0
                        ? "Giros ${l.lineExtension} m fuera del área: las curvas de DJI Fly no afectan las fotos"
                        : "Sin extensión de líneas: en iPhone los giros pueden quedar dentro del área",
                  ),
                  StatusLine(
                    ok: maxPerMission <= MissionStats.maxWaypointsPerMission,
                    text:
                        "Máximo $maxPerMission puntos por misión (límite ${MissionStats.maxWaypointsPerMission})",
                  ),
                  StatusLine(
                    ok: s.blurCm <= s.gsdCm / 2,
                    warn: true,
                    text: s.blurCm <= s.gsdCm / 2
                        ? "Sin foto movida: desplazamiento de ${fmtNum(s.blurCm, 2)} cm a 1/1000 s"
                        : "Riesgo de foto movida: baja la velocidad o sube la altura",
                  ),
                  StatusLine(
                    ok: l.altitude <= 120,
                    text: l.altitude <= 120
                        ? "Altura de ${l.altitude} m, dentro del límite de 120 m (RAC 100)"
                        : "Altura mayor a 120 m: requiere permiso especial de la Aerocivil",
                  ),
                  StatusLine(
                    ok: l.gcps.where((p) => !p.isCheck).length >= 5,
                    warn: true,
                    text: l.gcps.isEmpty
                        ? "Sin puntos de control: el modelo quedará con la precisión del GPS (metros)"
                        : "${l.gcps.where((p) => !p.isCheck).length} puntos de control y ${l.gcps.where((p) => p.isCheck).length} de chequeo cargados",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Ver puntos de foto en el mapa"),
              value: l.showPoints,
              onChanged: (v) => l.showPoints = v,
            ),
          ],
        ),
      );
    });
  }
}
