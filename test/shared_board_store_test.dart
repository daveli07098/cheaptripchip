import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/data/shared_board_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_rating.dart';
import 'package:cheaptripchip/models/shared_board.dart';
import 'package:cheaptripchip/services/auth_service.dart';
import 'package:cheaptripchip/services/board_invite_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes/fake_shared_board_repository.dart';

Place _place(String id, {String? name, int? score, String notes = ''}) => Place(
  id: id,
  name: name ?? 'Place $id',
  areaLabel: '',
  region: 'Tokyo',
  category: PlaceCategory.food,
  location: LatLng(35 + id.hashCode % 100 / 1000, 139),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
  myScore: score,
  myNotes: notes,
);

const _alice = AppUser(uid: 'alice', displayName: 'Alice');
const _bob = AppUser(uid: 'bob', displayName: 'Bob');
const _code = 'abcdefghijklmnopqrstuvwx';

SharedBoard _aliceBoard({BoardRole? linkRole = BoardRole.viewer}) =>
    SharedBoard(
      id: 'sb',
      ownerId: 'alice',
      ownerName: 'Alice',
      name: 'Tokyo',
      emoji: '🗼',
      sections: const [
        BoardSection(title: 'Food', placeIds: ['p1']),
      ],
      members: const {'alice': BoardRole.owner},
      memberNames: const {'alice': 'Alice'},
      linkRole: linkRole,
      inviteCode: _code,
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSharedBoardRepository repo;
  final store = SharedBoardStore.instance;

  setUp(() async {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    repo = FakeSharedBoardRepository();
    await _settle();
  });

  tearDown(() => store.bind(null));

  test('bind(null) clears everything', () async {
    repo.seed(_aliceBoard(), [_place('p1')]);
    store.bindRepository(repo, _alice);
    await _settle();
    expect(store.boards.value, hasLength(1));
    expect(store.placesOf('sb'), contains('p1'));
    store.bind(null);
    expect(store.boards.value, isEmpty);
    expect(store.places.value, isEmpty);
    expect(store.uid, isNull);
  });

  test('shareBoard moves a personal board and strips private fields', () async {
    await PlaceStore.instance.add(_place('p1', score: 9, notes: 'secret'));
    await PlaceStore.instance.add(_place('p2'));
    final personal = await BoardStore.instance.createBoard(
      'Trip',
      sections: const [
        BoardSection(title: 'Food', placeIds: ['p1', 'p2', 'gone']),
      ],
    );
    store.bindRepository(repo, _alice);
    await _settle();

    final shared = await store.shareBoard(personal);
    await _settle();

    expect(shared, isNotNull);
    expect(BoardStore.instance.byIdOrNull(personal.id), isNull);
    expect(PlaceStore.instance.byIdOrNull('p1'), isNotNull);
    final stored = repo.boards[shared!.id]!;
    expect(stored.roleOf('alice'), BoardRole.owner);
    expect(stored.memberIds, ['alice']);
    expect(stored.linkRole, isNull);
    expect(stored.inviteCode.length, greaterThanOrEqualTo(22));
    expect(stored.sections.single.placeIds, ['p1', 'p2']);
    final copy = repo.places[shared.id]!['p1']!;
    expect(copy.myScore, isNull);
    expect(copy.myNotes, '');
    expect(store.boards.value.single.id, shared.id);
  });

  test('join tries the link role and adds the member', () async {
    repo.seed(_aliceBoard(linkRole: BoardRole.viewer), [_place('p1')]);
    store.bindRepository(repo, _bob);
    await _settle();

    final (result, board) = await store.join(
      const BoardInvite(boardId: 'sb', code: _code),
    );
    await _settle();

    expect(result, JoinResult.joined);
    expect(board!.roleOf('bob'), BoardRole.viewer);
    expect(repo.boards['sb']!.memberIds.toSet(), {'alice', 'bob'});
    expect(repo.boards['sb']!.memberNames['bob'], 'Bob');
    expect(store.boards.value.single.id, 'sb');
    expect(store.placesOf('sb'), contains('p1'));
  });

  test('join with a bad code or a link that is off is invalid', () async {
    repo.seed(_aliceBoard());
    store.bindRepository(repo, _bob);
    final (bad, _) = await store.join(
      const BoardInvite(boardId: 'sb', code: 'wrong-code-wrong-code-00'),
    );
    expect(bad, JoinResult.invalid);

    repo.seed(_aliceBoard(linkRole: null));
    final (off, _) = await store.join(
      const BoardInvite(boardId: 'sb', code: _code),
    );
    expect(off, JoinResult.invalid);
    expect(repo.boards['sb']!.members.containsKey('bob'), isFalse);
  });

  test('join when already a member writes nothing', () async {
    repo.seed(_aliceBoard());
    store.bindRepository(repo, _alice);
    final (result, _) = await store.join(
      const BoardInvite(boardId: 'sb', code: _code),
    );
    expect(result, JoinResult.alreadyMember);
    expect(repo.joinAttempts, isEmpty);
    expect(repo.boards['sb']!.roleOf('alice'), BoardRole.owner);
  });

  test('join while signed out does nothing', () async {
    final (result, _) = await store.join(
      const BoardInvite(boardId: 'sb', code: _code),
    );
    expect(result, JoinResult.signedOut);
  });

  test('viewer cannot change places; editor can', () async {
    repo.seed(_aliceBoard().withMember('bob', BoardRole.viewer, name: 'Bob'), [
      _place('p1'),
    ]);
    store.bindRepository(repo, _bob);
    await _settle();

    await store.updatePlaces('sb', newPlaces: [_place('p9')]);
    expect(repo.boards['sb']!.sections.single.placeIds, ['p1']);

    await repo.setMemberRole('sb', 'bob', BoardRole.editor);
    await _settle();
    await store.updatePlaces('sb', newPlaces: [_place('p9')]);
    await _settle();
    expect(repo.boards['sb']!.sections.single.placeIds, ['p1', 'p9']);
    expect(repo.places['sb']!.keys, containsAll(['p1', 'p9']));

    final removed = await store.removePlace('sb', 'p1');
    await _settle();
    expect(removed!.$2, ['Food']);
    expect(repo.places['sb']!.containsKey('p1'), isFalse);
  });

  test('owner manages link, members and notes', () async {
    await PlaceStore.instance.add(_place('p1', score: 7, notes: 'mine'));
    repo.seed(_aliceBoard(linkRole: null).withMember('bob', BoardRole.viewer), [
      sharedCopyOf(_place('p1', score: 7, notes: 'mine')),
    ]);
    store.bindRepository(repo, _alice);
    await _settle();

    await store.setLinkRole('sb', BoardRole.editor);
    expect(repo.boards['sb']!.linkRole, BoardRole.editor);
    await store.resetLink('sb');
    expect(repo.boards['sb']!.inviteCode, isNot(_code));
    await store.setMemberRole('sb', 'bob', BoardRole.editor);
    expect(repo.boards['sb']!.roleOf('bob'), BoardRole.editor);
    await store.setIncludeOwnerNotes('sb', true);
    expect(repo.places['sb']!['p1']!.myNotes, 'mine');
    await store.removeMember('sb', 'bob');
    expect(repo.boards['sb']!.memberIds, ['alice']);
    await store.removeMember('sb', 'alice');
    expect(repo.boards['sb']!.memberIds, ['alice']);
  });

  test(
    'removeMember removes the member and resets the invite link in one write',
    () async {
      repo.seed(
        _aliceBoard(
          linkRole: BoardRole.editor,
        ).withMember('bob', BoardRole.viewer, name: 'Bob'),
      );
      store.bindRepository(repo, _alice);
      await _settle();
      final codeBefore = repo.boards['sb']!.inviteCode;

      await store.removeMember('sb', 'bob');
      await _settle();

      final board = repo.boards['sb']!;
      expect(board.memberIds, ['alice']);
      expect(board.memberNames.containsKey('bob'), isFalse);
      expect(board.inviteCode, isNot(codeBefore));
      expect(board.inviteCode.length, greaterThanOrEqualTo(22));
      expect(store.byIdOrNull('sb')!.inviteCode, board.inviteCode);
      // One combined write, not a member removal plus a separate link reset.
      expect(repo.calls, ['removeMemberResetLink']);
      expect(repo.calls, isNot(contains('updateLink')));
    },
  );

  test('leave removes the board locally and remotely', () async {
    repo.seed(_aliceBoard().withMember('bob', BoardRole.viewer));
    store.bindRepository(repo, _bob);
    await _settle();
    final codeBefore = repo.boards['sb']!.inviteCode;
    await store.leave('sb');
    await _settle();
    expect(store.boards.value, isEmpty);
    expect(repo.boards['sb']!.members.containsKey('bob'), isFalse);
    // Self-leave never resets the link — only the owner's removeMember does.
    expect(repo.boards['sb']!.inviteCode, codeBefore);
  });

  test(
    'stopSharing restores a personal board with everyone\'s places',
    () async {
      await PlaceStore.instance.add(_place('p1', name: 'Mine'));
      repo.seed(
        _aliceBoard().copyWith(
          sections: const [
            BoardSection(title: 'Food', placeIds: ['p1', 'p2']),
          ],
        ),
        [_place('p1', name: 'Mine'), _place('p2', name: 'Theirs')],
      );
      store.bindRepository(repo, _alice);
      await _settle();

      final personal = await store.stopSharing('sb');
      await _settle();

      expect(repo.boards, isEmpty);
      expect(store.boards.value, isEmpty);
      expect(personal!.name, 'Tokyo');
      final ids = personal.sections.single.placeIds;
      expect(ids.first, 'p1'); // the owner's own place, deduped
      expect(ids, hasLength(2));
      expect(
        PlaceStore.instance.places.value.map((p) => p.name),
        containsAll(['Mine', 'Theirs']),
      );
    },
  );

  test('saveToMyPlaces copies once with a fresh id and no notes', () async {
    final theirs = _place('x1', name: 'Sushi', score: 10, notes: 'owner');
    expect(await store.saveToMyPlaces(theirs), isTrue);
    final saved = PlaceStore.instance.places.value.firstWhere(
      (p) => p.name == 'Sushi',
    );
    expect(saved.id, isNot('x1'));
    expect(saved.myScore, isNull);
    expect(saved.myNotes, '');
    expect(await store.saveToMyPlaces(theirs), isFalse);
  });

  group('ratings', () {
    SharedBoard withBob() =>
        _aliceBoard().withMember('bob', BoardRole.viewer, name: 'Bob');

    test(
      'any member (viewer too) sets, updates and deletes their own',
      () async {
        repo.seed(withBob(), [_place('p1')]);
        store.bindRepository(repo, _bob);
        await _settle();

        final seen = <List<PlaceRating>>[];
        final sub = store.watchRatings('sb', 'p1').listen(seen.add);
        await _settle();
        expect(seen.last, isEmpty);

        await store.setMyRating('sb', 'p1', score: 7, notes: '  Nice  ');
        await _settle();
        final mine = seen.last.single;
        expect(mine.uid, 'bob');
        expect(mine.placeId, 'p1');
        expect(mine.displayName, 'Bob');
        expect(mine.score, 7);
        expect(mine.notes, 'Nice');

        await store.setMyRating('sb', 'p1', score: 9, notes: 'x' * 1200);
        await _settle();
        expect(seen.last.single.score, 9);
        expect(seen.last.single.notes, hasLength(PlaceRating.maxNotesLength));

        await store.setMyRating('sb', 'p1', score: null);
        await _settle();
        expect(seen.last, isEmpty);
        expect(repo.calls, ['setRating', 'setRating', 'deleteRating']);
        await sub.cancel();
      },
    );

    test("sees other members' ratings of the same place only", () async {
      repo.seed(withBob(), [_place('p1'), _place('p2')]);
      repo.seedRating(
        'sb',
        const PlaceRating(
          uid: 'alice',
          placeId: 'p1',
          displayName: 'Alice',
          score: 8,
        ),
      );
      repo.seedRating(
        'sb',
        const PlaceRating(
          uid: 'alice',
          placeId: 'p2',
          displayName: 'Alice',
          score: 2,
        ),
      );
      store.bindRepository(repo, _bob);
      await _settle();
      final first = await store.watchRatings('sb', 'p1').first;
      expect(first.single.score, 8);
    });

    test('a removed member writes nothing', () async {
      repo.seed(_aliceBoard(), [_place('p1')]);
      store.bindRepository(repo, _bob);
      await _settle();
      // Bob isn't on the board the store knows about.
      repo.seed(withBob().withoutMember('bob'));
      await _settle();
      await store.setMyRating('sb', 'p1', score: 5);
      expect(repo.calls, isEmpty);
    });

    test('signed out: empty stream, no writes', () async {
      expect(await store.watchRatings('sb', 'p1').first, isEmpty);
      await store.setMyRating('sb', 'p1', score: 5);
      expect(repo.calls, isEmpty);
    });
  });
}
