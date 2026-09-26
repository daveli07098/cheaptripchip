import 'dart:async';

import 'package:cheaptripchip/data/shared_board_repository.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/shared_board.dart';

/// In-memory [SharedBoardRepository] that mimics the firestore.rules
/// decisions the store depends on (join checks, membership reads).
class FakeSharedBoardRepository implements SharedBoardRepository {
  final Map<String, SharedBoard> boards = {};
  final Map<String, Map<String, Place>> places = {};
  final _changes = StreamController<void>.broadcast();
  int _nextId = 0;

  /// Every join attempt as (boardId, role), for assertions.
  final List<(String, BoardRole)> joinAttempts = [];

  /// Every method invoked, for assertions on which write path a store
  /// method took (e.g. that `removeMember` uses the combined write, not a
  /// separate `updateLink`).
  final List<String> calls = [];

  void _changed() => _changes.add(null);

  /// Seeds a board as if another user created it.
  void seed(SharedBoard board, [List<Place> copies = const []]) {
    boards[board.id] = board;
    places[board.id] = {for (final p in copies) p.id: p};
    _changed();
  }

  @override
  Stream<List<SharedBoard>> watchBoards(String uid) {
    List<SharedBoard> current() => [
      for (final b in boards.values)
        if (b.members.containsKey(uid)) b,
    ];
    return Stream.multi((controller) {
      controller.add(current());
      final sub = _changes.stream.listen((_) => controller.add(current()));
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<List<Place>> watchPlaces(String boardId) {
    return Stream.multi((controller) {
      controller.add([...?places[boardId]?.values]);
      final sub = _changes.stream.listen(
        (_) => controller.add([...?places[boardId]?.values]),
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  String newBoardId() => 'shared${_nextId++}';

  @override
  Future<void> create(SharedBoard board, List<Place> copies) async {
    seed(board, copies);
  }

  @override
  Future<SharedBoard?> fetch(String boardId) async => boards[boardId];

  @override
  Future<void> updateSections(
    String boardId,
    List<BoardSection> sections, {
    List<Place> upsertPlaces = const [],
    Set<String> deletePlaceIds = const {},
  }) async {
    final map = places.putIfAbsent(boardId, () => {});
    for (final p in upsertPlaces) {
      map[p.id] = p;
    }
    deletePlaceIds.forEach(map.remove);
    boards[boardId] = boards[boardId]!.copyWith(sections: sections);
    _changed();
  }

  @override
  Future<void> rename(String boardId, String name) async {
    boards[boardId] = boards[boardId]!.copyWith(name: name);
    _changed();
  }

  @override
  Future<void> updateLink(
    String boardId, {
    required BoardRole? linkRole,
    required String inviteCode,
  }) async {
    calls.add('updateLink');
    boards[boardId] = boards[boardId]!.copyWith(
      linkRole: linkRole,
      clearLinkRole: linkRole == null,
      inviteCode: inviteCode,
    );
    _changed();
  }

  @override
  Future<void> setIncludeOwnerNotes(
    String boardId,
    bool include,
    List<Place> refreshedPlaces,
  ) async {
    boards[boardId] = boards[boardId]!.copyWith(includeOwnerNotes: include);
    for (final p in refreshedPlaces) {
      places[boardId]![p.id] = p;
    }
    _changed();
  }

  @override
  Future<void> setMemberRole(String boardId, String uid, BoardRole role) async {
    boards[boardId] = boards[boardId]!.withMember(uid, role);
    _changed();
  }

  @override
  Future<void> removeMember(String boardId, String uid) async {
    calls.add('removeMember');
    boards[boardId] = boards[boardId]!.withoutMember(uid);
    _changed();
  }

  @override
  Future<void> removeMemberResetLink(
    String boardId,
    String uid, {
    required String inviteCode,
  }) async {
    calls.add('removeMemberResetLink');
    boards[boardId] = boards[boardId]!
        .withoutMember(uid)
        .copyWith(inviteCode: inviteCode);
    _changed();
  }

  @override
  Future<JoinOutcome> join(
    String boardId, {
    required String code,
    required String uid,
    required String name,
    required BoardRole role,
  }) async {
    joinAttempts.add((boardId, role));
    final board = boards[boardId];
    if (board == null ||
        board.linkRole == null ||
        board.inviteCode != code ||
        board.linkRole != role ||
        board.members.containsKey(uid)) {
      return JoinOutcome.denied;
    }
    boards[boardId] = board.withMember(uid, role, name: name);
    _changed();
    return JoinOutcome.joined;
  }

  @override
  Future<void> delete(String boardId) async {
    boards.remove(boardId);
    places.remove(boardId);
    _changed();
  }
}
