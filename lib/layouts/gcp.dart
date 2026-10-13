import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:universal_io/io.dart';
import 'package:ymapper/core/file_saver.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/shared/map_provider.dart';
import 'package:ymapper/shared/value_listeneables.dart';

/// Pestaña de puntos de control (GCP) y de chequeo.
class GcpBar extends StatefulWidget {
  const GcpBar({super.key});

  @override
  State<GcpBar> createState() => _GcpBarState();
}

class _GcpBarState extends State<GcpBar> {
  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _applyText(ValueListenables listenables, String text) {
    final result = GcpParser.parse(text, listenables.gcpCrs);
    if (result.points.isEmpty) {
      _snack(result.errors.isNotEmpty
          ? "No se importó ningún punto. ${result.errors.first}"
          : "No se encontraron puntos en el archivo");
      return;
    }
    listenables.gcps = result.points;

    final bounds =
        LatLngBounds.fromPoints(result.points.map((p) => p.position).toList());
    Provider.of<MapProvider>(context, listen: false).mapController.fitCamera(
        CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(80),
            maxZoom: 18));

    final skipped = result.errors.isEmpty
        ? ""
        : " (${result.errors.length} líneas omitidas: ${result.errors.first})";
    _snack("${result.points.length} puntos importados$skipped");
  }

  Future<void> _importFile(ValueListenables listenables) async {
    final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["csv", "txt"],
        withData: true,
        dialogTitle: "Importar puntos de control");
    if (picked == null || picked.files.isEmpty) {
      _snack("Importación cancelada");
      return;
    }
    final file = picked.files.first;
    String text;
    if (file.bytes != null) {
      text = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (!kIsWeb && file.path != null) {
      text = await File(file.path!).readAsString();
    } else {
      _snack("No se pudo leer el archivo");
      return;
    }
    _applyText(listenables, text);
  }

  Future<void> _pasteDialog(ValueListenables listenables) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Pegar puntos"),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 10,
            autofocus: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "GCP1, 2250112.40, 4712305.18, 1512.36\n"
                  "CHK1, 2250078.30, 4712372.10, 1507.22, chequeo",
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar")),
          FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _applyText(listenables, controller.text);
              },
              child: const Text("Importar")),
        ],
      ),
    );
  }

  Future<void> _exportCoordinates(ValueListenables listenables) async {
    if (listenables.gcps.isEmpty) {
      _snack("Primero importa los puntos de control");
      return;
    }
    final text =
        GcpParser.toCoordinatesFile(listenables.gcps, listenables.gcpCrs);
    final ok = await FileSaver.save(
        bytes: Uint8List.fromList(utf8.encode(text)),
        fileName: "gcp_coordenadas",
        extension: "txt",
        mimeType: "text/plain",
        dialogTitle: "Guardar coordenadas de GCP");
    _snack(ok ? "Archivo de coordenadas guardado" : "Exportación cancelada");
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ValueListenables>(builder: (context, listenables, _) {
      final scheme = Theme.of(context).colorScheme;
      final control = listenables.gcps.where((p) => !p.isCheck).length;
      final checks = listenables.gcps.where((p) => p.isCheck).length;
      final gsd = MissionStats.gsdCm(
        altitude:
            (listenables.altitude - listenables.groundOffset).toDouble(),
        sensorWidth: listenables.sensorWidth,
        focalLength: listenables.focalLength,
        imageWidth: listenables.imageWidth,
      );
      final decimals = listenables.gcpCrs == GcpCrs.wgs84 ? 7 : 2;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: DropdownButtonFormField<GcpCrs>(
                initialValue: listenables.gcpCrs,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: "Sistema de coordenadas",
                    border: OutlineInputBorder()),
                items: [
                  for (final crs in GcpCrs.values)
                    DropdownMenuItem(value: crs, child: Text(crs.label)),
                ],
                onChanged: (crs) {
                  if (crs == null) return;
                  listenables.gcpCrs = crs;
                  if (listenables.gcps.isNotEmpty) {
                    listenables.gcps = [];
                    _snack("Sistema cambiado: vuelve a importar los puntos");
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                listenables.gcpCrs == GcpCrs.wgs84
                    ? "Formato: Nombre, Latitud, Longitud, Cota [, tipo]"
                    : "Formato: Nombre, Norte, Este, Cota [, tipo]. "
                        "Tipo \"chequeo\" o nombres que empiecen por CHK se toman como puntos de chequeo.",
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                    onPressed: () => _importFile(listenables),
                    icon: const Icon(Icons.upload_file),
                    label: const Text("Importar CSV")),
                OutlinedButton.icon(
                    onPressed: () => _pasteDialog(listenables),
                    icon: const Icon(Icons.content_paste),
                    label: const Text("Pegar")),
                OutlinedButton.icon(
                    onPressed: listenables.gcps.isEmpty
                        ? null
                        : () => _exportCoordinates(listenables),
                    icon: const Icon(Icons.file_download),
                    label: const Text("Coordenadas")),
                if (listenables.gcps.isNotEmpty)
                  TextButton.icon(
                      onPressed: () => listenables.gcps = [],
                      icon: const Icon(Icons.delete_outline),
                      label: const Text("Quitar")),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text("Control: $control",
                        style: const TextStyle(color: Colors.lightBlueAccent)),
                    Text("Chequeo: $checks",
                        style: const TextStyle(color: Colors.orange)),
                    Text(
                        "Diana mínima: ${MissionStats.targetSizeCm(gsd).toStringAsFixed(0)} cm"),
                  ],
                ),
              ),
            ),
            if (listenables.gcps.isNotEmpty && control < 5)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  "Se recomiendan al menos 5 puntos de control repartidos en el perímetro y el centro.",
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ),
            for (final p in listenables.gcps)
              ListTile(
                dense: true,
                leading: Icon(Icons.change_history,
                    color:
                        p.isCheck ? Colors.orange : Colors.lightBlueAccent),
                title: Text(p.name),
                subtitle: Text(listenables.gcpCrs == GcpCrs.wgs84
                    ? "Lat ${p.north.toStringAsFixed(decimals)} · Lon ${p.east.toStringAsFixed(decimals)}"
                    : "N ${p.north.toStringAsFixed(decimals)} · E ${p.east.toStringAsFixed(decimals)}"),
                trailing: Text("${p.elevation.toStringAsFixed(2)} m"),
                onTap: () => Provider.of<MapProvider>(context, listen: false)
                    .mapController
                    .move(p.position, 19),
              ),
          ],
        ),
      );
    });
  }
}
