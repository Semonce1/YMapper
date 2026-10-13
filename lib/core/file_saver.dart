import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;
import 'package:universal_io/io.dart';

/// Guarda un archivo generado por la app.
///
/// En la web lo descarga directamente (en iPhone queda en la app Archivos).
/// En escritorio y móvil abre el diálogo de guardar.
/// Devuelve `false` si el usuario cancela.
class FileSaver {
  static Future<bool> save({
    required Uint8List bytes,
    required String fileName,
    required String extension,
    String mimeType = 'application/octet-stream',
    String dialogTitle = "Guardar archivo",
  }) async {
    final fullName =
        fileName.endsWith(".$extension") ? fileName : "$fileName.$extension";

    if (kIsWeb) {
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", fullName)
        ..click();
      html.Url.revokeObjectUrl(url);
      return true;
    }

    String? outputPath = await FilePicker.saveFile(
        type: FileType.custom,
        fileName: fullName,
        allowedExtensions: [extension],
        dialogTitle: dialogTitle,
        bytes: bytes);

    if (outputPath == null) return false;

    // En escritorio el selector no escribe el archivo por sí solo
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (!outputPath.endsWith(".$extension")) {
        outputPath += ".$extension";
      }
      await File(outputPath).writeAsBytes(bytes);
    }
    return true;
  }
}
