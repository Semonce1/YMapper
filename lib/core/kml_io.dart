import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:universal_io/io.dart';
import 'package:ymapper/core/drone_mapper_format.dart';

/// Abre un KML y devuelve los vértices del polígono elegido, o `null`.
class KmlIo {
  static Future<List<LatLng>?> pickPolygon(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["kml"],
        withData: true,
        dialogTitle: "Cargar área");
    if (file == null || file.files.isEmpty) return null;

    late DroneMapperXml kml;
    if (file.files.first.bytes != null) {
      kml = await DroneMapperXml.fromKmlString(
          String.fromCharCodes(file.files.first.bytes!));
    } else if (!kIsWeb && file.files.single.path != null) {
      kml = await DroneMapperXml.fromKmlString(
          await File(file.files.single.path!).readAsString());
    } else {
      messenger.showSnackBar(
          const SnackBar(content: Text("No se pudo leer el archivo")));
      return null;
    }

    List<LatLng> toPoints(int i) => kml.polygons[i].outerBoundaryIs.rtepts
        .map((e) => LatLng(e.lat!, e.lon!))
        .toList();

    if (kml.polygons.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text("El KML no tiene polígonos")));
      return null;
    }
    if (kml.polygons.length == 1) return toPoints(0);
    if (!context.mounted) return null;

    return showDialog<List<LatLng>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Elige el polígono"),
        content: SizedBox(
          width: 400,
          height: 320,
          child: ListView.separated(
            itemCount: kml.polygons.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => ListTile(
              title: Text(kml.polygons[i].name ?? "Polígono ${i + 1}"),
              onTap: () => Navigator.pop(context, toPoints(i)),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar")),
        ],
      ),
    );
  }
}
