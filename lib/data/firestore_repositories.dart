import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../models/place.dart';
import 'repositories.dart';

/// `savedAt` strategy (documented per the multi-user contract): on every
/// [upsert] we `get()` the doc first to see whether it already exists, then
/// `set(..., SetOptions(merge: true))` with `updatedAt: FieldValue.serverTimestamp()`
/// always, and `savedAt: FieldValue.serverTimestamp()` ONLY when the doc did
/// not exist yet (i.e. first write) — so `savedAt` is a stable "when this was
/// first saved" marker used for feed ordering, while `updatedAt` tracks the
/// most recent edit without disturbing that order. Both fields live outside
/// [Place.toJson]/[Board.toJson] (they're repository bookkeeping, not part of
/// the model) and are simply ignored by the lenient `fromJson` on read.
class FirestorePlaceRepository implements PlaceRepository {
  FirestorePlaceRepository(this.uid);

  final String uid;

  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('places');

  @override
  Stream<List<Place>> watch() {
    return _collection.snapshots().map((snapshot) {
      final entries = <MapEntry<Place, Timestamp?>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        try {
          final place = Place.fromJson(data);
          // fromJson is lenient and yields LatLng(0,0) when location is
          // missing/malformed — skip those rather than showing a pin at
          // null island.
          if (place.location.latitude == 0 && place.location.longitude == 0) {
            continue;
          }
          entries.add(MapEntry(place, data['savedAt'] as Timestamp?));
        } catch (error, stackTrace) {
          debugPrint(
            'FirestorePlaceRepository: skipping ${doc.id}: $error\n$stackTrace',
          );
        }
      }
      // Order by savedAt desc when present (client-side, to avoid needing a
      // Firestore index); docs without savedAt (not yet round-tripped through
      // this repository) sort after, by name, for a stable fallback order.
      entries.sort((a, b) {
        final aSavedAt = a.value;
        final bSavedAt = b.value;
        if (aSavedAt != null && bSavedAt != null) {
          return bSavedAt.compareTo(aSavedAt);
        }
        if (aSavedAt != null) return -1;
        if (bSavedAt != null) return 1;
        return a.key.name.compareTo(b.key.name);
      });
      return entries.map((entry) => entry.key).toList();
    });
  }

  @override
  Future<void> upsert(Place place) async {
    final docRef = _collection.doc(place.id);
    final snapshot = await docRef.get();
    final data = place.toJson();
    data['updatedAt'] = FieldValue.serverTimestamp();
    if (!snapshot.exists) {
      data['savedAt'] = FieldValue.serverTimestamp();
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();
}

/// See the `savedAt` strategy note on [FirestorePlaceRepository]. Boards
/// aren't ordered by save time (no ordering requirement in the contract), so
/// this repository skips the `savedAt`/`updatedAt` bookkeeping and just
/// merges [Board.toJson] straight through.
class FirestoreBoardRepository implements BoardRepository {
  FirestoreBoardRepository(this.uid);

  final String uid;

  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('boards');

  @override
  Stream<List<Board>> watch() {
    return _collection.snapshots().map((snapshot) {
      final boards = <Board>[];
      for (final doc in snapshot.docs) {
        try {
          boards.add(Board.fromJson(doc.data()));
        } catch (error, stackTrace) {
          debugPrint(
            'FirestoreBoardRepository: skipping ${doc.id}: $error\n$stackTrace',
          );
        }
      }
      return boards;
    });
  }

  @override
  Future<void> upsert(Board board) {
    return _collection
        .doc(board.id)
        .set(board.toJson(), SetOptions(merge: true));
  }

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();
}
