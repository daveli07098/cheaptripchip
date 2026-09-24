import 'dart:typed_data';

import 'photo_repository.dart';

/// In-memory [PhotoRepository]: the default before [PhotoStore.bind] runs,
/// web guest mode (there is no app documents directory on web, and guest
/// data never goes to Firestore — so web guest photos last until reload),
/// and tests.
class MemoryPhotoRepository implements PhotoRepository {
  final Map<String, Uint8List> _photos = {};

  @override
  Future<Uint8List?> load(String placeId) async => _photos[placeId];

  @override
  Future<void> save(String placeId, Uint8List jpeg) async {
    _photos[placeId] = jpeg;
  }

  @override
  Future<void> delete(String placeId) async {
    _photos.remove(placeId);
  }

  @override
  bool get loadIsCostly => false;
}
