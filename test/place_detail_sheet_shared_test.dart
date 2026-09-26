// Widget tests for PlaceDetailSheet's read-only shared-board mode
// (PlaceDetailSource.sharedBoard) — see docs/shared-boards.md's place-detail
// follow-up. The personal controls (favourite, my review, photo, area/type
// edit, add to board) must never show for a shared-board place, whatever the
// role, and the id-sharing between a shared copy and the owner's own Saved
// place must not leak the owner's private fields.
import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/data/shared_board_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_rating.dart';
import 'package:cheaptripchip/models/shared_board.dart';
import 'package:cheaptripchip/screens/place_detail_sheet.dart';
import 'package:cheaptripchip/services/auth_service.dart';
import 'package:cheaptripchip/widgets/score_stars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes/fake_shared_board_repository.dart';

// Ids distinct from lib/data/mock_data.dart's seeded p1..p6 — LocalPlaceRepository
// seeds every test's PlaceStore with MockData.places, so an id collision would
// make isSaved/dedupe checks pass for the wrong reason.
Place _place({
  String id = 'sbtest-1',
  String name = 'Ramen House',
  int? score,
  String notes = '',
  bool favorite = false,
}) => Place(
  id: id,
  name: name,
  areaLabel: 'Shibuya',
  region: 'Tokyo',
  category: PlaceCategory.food,
  location: const LatLng(35.6, 139.7),
  descriptionEn: 'Great ramen.',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
  myScore: score,
  myNotes: notes,
  isFavorite: favorite,
);

final _board = SharedBoard(
  id: 'sb',
  ownerId: 'alice',
  ownerName: 'Alice',
  name: 'Tokyo',
  emoji: '🗼',
  sections: const [
    BoardSection(title: 'Food', placeIds: ['sbtest-1']),
  ],
  members: const {
    'alice': BoardRole.owner,
    'bob': BoardRole.viewer,
    'carol': BoardRole.editor,
  },
  memberNames: const {'alice': 'Alice', 'bob': 'Bob', 'carol': 'Carol'},
  inviteCode: 'abcdefghijklmnopqrstuvwx',
);

const _bob = AppUser(uid: 'bob', displayName: 'Bob');

