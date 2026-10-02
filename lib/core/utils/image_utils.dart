import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Picks a photo and compresses it to a JPEG under ~300 KB, stepping the
/// quality down until it fits. Returns null if the user cancels.
Future<List<int>?> pickCompressedPhoto({required bool camera, int maxBytes = 300 * 1024}) async {
  final file = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 90,
  );
  if (file == null) return null;
  final original = await file.readAsBytes();
  var quality = 80;
  var width = 1280;
  List<int> out = original;
  while (true) {
    try {
      out = await FlutterImageCompress.compressWithList(
        original,
        minWidth: width,
        minHeight: width,
        quality: quality,
        format: CompressFormat.jpeg,
      );
    } catch (_) {
      // Compression isn't available on every platform (e.g. some web
      // browsers); fall back to the picker's already-downscaled bytes.
      return original.length <= maxBytes * 2 ? original : null;
    }
    if (out.length <= maxBytes || quality <= 30) return out;
    quality -= 15;
    width = (width * 0.85).round();
  }
}
