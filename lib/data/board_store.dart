import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../services/auth_service.dart';
import 'firestore_repositories.dart';
import 'guest_storage.dart';
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

  /// Persisted guest repository, reused across binds (see PlaceStore).
  LocalBoardRepository? _guestRepository;

  static final Random _idRandom = Random();

  /// Index each board held at the moment it was removed by [deleteBoard],
  /// keyed by board id — consulted by [restoreBoard] to re-insert at (as
  /// close as optimistically possible to) its old position.
  final Map<String, int> _lastKnownIndex = {};

  /// Picks [LocalBoardRepository] when [user] is null (guest mode) or
  /// [FirestoreBoardRepository] under `users/{uid}/boards` when signed in,
  /// cancelling any previous subscription first.
  Future<void> bind(AppUser? user) async {
    final repository = user == null
        ? _guestRepository ??= LocalBoardRepository(
            storage: GuestSnapshotStore.forCollection('boards'),
          )
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

  /// Renames board [id] to [name] (trimmed). No-op if the board doesn't
  /// exist or [name] is blank after trimming. Optimistic, like [createBoard].
  Future<void> renameBoard(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final board = byIdOrNull(id);
    if (board == null) return;
    final updated = board.copyWith(name: trimmed);
    boards.value = [
      for (final b in boards.value)
        if (b.id == id) updated else b,
    ];
    await _repository.upsert(updated);
  }

  /// Removes board [id] and returns the removed [Board] (for undo via
  /// [restoreBoard]), or null if it didn't exist. Optimistic: [boards]
  /// updates synchronously before the repository delete completes.
  Future<Board?> deleteBoard(String id) async {
    final index = boards.value.indexWhere((b) => b.id == id);
    if (index == -1) return null;
    final removed = boards.value[index];
    _lastKnownIndex[id] = index;
    boards.value = [
      for (final b in boards.value)
        if (b.id != id) b,
    ];
    await _repository.delete(id);
    return removed;
  }

  /// Re-inserts [board], previously removed by [deleteBoard], at the index
  /// it held at deletion time (clamped to the current list length; 0 if
  /// [board] wasn't deleted via this store instance). This position is only
  /// honoured optimistically — once the repository's [watch] stream echoes
  /// back (Local: unknown ids land at index 0 on the next upsert; Firestore:
  /// snapshot order, not insertion order), [boards] reflects whatever order
  /// the backing store produces, not this one.
  Future<void> restoreBoard(Board board) async {
    final index = (_lastKnownIndex.remove(board.id) ?? 0).clamp(
      0,
      boards.value.length,
    );
    boards.value = [
      ...boards.value.sublist(0, index),
      board,
      ...boards.value.sublist(index),
    ];
    await _repository.upsert(board);
  }

  /// Removes [placeId] from every section of board [boardId] that contains
  /// it (a place can appear in more than one section of the same board).
  /// A section that becomes empty is dropped entirely — an empty section
  /// would otherwise render as a bare, item-less header in the UI. Returns
  /// the titles of the sections [placeId] was removed from (in board order,
  /// before pruning), which is enough to undo via a loop of
  /// [addPlaceToBoard] calls with `sectionTitle:` set to each returned
  /// title — note the section is recreated at the end of the board, so
  /// original position isn't restored, only membership.
  Future<List<String>> removePlaceFromBoard({
    required String boardId,
    required String placeId,
  }) async {
    final board = byIdOrNull(boardId);
    if (board == null) return const [];

    final removedFrom = <String>[];
    final updatedSections = <BoardSection>[];
    for (final section in board.sections) {
      if (!section.placeIds.contains(placeId)) {
        updatedSections.add(section);
        continue;
      }
      removedFrom.add(section.title);
      final remaining = section.placeIds.where((id) => id != placeId).toList();
      if (remaining.isNotEmpty) {
        updatedSections.add(section.copyWith(placeIds: remaining));
      }
    }
    if (removedFrom.isEmpty) return const [];

    final updated = board.copyWith(sections: updatedSections);
    boards.value = [
      for (final b in boards.value)
        if (b.id == boardId) updated else b,
    ];
    await _repository.upsert(updated);
    return removedFrom;
  }

  /// Applies [add]/[remove] place ids to board [boardId] in a single
  /// repository write — used by AddPlacesSheet, where a loop of
  /// [addPlaceToBoard]/[removePlaceFromBoard] calls (each of which reads
  /// back [boards] and upserts) would issue one write per toggled place
  /// instead of one for the whole batch. [remove] ids are dropped from every
  /// section (pruning any section left empty, same rule as
  /// [removePlaceFromBoard]); [add] ids are then folded in, each landing in
  /// the section titled by the place's `category.labelEn` (falling back to
  /// 'Saved' if unknown) — same resolution as [addPlaceToBoard]. A place id
  /// in both sets is treated as a removal (it ends up out of the board).
  /// No-op if the board doesn't exist or both sets are empty.
  Future<void> updateBoardPlaces({
    required String boardId,
    required Set<String> add,
    required Set<String> remove,
  }) async {
    final board = byIdOrNull(boardId);
    if (board == null) return;
    if (add.isEmpty && remove.isEmpty) return;

    var sections = [
      for (final section in board.sections)
        section.copyWith(
          placeIds: section.placeIds
              .where((id) => !remove.contains(id))
              .toList(),
        ),
    ].where((section) => section.placeIds.isNotEmpty).toList();

    final alreadyIn = <String>{
      for (final section in sections) ...section.placeIds,
    };
    for (final placeId in add) {
      if (remove.contains(placeId) || alreadyIn.contains(placeId)) continue;
      final title =
          PlaceStore.instance.byIdOrNull(placeId)?.category.labelEn ?? 'Saved';
      final index = sections.indexWhere((section) => section.title == title);
      if (index == -1) {
        sections = [
          ...sections,
          BoardSection(title: title, placeIds: [placeId]),
        ];
      } else {
        sections = [
          for (var i = 0; i < sections.length; i++)
            if (i == index)
              sections[i].copyWith(placeIds: [...sections[i].placeIds, placeId])
            else
              sections[i],
        ];
      }
      alreadyIn.add(placeId);
    }

    final updated = board.copyWith(sections: sections);
    boards.value = [
      for (final b in boards.value)
        if (b.id == boardId) updated else b,
    ];
    await _repository.upsert(updated);
  }

  /// True if board [boardId] has any section containing [placeId].
  bool containsPlace(String boardId, String placeId) {
    final board = byIdOrNull(boardId);
    if (board == null) return false;
    return board.sections.any((section) => section.placeIds.contains(placeId));
  }

  /// All boards with at least one section containing [placeId] — for a ✓
  /// "which boards is this saved to" picker.
  List<Board> boardsContaining(String placeId) {
    return boards.value
        .where((board) => containsPlace(board.id, placeId))
        .toList();
  }
}
