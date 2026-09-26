import '../models/board.dart';
import '../models/place.dart';
import '../models/shared_board.dart';

/// Outcome of [SharedBoardRepository.join].
enum JoinOutcome {
  joined,

  /// The rules refused: wrong/old code, link off, a role other than the
  /// link's, or no such board (indistinguishable to a non-member).
  denied,
}

/// Backs [SharedBoardStore] — collaborative boards at top-level
/// `sharedBoards/{id}` with place copies in `sharedBoards/{id}/places`.
/// Signed-in only; [FirestoreSharedBoardRepository] is the real one.
/// Every method is a narrow write matching one branch of firestore.rules.
abstract class SharedBoardRepository {
  /// Boards where [uid] is a member (`memberIds` array-contains).
  Stream<List<SharedBoard>> watchBoards(String uid);

  /// The place copies of board [boardId].
  Stream<List<Place>> watchPlaces(String boardId);

  /// A fresh document id for [create].
  String newBoardId();

  /// Creates [board] (owner only in members) and writes [places] after it —
  /// the places' rules read the board doc, so it must exist first.
  Future<void> create(SharedBoard board, List<Place> places);

  /// Reads board [boardId], or null when missing or not readable (not a
  /// member yet).
  Future<SharedBoard?> fetch(String boardId);

  /// Owner/editor: replaces the sections, upserting [upsertPlaces] copies
  /// and deleting [deletePlaceIds] docs.
  Future<void> updateSections(
    String boardId,
    List<BoardSection> sections, {
    List<Place> upsertPlaces = const [],
    Set<String> deletePlaceIds = const {},
  });

  /// Owner: board name.
  Future<void> rename(String boardId, String name);

  /// Owner: link mode (null = off) and/or a new invite code.
  Future<void> updateLink(
    String boardId, {
    required BoardRole? linkRole,
    required String inviteCode,
  });

  /// Owner: the notes toggle, re-writing [refreshedPlaces] copies to match.
  Future<void> setIncludeOwnerNotes(
    String boardId,
    bool include,
    List<Place> refreshedPlaces,
  );

  /// Owner: change a member's role.
  Future<void> setMemberRole(String boardId, String uid, BoardRole role);

  /// Owner removing [uid], or a member removing themself (leave).
  Future<void> removeMember(String boardId, String uid);

  /// Owner removing [uid] and resetting the invite code in the same write,
  /// so the removed member's old link stops working immediately. Not used
  /// for self-leave — [isSelfLeave] in firestore.rules doesn't allow the
  /// invite code to change.
  Future<void> removeMemberResetLink(
    String boardId,
    String uid, {
    required String inviteCode,
  });

  /// Blind self-join with an invite [code], claiming [role] — must equal the
  /// board's `linkRole` for the rules to accept it.
  Future<JoinOutcome> join(
    String boardId, {
    required String code,
    required String uid,
    required String name,
    required BoardRole role,
  });

  /// Owner: deletes every place copy, then the board.
  Future<void> delete(String boardId);
}
