import 'dart:typed_data';

import 'share_file.dart';

Future<ShareResult> shareFile(
        Uint8List bytes, String fileName, String mimeType) async =>
    ShareResult.unsupported;
