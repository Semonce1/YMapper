import 'dart:typed_data';

import 'share_stub.dart' if (dart.library.js_interop) 'share_web.dart' as impl;

/// Resultado de intentar compartir un archivo con el menú del sistema.
enum ShareResult { shared, cancelled, unsupported, error }

/// Abre el menú de compartir del sistema con el archivo (en la web usa la
/// Web Share API; en iPhone permite enviarlo a un Atajo).
Future<ShareResult> shareFile(Uint8List bytes, String fileName,
        {String mimeType = 'application/octet-stream'}) =>
    impl.shareFile(bytes, fileName, mimeType);
