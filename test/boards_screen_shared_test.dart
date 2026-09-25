import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/data/shared_board_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/shared_board.dart';
import 'package:cheaptripchip/screens/boards_screen.dart';
import 'package:cheaptripchip/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes/fake_shared_board_repository.dart';

const _boardName = 'Shared Osaka trip';

final _place = Place(
  id: 'sp1',
  name: 'Shared takoyaki',
  areaLabel: 'Namba',
  region: 'Osaka',
  category: PlaceCategory.food,
  location: const LatLng(34.66, 135.5),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
);

SharedBoard _board() => SharedBoard(
  id: 'sb',
  ownerId: 'alice',
  ownerName: 'Alice',
  name: _boardName,
  emoji: '🐙',
  sections: const [
    BoardSection(title: 'Food', placeIds: ['sp1']),
  ],
  members: const {
    'alice': BoardRole.owner,
    'eddie': BoardRole.editor,
    'vera': BoardRole.viewer,
  },
  memberNames: const {'alice': 'Alice', 'eddie': 'Eddie', 'vera': 'Vera'},
  linkRole: BoardRole.viewer,
  inviteCode: 'abcdefghijklmnopqrstuvwx',
);

Finder _inSharedCard(Finder finder) => find.descendant(
  of: find.ancestor(of: find.text(_boardName), matching: find.byType(Card)),
  matching: finder,
);

Future<void> _pumpAs(WidgetTester tester, String uid) async {
  final repo = FakeSharedBoardRepository()..seed(_board(), [_place]);
  SharedBoardStore.instance.bindRepository(repo, AppUser(uid: uid));
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: BoardsScreen())),
  );
  await tester.pump();
  // Expand the shared board.
  await tester.tap(find.text(_boardName));
  await tester.pumpAndSettle();
}

Future<List<String>> _menuLabels(WidgetTester tester) async {
  await tester.tap(_inSharedCard(find.byTooltip('Board options')));
  await tester.pumpAndSettle();
  final labels = [
    for (final item in tester.widgetList<PopupMenuItem<Object>>(
      find.byWidgetPredicate((w) => w is PopupMenuItem),
    ))
      ((item.child! as ListTile).title! as Text).data!,
  ];
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
  return labels;
}

void main() {
  setUp(() {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
  });

  tearDown(() => SharedBoardStore.instance.bind(null));

  testWidgets('viewer sees no edit actions', (tester) async {
    await _pumpAs(tester, 'vera');

    expect(find.text('Shared by Alice · View only'), findsOneWidget);
    expect(await _menuLabels(tester), [
      'Sharing info',
      'Send a copy',
      'Leave board',
    ]);
    // Rows are not swipe-to-remove, but can be saved as copies.
    expect(_inSharedCard(find.byType(Dismissible)), findsNothing);
    expect(_inSharedCard(find.byTooltip('Save to my places')), findsOneWidget);
  });

  testWidgets('editor can add and remove places but not manage', (
    tester,
  ) async {
    await _pumpAs(tester, 'eddie');

    expect(find.text('Shared by Alice · Can edit'), findsOneWidget);
    expect(await _menuLabels(tester), [
      'Sharing info',
      'Send a copy',
      'Add places…',
      'Leave board',
    ]);
    expect(_inSharedCard(find.byType(Dismissible)), findsOneWidget);
  });

  testWidgets('owner manages the board', (tester) async {
    await _pumpAs(tester, 'alice');

    expect(find.text('Shared · 3 people'), findsOneWidget);
    expect(await _menuLabels(tester), [
      'Sharing settings…',
      'Send a copy',
      'Add places…',
      'Rename',
      'Delete',
    ]);
    expect(_inSharedCard(find.byTooltip('Save to my places')), findsNothing);
  });

  testWidgets('personal boards offer Share board… and Send a copy', (
    tester,
  ) async {
    await BoardStore.instance.createBoard('Only mine');
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BoardsScreen())),
    );
    await tester.pump();
    final card = find.ancestor(
      of: find.text('Only mine'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Board options')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Share board…'), findsOneWidget);
    expect(find.text('Send a copy'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);

    // Guests are asked to sign in instead of sharing.
    await tester.tap(find.text('Share board…'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(BoardStore.instance.boards.value.first.name, 'Only mine');
  });
}
