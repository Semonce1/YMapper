import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:ymapper/components/origen_widgets.dart';
import 'package:ymapper/core/kml_io.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/shared/map_provider.dart';
import 'package:ymapper/shared/mission_summary.dart';
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:ymapper/theme/origen_theme.dart';

/// Paso 1: ubicar el despegue y dibujar el área.
class StepArea extends StatelessWidget {
  const StepArea({super.key, required this.onLocate, required this.onChanged});

  /// Centra el mapa en la ubicación del usuario.
  final VoidCallback onLocate;

  /// Avisa al mapa que cambió el polígono.
  final VoidCallback onChanged;

  void _fit(BuildContext context, List<LatLng> points) {
    final map = Provider.of<MapProvider>(context, listen: false).mapController;
    map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(60),
        maxZoom: 19));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ValueListenables>(builder: (context, l, _) {
      final s = MissionSummary.of(l);
      final vertices = l.polygon.length;

      String instruction;
      IconData icon;
      if (l.homePoint == null) {
        icon = Icons.home_outlined;
        instruction = "Toca el mapa en el sitio donde vas a despegar.";
      } else if (vertices < 3) {
        icon = Icons.touch_app_outlined;
        instruction =
            "Toca las esquinas del lote en orden, siguiendo el borde ($vertices de mínimo 3).";
      } else {
        icon = Icons.open_with;
        instruction =
            "Arrastra un vértice para moverlo. Mantenlo presionado para borrarlo.";
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: OrigenColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(instruction,
                        style: const TextStyle(fontSize: 14, height: 1.35))),
              ],
            ),
            if (s.selfIntersecting) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                    color: OrigenColors.dangerBg,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                          "Los lados del área se cruzan: los vértices quedaron en desorden.",
                          style: TextStyle(
                              color: OrigenColors.dangerText, fontSize: 13)),
                    ),
                    TextButton(
                        onPressed: () {
                          l.polygon = PolygonTools.sortAroundCentroid(l.polygon);
                          onChanged();
                        },
                        child: const Text("Ordenar")),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ToolButton(
                    icon: Icons.undo,
                    label: "Deshacer",
                    onTap: (vertices == 0 && l.homePoint == null)
                        ? null
                        : () {
                            if (l.polygon.isNotEmpty) {
                              l.polygon = List.of(l.polygon)..removeLast();
                            } else {
                              l.homePoint = null;
                            }
                            onChanged();
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ToolButton(
                    icon: Icons.file_open_outlined,
                    label: "Abrir KML",
                    onTap: () async {
                      final points = await KmlIo.pickPolygon(context);
                      if (points == null || points.length < 3) return;
                      l.polygon = points;
                      if (context.mounted) _fit(context, points);
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ToolButton(
                    icon: Icons.my_location,
                    label: "Mi ubicación",
                    onTap: onLocate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ToolButton(
                    icon: Icons.delete_outline,
                    label: "Borrar",
                    iconColor: OrigenColors.danger,
                    onTap: (vertices == 0 && l.homePoint == null)
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text("¿Borrar el área?"),
                                content: const Text(
                                    "Se quitan el punto de despegue y todos los vértices."),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text("Cancelar")),
                                  FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text("Borrar")),
                                ],
                              ),
                            );
                            if (ok == true) {
                              l.polygon = [];
                              l.homePoint = null;
                              onChanged();
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StatGrid(children: [
              StatTile(
                  label: "Área",
                  value: s.hasArea ? fmtNum(s.areaM2 / 10000, 2) : "–",
                  unit: s.hasArea ? "ha" : null),
              StatTile(
                  label: "Perímetro",
                  value: s.hasArea ? fmtNum(s.perimeterM, 0) : "–",
                  unit: s.hasArea ? "m" : null),
              StatTile(label: "Vértices", value: "$vertices"),
            ]),
          ],
        ),
      );
    });
  }
}
