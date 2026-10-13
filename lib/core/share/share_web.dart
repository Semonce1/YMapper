import 'dart:js_interop';
import 'dart:typed_data';

import 'share_file.dart';

@JS('olShareFile')
external JSPromise<JSString> _olShareFile(
    JSUint8Array bytes, JSString name, JSString mime);

Future<ShareResult> shareFile(
    Uint8List bytes, String fileName, String mimeType) async {
  try {
    final result =
        (await _olShareFile(bytes.toJS, fileName.toJS, mimeType.toJS).toDart)
            .toDart;
    switch (result) {
      case "shared":
        return ShareResult.shared;
      case "cancelled":
        return ShareResult.cancelled;
      case "unsupported":
        return ShareResult.unsupported;
      default:
        return ShareResult.error;
    }
  } catch (_) {
    return ShareResult.error;
  }
}
