import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../models/place.dart';
import '../models/place_rating.dart';
import '../models/shared_board.dart';
import '../services/auth_service.dart';
import '../services/board_invite_link.dart';
import '../services/import_service.dart';
import 'board_store.dart';
import 'firestore_shared_board_repository.dart';
import 'place_store.dart';
import 'shared_board_repository.dart';

/// Result of [SharedBoardStore.join].
enum JoinResult {
  joined,

  /// Already on the board — nothing written.
  alreadyMember,

  /// The link was reset, turned off, or never valid.
  invalid,

  /// Not signed in / store not bound.
  signedOut,
}

/// Runtime store for collaborative boards the signed-in user belongs to,
/// live via [SharedBoardRepository] snapshot listeners. Empty in guest mode —
/// sharing needs an account. Bound alongside the other stores in main.dart.
///
/// Personal boards stay in [BoardStore]; "Share board…" MOVES one here
/// ([shareBoard]) and "Stop sharing" moves it back ([stopSharing]).
class SharedBoardStore {
  SharedBoardStore._();
  static final SharedBoardStore instance = SharedBoardStore._();

  /// Boards the user is a member of (any role).
  final ValueNotifier<List<SharedBoard>> boards =
      ValueNotifier<List<SharedBoard>>(const []);

  /// Place copies per board id, keyed by place id.
  final ValueNotifier<Map<String, Map<String, Place>>> places =
      ValueNotifier<Map<String, Map<String, Place>>>(const {});

  SharedBoardRepository? _repository;
  AppUser? _user;
  StreamSubscription<List<SharedBoard>>? _boardsSub;
  final Map<String, StreamSubscription<List<Place>>> _placeSubs = {};

  static final Random _idRandom = Random();

  /// The signed-in member's uid, or null in guest mode.
  String? get uid => _user?.uid;

  /// Binds to [user]'s boards, or clears everything for guests. Doesn't
  /// touch Firestore when [user] is null (tests run without Firebase).
  void bind(AppUser? user) {
    if (user == null) {
      _unbind();
      return;
    }
    // userChanges() also fires on profile updates — keep the listeners.
    if (_user?.uid == user.uid && _repository != null) {
      _user = user;
      return;
    }
    bindRepository(FirestoreSharedBoardRepository(), user);
  }

  /// Test seam: bind to [repository] as [user].
  @visibleForTesting
  void bindRepository(SharedBoardRepository repository, AppUser user) {
    _unbind();
    _repository = repository;
    _user = user;
    _boardsSub = repository
        .watchBoards(user.uid)
        .listen(
          _onBoards,
          onError: (Object error) {
            // e.g. rules not deployed yet — sharing just stays empty.
            debugPrint('SharedBoardStore: boards unavailable: $error');
            _onBoards(const []);
          },
        );
  }

  void _unbind() {
    _boardsSub?.cancel();
    _boardsSub = null;
    for (final sub in _placeSubs.values) {
      sub.cancel();
    }
    _placeSubs.clear();
    _repository = null;
    _user = null;
    boards.value = const [];
    places.value = const {};
  }

  void _onBoards(List<SharedBoard> value) {
    boards.value = value;
    final ids = {for (final board in value) board.id};
    for (final id in _placeSubs.keys.toList()) {
      if (!ids.contains(id)) _dropPlaces(id);
    }
    final repository = _repository;
    if (repository == null) return;
    for (final id in ids) {
      _placeSubs[id] ??= repository
          .watchPlaces(id)
          .listen(
            (list) => places.value = {
              ...places.value,
              id: {for (final place in list) place.id: place},
            },
            // Removed from the board / board deleted: permission-denied.
            onError: (Object error) => _dropPlaces(id),
          );
    }
  }

  void _dropPlaces(String boardId) {
    _placeSubs.remove(boardId)?.cancel();
    if (places.value.containsKey(boardId)) {
      places.value = {...places.value}..remove(boardId);
    }
  }

  SharedBoard? byIdOrNull(String id) {
    for (final board in boards.value) {
      if (board.id == id) return board;
    }
    return null;
  }

  Map<String, Place> placesOf(String boardId) =>
      places.value[boardId] ?? const {};

  BoardRole? roleOn(String boardId) => byIdOrNull(boardId)?.roleOf(uid);

