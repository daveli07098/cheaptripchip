import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import 'file_photo_repository.dart';
import 'firestore_photo_repository.dart';
import 'memory_photo_repository.dart';
import 'photo_repository.dart';
import 'place_store.dart';

/// Largest JPEG [PhotoStore.setPhoto] accepts. Firestore caps a document at
/// 1 MiB (the bytes field plus overhead); 700 KB leaves headroom and is far
/// above what a 1280px / quality-75 pick normally produces (~150–400 KB).
const int kMaxPhotoBytes = 700 * 1024;

/// Thrown by [PhotoStore.setPhoto] when the JPEG exceeds [kMaxPhotoBytes].
class PhotoTooLargeException implements Exception {
  const PhotoTooLargeException(this.bytes);

  final int bytes;

  @override
  String toString() =>
      'Photo is ${(bytes / 1024).round()} KB — the limit is '
      '${kMaxPhotoBytes ~/ 1024} KB.';
}

/// Runtime cache of the user's own photo per place (one JPEG each), bound to
/// a [PhotoRepository] the same way [PlaceStore]/BoardStore bind theirs:
/// guest → local file (mobile) or memory (web), signed in → Firestore.
///
/// Photos load lazily: [photoFor] hands back a per-place listenable and
/// fetches on first use. For a costly repository (Firestore) it only fetches
/// places whose `Place.myPhotoAt` marks a photo, and re-fetches when that
/// marker changes (e.g. set from another device).
class PhotoStore {
  PhotoStore._();
  static final PhotoStore instance = PhotoStore._();

  /// Defaults to memory until [bind] runs, so widget tests that never call
  /// [bind] don't hit the path_provider/Firestore platform channels.
  PhotoRepository _repository = MemoryPhotoRepository();

  final Map<String, ValueNotifier<Uint8List?>> _photos = {};
  final Map<String, ValueNotifier<bool>> _loading = {};

  /// Per place: the `myPhotoAt` marker the cached value reflects. Presence of
  /// a key means "loaded (or deliberately skipped) for this marker".
  final Map<String, DateTime?> _loadedFor = {};

  /// Bumped on every rebind so loads that started against the previous
  /// repository can't write into the new user's cache.
  int _generation = 0;

  /// Per place: bumped by every [setPhoto]/[removePhoto], so a load that was
  /// already in flight can't overwrite the newer photo when it lands.
  final Map<String, int> _writes = {};

  Future<void> bind(AppUser? user) async {
    final PhotoRepository repository;
    if (user != null) {
      repository = FirestorePhotoRepository(user.uid);
    } else if (kIsWeb) {
      repository = MemoryPhotoRepository();
    } else {
      repository = FilePhotoRepository();
    }
    bindRepository(repository);
  }

  /// Test seam (and what [bind] delegates to): swaps the repository and
  /// empties the cache. Existing notifiers are reset to null rather than
  /// replaced — widgets may still hold them.
  @visibleForTesting
  void bindRepository(PhotoRepository repository) {
    _generation++;
    _repository = repository;
    _loadedFor.clear();
    for (final notifier in _photos.values) {
      notifier.value = null;
    }
    for (final notifier in _loading.values) {
      notifier.value = false;
    }
  }

  /// The user's photo for [placeId] (null when none, or not loaded yet).
  /// Safe to call from `build`: triggers at most one load per marker.
  ValueListenable<Uint8List?> photoFor(String placeId) {
    final notifier = _photos.putIfAbsent(
      placeId,
      () => ValueNotifier<Uint8List?>(null),
    );
    _ensureLoaded(placeId);
    return notifier;
  }

  /// True while [photoFor]'s fetch for [placeId] is in flight — lets the UI
  /// show a placeholder instead of the "no photo" fallback.
  ValueListenable<bool> loadingFor(String placeId) =>
      _loading.putIfAbsent(placeId, () => ValueNotifier<bool>(false));

  /// Stores [jpeg] as the photo for [placeId] and marks the place
  /// (`Place.myPhotoAt`). Optimistic: listeners see the new photo at once and
  /// are reverted if the write fails; the error is rethrown for the caller
  /// to surface. Throws [PhotoTooLargeException] above [kMaxPhotoBytes].
  Future<void> setPhoto(String placeId, Uint8List jpeg) async {
    if (jpeg.lengthInBytes > kMaxPhotoBytes) {
      throw PhotoTooLargeException(jpeg.lengthInBytes);
    }
    final at = DateTime.now().toUtc();
    await _write(
      placeId,
      value: jpeg,
      marker: at,
      write: () => _repository.save(placeId, jpeg),
    );
  }

  /// Deletes the photo for [placeId] and clears `Place.myPhotoAt`.
  /// Optimistic with revert, like [setPhoto].
  Future<void> removePhoto(String placeId) {
    return _write(
      placeId,
      value: null,
      marker: null,
      write: () => _repository.delete(placeId),
    );
  }

  Future<void> _write(
    String placeId, {
    required Uint8List? value,
    required DateTime? marker,
    required Future<void> Function() write,
  }) async {
    final notifier = _photos.putIfAbsent(
      placeId,
      () => ValueNotifier<Uint8List?>(null),
    );
    _writes[placeId] = (_writes[placeId] ?? 0) + 1;
    final previousValue = notifier.value;
    final hadLoaded = _loadedFor.containsKey(placeId);
    final previousMarker = _loadedFor[placeId];
    notifier.value = value;
    _loadedFor[placeId] = marker;
    try {
      await write();
    } catch (_) {
      notifier.value = previousValue;
      if (hadLoaded) {
        _loadedFor[placeId] = previousMarker;
      } else {
        _loadedFor.remove(placeId);
      }
      rethrow;
    }
    await PlaceStore.instance.setPhotoMarker(placeId, marker);
  }

  void _ensureLoaded(String placeId) {
    final costly = _repository.loadIsCostly;
    final marker = costly
        ? PlaceStore.instance.byIdOrNull(placeId)?.myPhotoAt
        : null;
    if (_loadedFor.containsKey(placeId) &&
        (!costly || _sameMoment(_loadedFor[placeId], marker))) {
      return;
    }
    _loadedFor[placeId] = marker;
    // photoFor() is called from build, and notifying listeners mid-build
    // throws — hop to a microtask before touching any notifier.
    final generation = _generation;
    scheduleMicrotask(() {
      if (generation != _generation) return;
      if (costly && marker == null) {
        // No photo marked — skip the billed read. A photo set earlier in
        // this session never gets here (its marker matches the cache).
        _photos[placeId]?.value = null;
        return;
      }
      _load(placeId, generation);
    });
  }

  Future<void> _load(String placeId, int generation) async {
    final loading = _loading.putIfAbsent(
      placeId,
      () => ValueNotifier<bool>(false),
    );
    final writes = _writes[placeId];
    loading.value = true;
    try {
      final bytes = await _repository.load(placeId);
      if (generation != _generation || writes != _writes[placeId]) return;
      _photos[placeId]?.value = bytes;
    } catch (error, stackTrace) {
      debugPrint('PhotoStore: load $placeId failed: $error\n$stackTrace');
      // Allow a retry on the next photoFor() instead of caching the failure.
      if (generation == _generation) _loadedFor.remove(placeId);
    } finally {
      if (generation == _generation) loading.value = false;
    }
  }

  static bool _sameMoment(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.isAtSameMomentAs(b);
  }
}
