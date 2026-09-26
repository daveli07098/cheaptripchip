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

Future<List<String>> _menuLabels(WidgetTester tester) =>
    _popupLabels(tester, _inSharedCard(find.byTooltip('Board options')));

/// Labels of the ⋮ menu on the shared board's (only) place row.
Future<List<String>> _rowMenuLabels(WidgetTester tester) =>
    _popupLabels(tester, _inSharedCard(find.byTooltip('Place options')));

Future<List<String>> _popupLabels(WidgetTester tester, Finder button) async {
  await tester.tap(button);
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
      'Add places…',
      'Sharing info',
      'Send a copy',
      'Leave board',
    ]);
    expect(_inSharedCard(find.byType(Dismissible)), findsOneWidget);
    // Removal isn't swipe-only: the row's ⋮ offers it, next to saving a
    // copy (editors don't own the place).
    expect(await _rowMenuLabels(tester), [
      'Save to my places',
      'Remove from board',
    ]);
  });

  testWidgets('owner manages the board', (tester) async {
    await _pumpAs(tester, 'alice');

    expect(find.text('Shared · 3 people'), findsOneWidget);
    expect(await _menuLabels(tester), [
      'Add places…',
      'Sharing settings…',
      'Send a copy',
      'Rename',
      'Delete',
    ]);
    expect(_inSharedCard(find.byTooltip('Save to my places')), findsNothing);
    expect(await _rowMenuLabels(tester), ['Remove from board']);
  });

  testWidgets('board ⋮ groups View / Share / Manage with dividers, and '
      'says which share is live and which is a snapshot', (tester) async {
    await _pumpAs(tester, 'alice');

    await tester.tap(_inSharedCard(find.byTooltip('Board options')));
    await tester.pumpAndSettle();
    // Add places… | Sharing settings…, Send a copy | Rename, Delete.
    expect(find.byType(PopupMenuDivider), findsNWidgets(2));
    expect(find.text('Invite link, people & roles'), findsOneWidget);
    expect(find.text('One-time snapshot — link or file'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  });

  testWidgets('owner removes a place from the row ⋮, with UNDO', (
    tester,
  ) async {
    await _pumpAs(tester, 'alice');

    await tester.tap(_inSharedCard(find.byTooltip('Place options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from board'));
    await tester.pumpAndSettle();

    expect(SharedBoardStore.instance.placesOf('sb'), isEmpty);
    expect(find.text('Removed from $_boardName'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(SharedBoardStore.instance.placesOf('sb').keys, ['sp1']);
  });

  testWidgets('Rename needs a non-blank name, capped at 40 characters', (
    tester,
  ) async {
    final board = await BoardStore.instance.createBoard('Only mine');
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BoardsScreen())),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Only mine'),
          matching: find.byType(Card),
        ),
        matching: find.byTooltip('Board options'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    FilledButton save() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

    await tester.enterText(field, '   ');
    await tester.pump();
    expect(save().onPressed, isNull);
    // Submitting from the keyboard doesn't save a blank name either.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(field, '  ${'x' * 50}  ');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text.length, 40);

    await tester.enterText(field, '  Kyoto spring  ');
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(BoardStore.instance.byIdOrNull(board.id)!.name, 'Kyoto spring');
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

    // Guests need sign-in first; with no Firebase in this build (as in
    // tests) that's said up front instead of offering a sign-in that can't
    // work, and the board stays personal.
    await tester.tap(find.text('Share board…'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share'), findsNothing);
    expect(
      find.text(
        "Shared boards need sign-in, which isn't set up in this build.",
      ),
      findsOneWidget,
    );
    expect(BoardStore.instance.boards.value.first.name, 'Only mine');
    expect(SharedBoardStore.instance.boards.value, isEmpty);
  });
}
