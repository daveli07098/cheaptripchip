import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a guest-mode local repository keeps its JSON snapshot between app
/// launches (see [LocalPlaceRepository]/[LocalBoardRepository]). One
/// snapshot per collection: the whole list, rewritten on every change.
abstract class GuestSnapshotStore {
  /// The last written snapshot, or null when nothing was ever saved.
  Future<String?> read();

  Future<void> write(String json);

  /// Picks the platform's store for the collection [name] (e.g. `places`):
  /// a file under the app documents directory on mobile/desktop,
  /// shared_preferences (browser localStorage) on web.
  factory GuestSnapshotStore.forCollection(String name) => kIsWeb
      ? PrefsSnapshotStore('guest_${name}_v1')
      : FileSnapshotStore('$name.json');
}

/// `<app documents>/guest/<fileName>`, written tmp-then-rename so a crash
/// mid-write leaves the previous snapshot intact.
class FileSnapshotStore implements GuestSnapshotStore {
  FileSnapshotStore(this.fileName, {Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationDocumentsDirectory;

  final String fileName;
  final Future<Directory> Function() _baseDir;
  File? _file;

  Future<File> _resolve() async =>
      _file ??= File('${(await _baseDir()).path}/guest/$fileName');

  @override
  Future<String?> read() async {
    final file = await _resolve();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String json) async {
    final file = await _resolve();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(file.path);
  }
}

/// Web fallback: one shared_preferences string per collection. Browsers cap
/// localStorage at roughly 5 MB per origin, so very large guest libraries
/// may fail to save there (the error is logged; the in-memory copy stays).
class PrefsSnapshotStore implements GuestSnapshotStore {
  PrefsSnapshotStore(this.key);

  final String key;

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String json) async {
    await (await SharedPreferences.getInstance()).setString(key, json);
  }
}

/// In-memory store for tests: survives across repository instances the
/// way a file survives an app restart.
class MemorySnapshotStore implements GuestSnapshotStore {
  MemorySnapshotStore([this.value]);

  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async {
    writes++;
    value = json;
  }
}
