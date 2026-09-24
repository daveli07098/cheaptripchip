import 'dart:typed_data';

/// Backs [PhotoStore] (lib/data/photo_store.dart): one personal JPEG per
/// place, keyed by place id. Request/response rather than a stream — photos
/// are loaded on demand when a card or detail sheet shows them, never
/// mirrored wholesale like places/boards.
///
/// Implementations:
/// - [MemoryPhotoRepository] (lib/data/memory_photo_repository.dart) — web
///   guest mode and tests; lost on reload.
/// - `FilePhotoRepository` (lib/data/file_photo_repository.dart) — mobile
///   guest mode, `<app documents>/photos/<placeId>.jpg`.
/// - `FirestorePhotoRepository` (lib/data/firestore_photo_repository.dart) —
///   signed in, `users/{uid}/photos/{placeId}`.
abstract class PhotoRepository {
  /// The stored JPEG for [placeId], or null when there is none.
  Future<Uint8List?> load(String placeId);

  Future<void> save(String placeId, Uint8List jpeg);

  /// Deleting a photo that doesn't exist is a no-op, not an error.
  Future<void> delete(String placeId);

  /// Whether [load] costs something worth avoiding (a billed network read).
  /// When true, [PhotoStore] only loads places whose `Place.myPhotoAt` marks
  /// a photo; when false (local file/memory) it always probes, because guest
  /// places are in-memory and lose that marker on restart while the file
  /// survives.
  bool get loadIsCostly;
}
