import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../models/place.dart';
import '../models/shared_board.dart';
import 'shared_board_repository.dart';

/// [SharedBoardRepository] on Cloud Firestore. Each write touches only the
/// fields one branch of firestore.rules allows (editor → sections, join →
/// self in members/memberIds/memberNames + joinCode, …), using field-path
/// updates so concurrent joins/edits don't clobber each other.
class FirestoreSharedBoardRepository implements SharedBoardRepository {
  FirestoreSharedBoardRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Firestore caps a batch at 500 writes; stay well under it.
  static const _batchSize = 450;

  CollectionReference<Map<String, dynamic>> get _boards =>
      _firestore.collection('sharedBoards');

  CollectionReference<Map<String, dynamic>> _places(String boardId) =>
      _boards.doc(boardId).collection('places');

  @override
  Stream<List<SharedBoard>> watchBoards(String uid) {
    return _boards.where('memberIds', arrayContains: uid).snapshots().map((
      snapshot,
    ) {
      final boards = <SharedBoard>[];
      for (final doc in snapshot.docs) {
        try {
          boards.add(SharedBoard.fromJson(doc.id, doc.data()));
        } catch (error) {
          debugPrint(
            'FirestoreSharedBoardRepository: skipping ${doc.id}: $error',
          );
        }
      }
      boards.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return boards;
    });
  }

  @override
  Stream<List<Place>> watchPlaces(String boardId) {
    return _places(boardId).snapshots().map((snapshot) {
      final places = <Place>[];
      for (final doc in snapshot.docs) {
        try {
          places.add(Place.fromJson(doc.data()));
        } catch (error) {
          debugPrint(
            'FirestoreSharedBoardRepository: skipping place ${doc.id}: $error',
          );
        }
      }
      return places;
    });
  }

  @override
  String newBoardId() => _boards.doc().id;

  @override
  Future<void> create(SharedBoard board, List<Place> places) async {
    await _boards.doc(board.id).set({
      ...board.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _writePlaces(board.id, upsert: places);
  }

  @override
  Future<SharedBoard?> fetch(String boardId) async {
    try {
      final snapshot = await _boards.doc(boardId).get();
      final data = snapshot.data();
      return data == null ? null : SharedBoard.fromJson(snapshot.id, data);
    } on FirebaseException catch (error) {
      // Not a member yet (or no such board) — the rules deny the read.
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }

  @override
  Future<void> updateSections(
    String boardId,
    List<BoardSection> sections, {
    List<Place> upsertPlaces = const [],
    Set<String> deletePlaceIds = const {},
  }) async {
    // Copies land before the sections that reference them, and deletions
    // after the sections stop referencing them.
    await _writePlaces(boardId, upsert: upsertPlaces);
    await _boards.doc(boardId).update({
      'sections': sections.map((section) => section.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _writePlaces(boardId, delete: deletePlaceIds);
  }

  @override
  Future<void> rename(String boardId, String name) {
    return _boards.doc(boardId).update({
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateLink(
    String boardId, {
    required BoardRole? linkRole,
    required String inviteCode,
  }) {
    return _boards.doc(boardId).update({
      'linkRole': linkRole?.name,
      'inviteCode': inviteCode,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setIncludeOwnerNotes(
    String boardId,
    bool include,
    List<Place> refreshedPlaces,
  ) async {
    await _boards.doc(boardId).update({
      'includeOwnerNotes': include,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _writePlaces(boardId, upsert: refreshedPlaces);
  }

  @override
  Future<void> setMemberRole(String boardId, String uid, BoardRole role) {
    return _boards.doc(boardId).update({
      FieldPath(['members', uid]): role.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> removeMember(String boardId, String uid) {
    return _boards.doc(boardId).update({
      FieldPath(['members', uid]): FieldValue.delete(),
      FieldPath(['memberNames', uid]): FieldValue.delete(),
      'memberIds': FieldValue.arrayRemove([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> removeMemberResetLink(
    String boardId,
    String uid, {
    required String inviteCode,
  }) {
    return _boards.doc(boardId).update({
      FieldPath(['members', uid]): FieldValue.delete(),
      FieldPath(['memberNames', uid]): FieldValue.delete(),
      'memberIds': FieldValue.arrayRemove([uid]),
      'inviteCode': inviteCode,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<JoinOutcome> join(
    String boardId, {
    required String code,
    required String uid,
    required String name,
    required BoardRole role,
  }) async {
    try {
      await _boards.doc(boardId).update({
        FieldPath(['members', uid]): role.name,
        'memberIds': FieldValue.arrayUnion([uid]),
        FieldPath(['memberNames', uid]): name,
        'joinCode': code,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return JoinOutcome.joined;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        return JoinOutcome.denied;
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String boardId) async {
    final existing = await _places(boardId).get();
    await _writePlaces(boardId, delete: {for (final d in existing.docs) d.id});
    await _boards.doc(boardId).delete();
  }

  Future<void> _writePlaces(
    String boardId, {
    List<Place> upsert = const [],
    Set<String> delete = const {},
  }) async {
    final ops = <void Function(WriteBatch)>[
      for (final place in upsert)
        (batch) => batch.set(_places(boardId).doc(place.id), {
          ...place.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      for (final id in delete)
        (batch) => batch.delete(_places(boardId).doc(id)),
    ];
    for (var start = 0; start < ops.length; start += _batchSize) {
      final batch = _firestore.batch();
      for (final op in ops.skip(start).take(_batchSize)) {
        op(batch);
      }
      await batch.commit();
    }
  }
}
