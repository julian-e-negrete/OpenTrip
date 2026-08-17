import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Copies a picked image (image_picker's temp file, which the OS can
/// clean up at any time) into this app's own persistent documents
/// directory, so the path stored in SQLite (profiles.avatar_path,
/// vehicles.photo_path) stays valid indefinitely.
class LocalImageStore {
  LocalImageStore._();

  static Future<String> save(File sourceFile) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final ext = p.extension(sourceFile.path);
    final destPath = p.join(imagesDir.path, '${const Uuid().v4()}$ext');
    await sourceFile.copy(destPath);
    return destPath;
  }

  static Future<void> deleteIfExists(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
