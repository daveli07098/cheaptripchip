import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/shared_board.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

SharedBoard _board() => const SharedBoard(
  id: 'sb1',
  ownerId: 'alice',
  ownerName: 'Alice',
  name: 'Tokyo',
  emoji: '🗼',
  sections: [
    BoardSection(title: 'Food', placeIds: ['p1']),
  ],
  members: {'alice': BoardRole.owner, 'vera': BoardRole.viewer},
  memberNames: {'alice': 'Alice', 'vera': 'Vera'},
  linkRole: BoardRole.viewer,
  inviteCode: 'abcdefghijklmnopqrstuvwx',
);

void main() {
  group('BoardPermissions', () {
    test('owner can do everything but leave', () {
      final can = BoardPermissions.forRole(BoardRole.owner);
      expect(can.canEditPlaces, isTrue);
      expect(can.canManage, isTrue);
      expect(can.canLeave, isFalse);
      expect(can.canSaveCopies, isFalse);
    });

    test('editor edits places but cannot manage', () {
      final can = BoardPermissions.forRole(BoardRole.editor);
      expect(can.canEditPlaces, isTrue);
      expect(can.canManage, isFalse);
      expect(can.canLeave, isTrue);
      expect(can.canSaveCopies, isTrue);
    });

    test('viewer is read only', () {
      final can = BoardPermissions.forRole(BoardRole.viewer);
      expect(can.canEditPlaces, isFalse);
      expect(can.canManage, isFalse);
      expect(can.canLeave, isTrue);
      expect(can.canSaveCopies, isTrue);
    });

    test('non-member gets nothing; personal boards are fully editable', () {
      final none = BoardPermissions.forRole(null);
      expect(none.canEditPlaces || none.canManage || none.canLeave, isFalse);
      expect(BoardPermissions.personal.canEditPlaces, isTrue);
      expect(BoardPermissions.personal.canManage, isTrue);
    });
  });

  group('members / memberIds sync', () {
    test('withMember adds to members, memberIds and memberNames', () {
      final board = _board().withMember('eddie', BoardRole.editor, name: 'Ed');
      expect(board.members['eddie'], BoardRole.editor);
      expect(board.memberIds.toSet(), {'alice', 'vera', 'eddie'});
      expect(board.memberNames['eddie'], 'Ed');
      expect(board.toJson()['memberIds'], hasLength(3));
    });

    test('withoutMember removes everywhere but never the owner', () {
      final board = _board().withoutMember('vera');
      expect(board.memberIds, ['alice']);
      expect(board.memberNames.keys, ['alice']);
      expect(board.withoutMember('alice').memberIds, ['alice']);
    });

    test('toJson memberIds always equals members keys', () {
      final json = _board()
          .withMember('eddie', BoardRole.editor)
          .withoutMember('vera')
          .toJson();
      expect(
        (json['memberIds'] as List).toSet(),
        (json['members'] as Map).keys.toSet(),
      );
    });

    test('roleOf trusts ownerId, not a forged owner entry', () {
      final board = _board().withMember('mallory', BoardRole.owner);
      expect(board.roleOf('alice'), BoardRole.owner);
      expect(board.roleOf('mallory'), isNull);
      expect(board.roleOf('vera'), BoardRole.viewer);
      expect(board.roleOf('stranger'), isNull);
      expect(board.roleOf(null), isNull);
    });
  });

  group('json', () {
    test('round-trips', () {
      final board = _board();
      final back = SharedBoard.fromJson(board.id, board.toJson());
      expect(back.toJson(), board.toJson());
      expect(back.linkRole, BoardRole.viewer);
    });

    test('link off serialises as null and unknown roles are dropped', () {
      final json = _board().copyWith(clearLinkRole: true).toJson();
      expect(json['linkRole'], isNull);
      json['members'] = {'alice': 'owner', 'x': 'superuser'};
      final back = SharedBoard.fromJson('id', json);
      expect(back.linkRole, isNull);
      expect(back.members.keys, ['alice']);
    });
  });

  test('sharedCopyOf strips private fields unless notes are included', () {
    final place = Place(
      id: 'p1',
      name: 'Ramen',
      areaLabel: '',
      region: '',
      category: PlaceCategory.food,
      location: const LatLng(35, 139),
      descriptionEn: '',
      originalCaption: '',
      address: '',
      hours: '',
      sourceHandle: '',
      sourcePlatform: SourcePlatform.instagram,
      isFavorite: true,
      myScore: 9,
      myNotes: 'secret',
      myPhotoAt: DateTime.utc(2026),
    );
    final stripped = sharedCopyOf(place);
    expect(stripped.myScore, isNull);
    expect(stripped.myNotes, '');
    expect(stripped.myPhotoAt, isNull);
    expect(stripped.isFavorite, isFalse);
    expect(stripped.name, 'Ramen');

    final withNotes = sharedCopyOf(place, includeOwnerNotes: true);
    expect(withNotes.myScore, 9);
    expect(withNotes.myNotes, 'secret');
    // The photo lives in the owner's private collection either way.
    expect(withNotes.myPhotoAt, isNull);
  });

  test('sectionsWithChanges removes, prunes, and adds by title', () {
    final sections = sectionsWithChanges(
      const [
        BoardSection(title: 'Food', placeIds: ['a', 'b']),
        BoardSection(title: 'Cafe', placeIds: ['c']),
      ],
      add: ['d', 'a', 'e'],
      remove: {'c', 'e'},
      sectionTitleFor: (id) => id == 'd' ? 'Cafe' : 'Food',
    );
    expect(sections.map((s) => s.title), ['Food', 'Cafe']);
    expect(sections[0].placeIds, ['a', 'b']);
    expect(sections[1].placeIds, ['d']);
  });
}
