import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'photo_repository.dart';

/// Signed-in [PhotoRepository]: `users/{uid}/photos/{placeId}` =
/// `{jpeg: Blob, updatedAt: serverTimestamp}`.
///
/// The Spark (free) plan has no Cloud Storage, so the JPEG is stored as a
/// Firestore bytes field — capped by the 1 MiB document limit (PhotoStore
/// callers keep uploads well under that; firestore.rules enforces it). It
/// lives in its own collection, not on the place doc, so the places list
/// listener never downloads image bytes.
class FirestorePhotoRepository implements PhotoRepository {
  FirestorePhotoRepository(this.uid);

  final String uid;

  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('photos');

  @override
  Future<Uint8List?> load(String placeId) async {
    final snapshot = await _collection.doc(placeId).get();
    final jpeg = snapshot.data()?['jpeg'];
    return jpeg is Blob ? jpeg.bytes : null;
  }

  @override
  Future<void> save(String placeId, Uint8List jpeg) {
    return _collection.doc(placeId).set({
      'jpeg': Blob(jpeg),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> delete(String placeId) => _collection.doc(placeId).delete();

  @override
  bool get loadIsCostly => true;
}
