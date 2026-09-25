import 'board.dart';
import 'place.dart';

/// A member's role on a [SharedBoard]. Stored by [name] in Firestore
/// (`members.<uid>: 'owner'|'editor'|'viewer'`, see firestore.rules).
enum BoardRole {
  owner('Owner'),
  editor('Can edit'),
  viewer('View only');

  const BoardRole(this.label);

  /// Short user-facing label ("Can edit", "View only").
  final String label;

  static BoardRole? fromName(Object? raw) {
    for (final role in values) {
      if (role.name == raw) return role;
    }
    return null;
  }
}

/// What the current user may do with a board — the single source of truth
/// for which edit affordances the Boards UI shows. Mirrors firestore.rules:
/// owner = everything, editor = places & sections, viewer = read only.
class BoardPermissions {
  const BoardPermissions._({
    required this.canEditPlaces,
    required this.canManage,
    required this.canLeave,
    required this.canSaveCopies,
  });

  /// A personal (unshared) board: the user owns it outright.
  static const personal = BoardPermissions._(
    canEditPlaces: true,
    canManage: true,
    canLeave: false,
    canSaveCopies: false,
  );

  /// The read-only auto-generated "New finds" board.
  static const auto = BoardPermissions._(
    canEditPlaces: false,
    canManage: false,
    canLeave: false,
    canSaveCopies: false,
  );

  /// Permissions on a shared board for [role]; `null` (not a member) grants
  /// nothing.
  factory BoardPermissions.forRole(BoardRole? role) {
    return switch (role) {
      BoardRole.owner => const BoardPermissions._(
        canEditPlaces: true,
        canManage: true,
        canLeave: false,
        canSaveCopies: false,
      ),
      BoardRole.editor => const BoardPermissions._(
        canEditPlaces: true,
        canManage: false,
        canLeave: true,
        canSaveCopies: true,
      ),
      BoardRole.viewer => const BoardPermissions._(
        canEditPlaces: false,
        canManage: false,
        canLeave: true,
        canSaveCopies: true,
      ),
      null => auto,
    };
  }

  /// Add/remove places and sections.
  final bool canEditPlaces;

  /// Rename, delete, and change sharing settings (link, members, notes).
  final bool canManage;

  /// Leave a board shared with you (the owner stops sharing instead).
  final bool canLeave;

  /// "Save to my places" on a board's rows — places that aren't yours.
  final bool canSaveCopies;
}

/// A collaborative board at `sharedBoards/{id}`; its places are copies at
/// `sharedBoards/{id}/places/{placeId}` (see lib/data/shared_board_repository.dart).
///
/// [members] and [memberIds] must always hold the same uids — firestore.rules
/// rejects any write that lets them drift. Build changes with [withMember] /
/// [withoutMember], which keep them in sync.
class SharedBoard {
  const SharedBoard({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.name,
    required this.emoji,
    required this.sections,
    required this.members,
    required this.memberNames,
    required this.inviteCode,
    this.linkRole,
    this.includeOwnerNotes = false,
  });

  final String id;
  final String ownerId;
  final String ownerName;
  final String name;
  final String emoji;
  final List<BoardSection> sections;

  /// uid → role. The owner is always present as [BoardRole.owner].
  final Map<String, BoardRole> members;

  /// uid → display name, for the members list.
  final Map<String, String> memberNames;

  /// The role anyone opening the invite link gets; `null` = link off.
  final BoardRole? linkRole;

  /// Random secret in the invite link; "Reset link" replaces it.
  final String inviteCode;

  /// Whether the owner's own scores & notes ride along on the place copies.
  final bool includeOwnerNotes;

  /// [members]' uids — written as the `memberIds` array the Boards tab
  /// queries with array-contains (Firestore can't query map keys).
  List<String> get memberIds => members.keys.toList();

  /// The [Board] view the Boards UI renders.
  Board get board =>
      Board(id: id, name: name, emoji: emoji, sections: sections);

  int get memberCount => members.length;

