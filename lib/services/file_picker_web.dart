// Browser-only file picker. The frontend is delivered as Flutter Web inside
// Telegram's Mini App, so dart:html is available everywhere this code runs.
//
// Usage:
//   final pf = await pickImageFile();
//   if (pf != null) api.uploadProof(pf.bytes, filename: pf.name);
//
// The picker accepts a single image and returns its bytes plus filename.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';

class PickedFile {
  PickedFile(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

Future<PickedFile?> pickImageFile() async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = false;
  // Don't attach to DOM — modern browsers allow programmatic .click().
  input.click();

  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;
  final file = files.first;
  final reader = html.FileReader();
  final completer = Completer<Uint8List>();
  reader.onLoadEnd.listen((_) {
    final result = reader.result;
    if (result is Uint8List) {
      completer.complete(result);
    } else if (result is ByteBuffer) {
      completer.complete(result.asUint8List());
    } else if (result is List<int>) {
      completer.complete(Uint8List.fromList(result));
    } else {
      completer.completeError('unsupported reader result type: ${result.runtimeType}');
    }
  });
  reader.onError.listen((_) => completer.completeError('read failed'));
  reader.readAsArrayBuffer(file);
  final bytes = await completer.future;
  return PickedFile(bytes, file.name);
}
