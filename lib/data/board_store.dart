import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../services/auth_service.dart';
import 'firestore_repositories.dart';
import 'local_repositories.dart';
import 'mock_data.dart';
import 'place_store.dart';
import 'repositories.dart';

/// Runtime store for boards, seeded from [MockData] until [bind] is called
/// with a real [AppUser] (or `null` for guest mode). Mirrors the same
/// Local/Firestore split as [PlaceStore] — see lib/data/repositories.dart.
class BoardStore {
  BoardStore._();
  static final BoardStore instance = BoardStore._();

  final ValueNotifier<List<Board>> boards = ValueNotifier<List<Board>>(
    List<Board>.from(MockData.boards),
  );

  BoardRepository _repository = LocalBoardRepository();
  StreamSubscription<List<Board>>? _subscription;

  static final Random _idRandom = Random();

  /// Picks [LocalBoardRepository] when [user] is null (guest mode) or
  /// [FirestoreBoardRepository] under `users/{uid}/boards` when signed in,
  /// cancelling any previous subscription first.
  Future<void> bind(AppUser? user) async {
    final repository = user == null
        ? LocalBoardRepository()
        : FirestoreBoardRepository(user.uid);
    bindRepository(repository);
  }

  /// Test seam: bind directly to a given [repository], bypassing [AppUser]
  /// resolution. Cancels any previous subscription and immediately starts
  /// mirroring [repository]'s stream into [boards].
  @visibleForTesting
  void bindRepository(BoardRepository repository) {
    _subscription?.cancel();
    _repository = repository;
    _subscription = repository.watch().listen((value) {
      boards.value = value;
    });
  }

  Board? byIdOrNull(String id) {
    for (final board in boards.value) {
      if (board.id == id) return board;
    }
    return null;
  }

  /// Creates a new board (empty unless [sections] is given) and adds it to
  /// [boards] (optimistic), writing through the repository. Passing
  /// [sections] writes a pre-filled board in one upsert — prefer it over a
  /// loop of [addPlaceToBoard] calls, which read back [boards] and can race
  /// the repository's asynchronous echo.
  Future<Board> createBoard(
    String name, {
    String emoji = '📌',
    List<BoardSection> sections = const [],
  }) async {
    final id =
        'board-${DateTime.now().millisecondsSinceEpoch}-'
        '${_idRandom.nextInt(10000).toString().padLeft(4, '0')}';
    final board = Board(id: id, name: name, emoji: emoji, sections: sections);
    boards.value = [board, ...boards.value];
    await _repository.upsert(board);
    return board;
  }

  /// Adds [placeId] to the section titled [sectionTitle] on board [boardId]
  /// (created if missing; when [sectionTitle] is null, defaults to the
  /// place's `category.labelEn` via [PlaceStore.byIdOrNull], falling back to
  /// 'Saved' if the place isn't known). No-op if [placeId] is already in that
  /// section. Optimistic, like [createBoard].
  Future<void> addPlaceToBoard({
    required String boardId,
    required String placeId,
    String? sectionTitle,
  }) async {
    final board = byIdOrNull(boardId);
    if (board == null) return;
    final resolvedTitle =
        sectionTitle ??
        PlaceStore.instance.byIdOrNull(placeId)?.category.labelEn ??
        'Saved';

    final sectionIndex = board.sections.indexWhere(
      (section) => section.title == resolvedTitle,
    );

    List<BoardSection> updatedSections;
    if (sectionIndex == -1) {
      updatedSections = [
        ...board.sections,
        BoardSection(title: resolvedTitle, placeIds: [placeId]),
      ];
    } else {
      final section = board.sections[sectionIndex];
      if (section.placeIds.contains(placeId)) {
        return; // Already saved to this section — no-op.
      }
      updatedSections = [
        for (var i = 0; i < board.sections.length; i++)
          if (i == sectionIndex)
            section.copyWith(placeIds: [...section.placeIds, placeId])
          else
            board.sections[i],
      ];
    }

    final updated = board.copyWith(sections: updatedSections);
    boards.value = [
      for (final b in boards.value)
        if (b.id == boardId) updated else b,
    ];
    await _repository.upsert(updated);
  }
}