  void _replace(SharedBoard board) {
    boards.value = [
      for (final b in boards.value)
        if (b.id == board.id) board else b,
    ];
  }

  String _displayName(AppUser user) {
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'Someone');
    return name.length > 100 ? name.substring(0, 100) : name;
  }

  /// Moves personal [personal] board to a new shared board owned by the
  /// user: copies the board and its places' public fields (link off, notes
  /// excluded), then deletes the personal board. The user's own places stay
  /// in Saved — the copies keep the same ids so sections resolve.
  Future<SharedBoard?> shareBoard(Board personal) async {
    final repository = _repository;
    final user = _user;
    if (repository == null || user == null) return null;

    final copies = <Place>[];
    final seen = <String>{};
    final sections = <BoardSection>[];
    for (final section in personal.sections) {
      final ids = <String>[];
      for (final id in section.placeIds) {
        final place = PlaceStore.instance.byIdOrNull(id);
        if (place == null) continue;
        ids.add(id);
        if (seen.add(id)) copies.add(sharedCopyOf(place));
      }
      if (ids.isNotEmpty) sections.add(section.copyWith(placeIds: ids));
    }

    final board = SharedBoard(
      id: repository.newBoardId(),
      ownerId: user.uid,
      ownerName: _displayName(user),
      name: personal.name,
      emoji: personal.emoji,
      sections: sections,
      members: {user.uid: BoardRole.owner},
      memberNames: {user.uid: _displayName(user)},
      inviteCode: BoardInviteLink.generateCode(),
    );
    await repository.create(board, copies);
    if (byIdOrNull(board.id) == null) {
      boards.value = [board, ...boards.value];
    }
    await BoardStore.instance.deleteBoard(personal.id);
    return board;
  }

  /// Owner/editor: adds [newPlaces] (copied, owner notes only when the
  /// owner adds them with the toggle on) and removes [remove] ids, in one
  /// sections write. Added places go to [sectionTitle] or their category's
  /// section. Place docs no longer referenced are deleted.
  Future<void> updatePlaces(
    String boardId, {
    List<Place> newPlaces = const [],
    Set<String> remove = const {},
    String? sectionTitle,
  }) async {
    final repository = _repository;
    final board = byIdOrNull(boardId);
    if (repository == null || board == null) return;
    if (!BoardPermissions.forRole(board.roleOf(uid)).canEditPlaces) return;
    if (newPlaces.isEmpty && remove.isEmpty) return;

    final byId = {for (final place in newPlaces) place.id: place};
    final sections = sectionsWithChanges(
      board.sections,
      add: byId.keys,
      remove: remove,
      sectionTitleFor: (id) =>
          sectionTitle ?? byId[id]?.category.labelEn ?? 'Saved',
    );
    final stillIn = {for (final s in sections) ...s.placeIds};
    final includeNotes =
        board.includeOwnerNotes && board.roleOf(uid) == BoardRole.owner;
    final copies = [
      for (final place in byId.values)
        if (stillIn.contains(place.id))
          sharedCopyOf(place, includeOwnerNotes: includeNotes),
    ];
    final existing = placesOf(boardId);
    _replace(board.copyWith(sections: sections));
    places.value = {
      ...places.value,
      boardId: {
        for (final entry in existing.entries)
          if (stillIn.contains(entry.key)) entry.key: entry.value,
        for (final copy in copies) copy.id: copy,
      },
    };
    await repository.updateSections(
      boardId,
      sections,
      upsertPlaces: copies,
      deletePlaceIds: remove.difference(stillIn),
    );
  }

  /// AddPlacesSheet's apply for a shared board: [add] ids resolve against
  /// the user's own [PlaceStore].
  Future<void> updateFromSaved(
    String boardId, {
    required Set<String> add,
    required Set<String> remove,
  }) {
    return updatePlaces(
      boardId,
      newPlaces: [for (final id in add) ?PlaceStore.instance.byIdOrNull(id)],
      remove: remove,
    );
  }

  /// Removes [placeId] from board [boardId]; returns the removed copy and
  /// the section titles it was in (for undo via [updatePlaces]), or null.
  Future<(Place, List<String>)?> removePlace(
    String boardId,
    String placeId,
  ) async {
    final board = byIdOrNull(boardId);
    final place = placesOf(boardId)[placeId];
    if (board == null || place == null) return null;
    final titles = [
      for (final section in board.sections)
        if (section.placeIds.contains(placeId)) section.title,
    ];
    await updatePlaces(boardId, remove: {placeId});
    return (place, titles);
  }

  /// Owner: rename.
  Future<void> rename(String boardId, String name) async {
    final trimmed = name.trim();
    final board = byIdOrNull(boardId);
    if (trimmed.isEmpty || board == null || _repository == null) return;
    _replace(board.copyWith(name: trimmed));
    await _repository!.rename(boardId, trimmed);
  }

  /// Owner: link mode; null turns the link off.
  Future<void> setLinkRole(String boardId, BoardRole? role) async {
    final board = byIdOrNull(boardId);
    if (board == null || _repository == null) return;
    assert(role != BoardRole.owner, 'links never grant ownership');
    _replace(board.copyWith(linkRole: role, clearLinkRole: role == null));
    await _repository!.updateLink(
      boardId,
      linkRole: role,
      inviteCode: board.inviteCode,
    );
  }

  /// Owner: a new invite code — links sent so far stop working.
  Future<void> resetLink(String boardId) async {
    final board = byIdOrNull(boardId);
    if (board == null || _repository == null) return;
    final code = BoardInviteLink.generateCode();
    _replace(board.copyWith(inviteCode: code));
    await _repository!.updateLink(
      boardId,
      linkRole: board.linkRole,
      inviteCode: code,
    );
  }

  /// Owner: include (or drop) their scores & notes on the copies of their
  /// own places already on the board.
  Future<void> setIncludeOwnerNotes(String boardId, bool include) async {
    final board = byIdOrNull(boardId);
    if (board == null || _repository == null) return;
    final ownPlaces = [
      for (final id in placesOf(boardId).keys)
        if (PlaceStore.instance.byIdOrNull(id) case final place?)
          sharedCopyOf(place, includeOwnerNotes: include),
    ];
    _replace(board.copyWith(includeOwnerNotes: include));
    await _repository!.setIncludeOwnerNotes(boardId, include, ownPlaces);
  }

  /// Owner: change [memberUid]'s role (editor/viewer).
  Future<void> setMemberRole(
    String boardId,
    String memberUid,
    BoardRole role,
  ) async {
    final board = byIdOrNull(boardId);
    if (board == null || _repository == null) return;
    if (memberUid == board.ownerId || role == BoardRole.owner) return;
    _replace(board.withMember(memberUid, role));
    await _repository!.setMemberRole(boardId, memberUid, role);
  }

  /// Owner: remove [memberUid] from the board, resetting the invite code in
  /// the same write — the removed member's old link stops working right
  /// away instead of only after a separate "Reset link".
  Future<void> removeMember(String boardId, String memberUid) async {
    final board = byIdOrNull(boardId);
    if (board == null || _repository == null) return;
    if (memberUid == board.ownerId) return;
    final code = BoardInviteLink.generateCode();
    _replace(board.withoutMember(memberUid).copyWith(inviteCode: code));
    await _repository!.removeMemberResetLink(
      boardId,
      memberUid,
      inviteCode: code,
    );
  }

  /// Non-owner: leave the board (it disappears from the Boards tab).
  Future<void> leave(String boardId) async {
    final board = byIdOrNull(boardId);
    final me = uid;
    if (board == null || me == null || _repository == null) return;
    if (me == board.ownerId) return;
    boards.value = [
      for (final b in boards.value)
        if (b.id != boardId) b,
    ];
    _dropPlaces(boardId);
    await _repository!.removeMember(boardId, me);
  }

  /// Owner: delete the board for everyone.
  Future<void> delete(String boardId) async {
    if (_repository == null) return;
    boards.value = [
      for (final b in boards.value)
        if (b.id != boardId) b,
    ];
    _dropPlaces(boardId);
    await _repository!.delete(boardId);
  }

  /// Owner: turns the board back into a personal board — places others
  /// added are saved into the owner's Saved (deduped) — then deletes the
  /// shared board, removing everyone else's access.
  Future<Board?> stopSharing(String boardId, {PlaceStore? placeStore}) async {
    final board = byIdOrNull(boardId);
    if (board == null || _repository == null) return null;
    final copies = placesOf(boardId);
    final result = await ImportService.importSections(
      boardName: board.name,
      emoji: board.emoji,
      sections: [
        for (final section in board.sections)
          ImportSection(section.title, [
            for (final id in section.placeIds) ?copies[id],
          ]),
      ],
      placeStore: placeStore,
    );
    await delete(boardId);
    return result.board;
  }

  /// Whether [place] (or an equivalent — [ImportService.isDuplicate]) is
  /// already in [placeStore]'s Saved list. Shared by [saveToMyPlaces] and
  /// the shared-board place detail sheet's "Save to my places" button, so
  /// both agree on what counts as a duplicate.
  bool isSaved(Place place, {PlaceStore? placeStore}) {
    final store = placeStore ?? PlaceStore.instance;
    for (final saved in store.places.value) {
      if (saved.id == place.id || ImportService.isDuplicate(saved, place)) {
        return true;
      }
    }
    return false;
  }

  /// Copies a board place into the user's own Saved list with a fresh id
  /// and no one else's notes. Returns false when an equivalent place
  /// ([ImportService.isDuplicate]) is already saved.
  Future<bool> saveToMyPlaces(Place place, {PlaceStore? placeStore}) async {
    if (isSaved(place, placeStore: placeStore)) return false;
    final store = placeStore ?? PlaceStore.instance;
    final id =
        'shared-${DateTime.now().millisecondsSinceEpoch}-'
        '${_idRandom.nextInt(10000).toString().padLeft(4, '0')}';
    await store.add(
      place.copyWith(
        id: id,
        clearMyScore: true,
        myNotes: '',
        clearMyPhotoAt: true,
        isFavorite: false,
      ),
    );
    return true;
  }

  /// Every member's rating of [placeId] on [boardId], live. Empty when
  /// signed out/unbound; a read error (e.g. rules not deployed, removed
  /// from the board) also reads as "no ratings" rather than breaking the
  /// place page.
  Stream<List<PlaceRating>> watchRatings(String boardId, String placeId) {
    final repository = _repository;
    if (repository == null) return Stream.value(const []);
    return repository.watchRatings(boardId, placeId).handleError((
      Object error,
    ) {
      debugPrint('SharedBoardStore: ratings unavailable: $error');
    });
  }

  /// Sets the signed-in member's own rating of [placeId] on [boardId] —
  /// any role may rate. A null [score] deletes the rating (remark included):
  /// the rules require a score on every rating doc. [notes] is trimmed and
  /// capped at [PlaceRating.maxNotesLength].
  Future<void> setMyRating(
    String boardId,
    String placeId, {
    required int? score,
    String notes = '',
  }) async {
    final repository = _repository;
    final user = _user;
    if (repository == null || user == null) return;
    // Not (or no longer) a member — the rules would deny it anyway.
    if (roleOn(boardId) == null) return;
    if (score == null) {
      await repository.deleteRating(boardId, placeId, user.uid);
      return;
    }
    var trimmed = notes.trim();
    if (trimmed.length > PlaceRating.maxNotesLength) {
      trimmed = trimmed.substring(0, PlaceRating.maxNotesLength);
    }
    final photoUrl = user.photoUrl;
    await repository.setRating(
      boardId,
      PlaceRating(
        uid: user.uid,
        placeId: placeId,
        displayName: _displayName(user),
        photoUrl: photoUrl != null && photoUrl.length <= 2000 ? photoUrl : null,
        score: score.clamp(1, 10),
        notes: trimmed,
      ),
    );
  }

  /// Joins board [invite.boardId] with its invite code. Already a member →
  /// nothing written. The link's role isn't readable before joining, so
  /// this tries editor, then viewer — the rules accept only the link's role.
  Future<(JoinResult, SharedBoard?)> join(BoardInvite invite) async {
    final repository = _repository;
    final user = _user;
    if (repository == null || user == null) {
      return (JoinResult.signedOut, null);
    }
    final existing = await repository.fetch(invite.boardId);
    if (existing != null && existing.members.containsKey(user.uid)) {
      return (JoinResult.alreadyMember, existing);
    }
    for (final role in const [BoardRole.editor, BoardRole.viewer]) {
      final outcome = await repository.join(
        invite.boardId,
        code: invite.code,
        uid: user.uid,
        name: _displayName(user),
        role: role,
      );
      if (outcome == JoinOutcome.joined) {
        return (JoinResult.joined, await repository.fetch(invite.boardId));
      }
    }
    return (JoinResult.invalid, null);
  }
}