Future<void> _pump(WidgetTester tester, Place place) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlaceDetailSheet(
          place: place,
          source: PlaceDetailSource.sharedBoard(_board, BoardRole.viewer),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late FakeSharedBoardRepository repo;

  setUp(() {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    repo = FakeSharedBoardRepository();
    SharedBoardStore.instance.bindRepository(repo, _bob);
  });

  tearDown(() => SharedBoardStore.instance.bind(null));

  testWidgets('hides personal controls and shows "In your places" for an '
      "already-saved place", (tester) async {
    final mine = _place(score: 9, notes: 'My secret notes', favorite: true);
    await PlaceStore.instance.add(mine);
    // The owner's copy keeps the same id as the owner's own Saved place —
    // sharedCopyOf strips the private fields (no includeOwnerNotes here).
    final shared = sharedCopyOf(mine);
    await _pump(tester, shared);

    expect(find.byTooltip('Add to favourites'), findsNothing);
    expect(find.byTooltip('Remove from favourites'), findsNothing);
    expect(find.text('Add photo'), findsNothing);
    expect(find.text('Change photo'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('MY REVIEW / 我的評價'), findsNothing);
    expect(find.text('My secret notes'), findsNothing);
    expect(find.text('Add to board'), findsNothing);

    // Same id as the user's own Saved place -> already saved.
    expect(find.text('✓ In your places'), findsOneWidget);
    expect(find.text('Save to my places'), findsNothing);
  });

  testWidgets(
    "shows the owner's baked review only when the board includes it",
    (tester) async {
      final owners = _place(id: 'sbtest-2', score: 7, notes: "Owner's pick");

      await _pump(tester, sharedCopyOf(owners));
      expect(find.text('RATINGS / 評分'), findsOneWidget);
      expect(find.text("Owner's pick"), findsNothing);
      expect(find.text('No one else has rated this yet'), findsOneWidget);

      await _pump(tester, sharedCopyOf(owners, includeOwnerNotes: true));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('7/10'), findsOneWidget);
      expect(find.text("Owner's pick"), findsOneWidget);
      expect(find.text('No one else has rated this yet'), findsNothing);
    },
  );

  testWidgets('your rating is editable above; others are read-only below', (
    tester,
  ) async {
    final place = _place(id: 'sbtest-5', score: 4, notes: 'Baked, stale');
    repo.seed(_board, [place]);
    repo.seedRating(
      'sb',
      const PlaceRating(
        uid: 'alice',
        placeId: 'sbtest-5',
        displayName: 'Alice',
        score: 8,
        notes: 'Best broth in town',
      ),
    );
    repo.seedRating(
      'sb',
      const PlaceRating(
        uid: 'carol',
        placeId: 'sbtest-5',
        displayName: 'Carol',
        score: 6,
      ),
    );
    // A former member's rating lingers in Firestore — never shown.
    repo.seedRating(
      'sb',
      const PlaceRating(
        uid: 'mallory',
        placeId: 'sbtest-5',
        displayName: 'Mallory',
        score: 1,
      ),
    );
    // Re-bind inside the test's fake-async zone: setUp's subscriptions
    // deliver on real microtasks, which tester.pump() doesn't flush.
    SharedBoardStore.instance.bindRepository(repo, _bob);
    await tester.pump();
    expect(SharedBoardStore.instance.roleOn('sb'), BoardRole.viewer);
    await _pump(tester, sharedCopyOf(place, includeOwnerNotes: true));

    expect(find.text('Your rating'), findsOneWidget);
    expect(find.text('Tap to rate'), findsOneWidget);
    expect(find.text('Rate first to add a remark / 先評分再加備註'), findsOneWidget);
    // Alice rated for real, so her baked copy isn't duplicated.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('8/10'), findsOneWidget);
    expect(find.text('Best broth in town'), findsOneWidget);
    expect(find.text('Baked, stale'), findsNothing);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('6/10'), findsOneWidget);
    expect(find.text('Mallory'), findsNothing);
    expect(find.text('Avg 7 · 2 ratings'), findsOneWidget);
    // Others' ratings sit below yours.
    expect(
      tester.getTopLeft(find.text('Alice')).dy,
      greaterThan(tester.getTopLeft(find.byType(ScoreStars)).dy),
    );

    // Rate 9 (left half of the 5th star), then add a remark.
    await tester.ensureVisible(find.byType(ScoreStars));
    await tester.pumpAndSettle();
    final fifth = find.descendant(
      of: find.byType(ScoreStars),
      matching: find.byIcon(Icons.star_border),
    );
    final ninePoint = tester.getCenter(fifth.last) + const Offset(-10, 0);
    await tester.tapAt(ninePoint);
    await tester.pump();
    await tester.pump();
    expect(repo.ratings['sb']!['sbtest-5/bob']!.score, 9);
    expect(find.text('9/10'), findsOneWidget);
    expect(find.text('Avg 7.7 · 3 ratings'), findsOneWidget);

    await tester.ensureVisible(find.text('Add a remark… / 加備註'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a remark… / 加備註'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Worth the queue ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final mine = repo.ratings['sb']!['sbtest-5/bob']!;
    expect(mine.notes, 'Worth the queue');
    expect(mine.displayName, 'Bob');
    expect(find.text('Worth the queue'), findsOneWidget);

    // Clearing your stars (tapping the current half again) deletes it.
    await tester.ensureVisible(find.byType(ScoreStars));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.byIcon(Icons.star_half)) + const Offset(-10, 0),
    );
    await tester.pump();
    await tester.pump();
    expect(repo.ratings['sb']!.containsKey('sbtest-5/bob'), isFalse);
  });

  testWidgets('Save to my places adds a copy with a fresh id', (tester) async {
    final theirs = _place(id: 'sbtest-3', name: 'Somewhere else');
    await _pump(tester, theirs);

    expect(find.text('Save to my places'), findsOneWidget);
    await tester.tap(find.text('Save to my places'));
    await tester.pumpAndSettle();

    final added = PlaceStore.instance.places.value.where(
      (p) => p.name == 'Somewhere else',
    );
    expect(added, hasLength(1));
    expect(added.single.id, isNot('sbtest-3'));
    expect(added.single.id, startsWith('shared-'));
    expect(find.text('✓ In your places'), findsOneWidget);
  });

  testWidgets('restaurant sub-type chip is read-only and accessible', (
    tester,
  ) async {
    // Disposed before the test body returns (not via addTearDown): the
    // framework's own semantics-handle-leak check runs before package:test's
    // tearDowns fire, so a handle only released in addTearDown still trips it.
    final semantics = tester.ensureSemantics();
    final place = _place(
      id: 'sbtest-4',
    ).copyWith(category: PlaceCategory.restaurant);
    await _pump(tester, place);

    // No picker affordance...
    expect(find.byIcon(Icons.expand_more), findsNothing);
    // ...but still exposed to assistive tech, not just a bare emoji glyph
    // (merges into the section's semantics node, same as every other
    // non-container Text/Semantics in this sheet).
    expect(find.bySemanticsLabel(RegExp('Cuisine: ')), findsOneWidget);
    semantics.dispose();
  });
}