  BoardRole? roleOf(String? uid) {
    if (uid == null) return null;
    if (uid == ownerId) return BoardRole.owner;
    final role = members[uid];
    // Only ownerId is the owner, whatever the map claims.
    return role == BoardRole.owner ? null : role;
  }

  SharedBoard copyWith({
    String? name,
    String? emoji,
    List<BoardSection>? sections,
    Map<String, BoardRole>? members,
    Map<String, String>? memberNames,
    BoardRole? linkRole,
    bool clearLinkRole = false,
    String? inviteCode,
    bool? includeOwnerNotes,
  }) {
    return SharedBoard(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      sections: sections ?? this.sections,
      members: members ?? this.members,
      memberNames: memberNames ?? this.memberNames,
      linkRole: clearLinkRole ? null : (linkRole ?? this.linkRole),
      inviteCode: inviteCode ?? this.inviteCode,
      includeOwnerNotes: includeOwnerNotes ?? this.includeOwnerNotes,
    );
  }

  /// Adds (or re-roles) [uid]; [name] updates [memberNames] when given.
  SharedBoard withMember(String uid, BoardRole role, {String? name}) {
    return copyWith(
      members: {...members, uid: role},
      memberNames: name == null ? memberNames : {...memberNames, uid: name},
    );
  }

  /// Removes [uid] from [members] and [memberNames]. The owner can't be
  /// removed — returns this board unchanged for [ownerId].
  SharedBoard withoutMember(String uid) {
    if (uid == ownerId) return this;
    return copyWith(
      members: {...members}..remove(uid),
      memberNames: {...memberNames}..remove(uid),
    );
  }

  /// Plain JSON for Firestore (the repository adds timestamps).
  Map<String, dynamic> toJson() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'name': name,
      'emoji': emoji,
      'sections': sections.map((section) => section.toJson()).toList(),
      'members': {
        for (final entry in members.entries) entry.key: entry.value.name,
      },
      'memberIds': memberIds,
      'memberNames': memberNames,
      'linkRole': linkRole?.name,
      'inviteCode': inviteCode,
      'includeOwnerNotes': includeOwnerNotes,
    };
  }

  /// Lenient parse; unknown roles are dropped. [id] is the document id.
  factory SharedBoard.fromJson(String id, Map<String, dynamic> json) {
    final rawMembers = json['members'] is Map
        ? Map<String, dynamic>.from(json['members'] as Map)
        : const <String, dynamic>{};
    final members = <String, BoardRole>{};
    rawMembers.forEach((uid, raw) {
      final role = BoardRole.fromName(raw);
      if (role != null) members[uid] = role;
    });
    final rawNames = json['memberNames'] is Map
        ? Map<String, dynamic>.from(json['memberNames'] as Map)
        : const <String, dynamic>{};
    return SharedBoard(
      id: id,
      ownerId: json['ownerId'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      name: json['name'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '📌',
      sections:
          (json['sections'] as List?)
              ?.map(
                (section) => BoardSection.fromJson(
                  Map<String, dynamic>.from(section as Map),
                ),
              )
              .toList() ??
          const [],
      members: members,
      memberNames: {
        for (final entry in rawNames.entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
      linkRole: BoardRole.fromName(json['linkRole']),
      inviteCode: json['inviteCode'] as String? ?? '',
      includeOwnerNotes: json['includeOwnerNotes'] == true,
    );
  }
}

/// The copy of [place] stored on a shared board: the owner's private fields
/// (score, notes, favourite) are dropped unless [includeOwnerNotes]. The
/// photo marker always goes — the photo itself lives under the owner's
/// `users/{uid}/photos`, which other members can't read.
Place sharedCopyOf(Place place, {bool includeOwnerNotes = false}) {
  return place.copyWith(
    clearMyPhotoAt: true,
    isFavorite: false,
    clearMyScore: !includeOwnerNotes,
    myNotes: includeOwnerNotes ? place.myNotes : '',
  );
}
