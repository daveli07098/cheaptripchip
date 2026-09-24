import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'photo_repository.dart';

/// Guest-mode [PhotoRepository] on mobile: one file per place at
/// `<app documents>/photos/<placeId>.jpg`. Never used on web (no dart:io
/// filesystem there — see [MemoryPhotoRepository]).
class FilePhotoRepository implements PhotoRepository {
  Directory? _dir;

  Future<File> _file(String placeId) async {
    final dir = _dir ??= Directory(
      '${(await getApplicationDocumentsDirectory()).path}/photos',
    );
    // Place ids are app-generated, but keep them from escaping the folder.
    final safeId = placeId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$safeId.jpg');
  }

  @override
  Future<Uint8List?> load(String placeId) async {
    final file = await _file(placeId);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> save(String placeId, Uint8List jpeg) async {
    final file = await _file(placeId);
    await file.parent.create(recursive: true);
    // Write-then-rename so a crash mid-write can't leave a truncated JPEG.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(jpeg, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete(String placeId) async {
    final file = await _file(placeId);
    if (await file.exists()) await file.delete();
  }

  @override
  bool get loadIsCostly => false;
}
