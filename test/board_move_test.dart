// Widget tests for moving a place between personal boards: the row's ⋮
// "Move to board…" (picker in move mode, "Current" source, one store move,
// "Moved to …" + UNDO), the place page's "Move to another board" action,
// and board cards keeping their expanded state when the list shifts.
import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/screens/boards_screen.dart';
import 'package:cheaptripchip/screens/place_detail_sheet.dart';
import 'package:cheaptripchip/widgets/board_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _p1 = MockData.placeById('p1');
final _p2 = MockData.placeById('p2');
final _p5 = MockData.placeById('p5');

Finder _card(String boardName) =>
    find.ancestor(of: find.text(boardName), matching: find.byType(Card));

Finder _inCard(String boardName, Finder finder) =>
    find.descendant(of: _card(boardName), matching: finder);

Finder _inPicker(Finder finder) =>
    find.descendant(of: find.byType(BoardPickerSheet), matching: finder);

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 50),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

Future<void> _pumpBoards(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: BoardsScreen())),
  );
  await tester.pump();
}

/// Opens the ⋮ menu on [placeName]'s row inside [boardName]'s card.
Future<void> _rowMenu(
  WidgetTester tester,
  String boardName,
  String placeName,
) async {
  final row = _inCard(
    boardName,
    find.ancestor(of: find.text(placeName), matching: find.byType(ListTile)),
  );
  await tester.tap(
    find.descendant(of: row.first, matching: find.byTooltip('Place options')),
  );
  await _settle(tester);
}

void main() {
  late Board osaka;
  late Board kyoto;

  setUp(() async {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    await Future<void>.delayed(Duration.zero);
    // Drop the seeded boards so only these two render (and nothing is
    // expanded by default).
    await BoardStore.instance.deleteBoard('b1');
    await BoardStore.instance.deleteBoard('b2');
    kyoto = await BoardStore.instance.createBoard('Kyoto');
    osaka = await BoardStore.instance.createBoard(
      'Osaka',
      sections: [
        BoardSection(title: _p1.category.labelEn, placeIds: [_p1.id]),
        BoardSection(title: _p2.category.labelEn, placeIds: [_p2.id]),
      ],
    );
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('row ⋮ → Move to board… moves the place in one step, keeps '
      'the source card expanded, and UNDO puts it back', (tester) async {
    await _pumpBoards(tester);
    await tester.tap(find.text('Osaka'));
    await _settle(tester);

    await _rowMenu(tester, 'Osaka', _p1.name);
    await tester.tap(find.text('Move to board…'));
    await _settle(tester);

    // Move-mode picker: the source is tagged Current and can't be picked.
    expect(_inPicker(find.text('Move to board')), findsOneWidget);
    final current = tester.widget<ListTile>(
      _inPicker(
        find.ancestor(
          of: find.text('Current'),
          matching: find.byType(ListTile),
        ),
      ),
    );
    expect((current.title! as Text).data, 'Osaka');
    expect(current.enabled, isFalse);

    await tester.tap(_inPicker(find.text('Kyoto')));
    await _settle(tester);

    expect(find.byType(BoardPickerSheet), findsNothing);
    expect(BoardStore.instance.containsPlace(osaka.id, _p1.id), isFalse);
    expect(BoardStore.instance.containsPlace(kyoto.id, _p1.id), isTrue);
    expect(find.text('Moved to Kyoto'), findsOneWidget);
    // Source card is still open: its other place is still listed.
    expect(_inCard('Osaka', find.text(_p2.name)), findsOneWidget);
    expect(_inCard('Osaka', find.text(_p1.name)), findsNothing);

    await tester.tap(find.text('UNDO'));
    await _settle(tester);

    expect(BoardStore.instance.containsPlace(kyoto.id, _p1.id), isFalse);
    final restored = BoardStore.instance.byIdOrNull(osaka.id)!;
    expect(restored.sections.map((s) => s.placeIds).toList(), [
      [_p1.id],
      [_p2.id],
    ]);
    expect(_inCard('Osaka', find.text(_p1.name)), findsOneWidget);

    // Let the SnackBar's timer finish so no pending-timer failure at
    // teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('dismissing the move picker changes nothing', (tester) async {
    await _pumpBoards(tester);
    await tester.tap(find.text('Osaka'));
    await _settle(tester);

    await _rowMenu(tester, 'Osaka', _p1.name);
    await tester.tap(find.text('Move to board…'));
    await _settle(tester);
    await tester.tap(_inPicker(find.text('Cancel')));
    await _settle(tester);

    expect(BoardStore.instance.containsPlace(osaka.id, _p1.id), isTrue);
    expect(BoardStore.instance.containsPlace(kyoto.id, _p1.id), isFalse);
    expect(find.text('Moved to Kyoto'), findsNothing);
  });

  testWidgets('a board card stays expanded when "New finds" appears above '
      'it', (tester) async {
    // Every place is on a board, so there is no "New finds" card yet.
    await BoardStore.instance.updateBoardPlaces(
      boardId: osaka.id,
      add: {for (final p in MockData.places) p.id},
      remove: const {},
    );
    await _pumpBoards(tester);
    expect(find.text('New finds'), findsNothing);
    await tester.tap(find.text('Osaka'));
    await _settle(tester);

    // Removing p5 leaves it on no board: "New finds" is inserted at the top.
    await _rowMenu(tester, 'Osaka', _p5.name);
    await tester.tap(find.text('Remove from board'));
    await _settle(tester);

    expect(find.text('New finds'), findsOneWidget);
    expect(_inCard('Osaka', find.text(_p1.name)), findsOneWidget);
    expect(find.text('Removed from Osaka'), findsOneWidget);

    // UNDO puts p5 back in its original section and position, in one go.
    final before = BoardStore.instance.byIdOrNull(osaka.id)!;
    expect(before.sections.expand((s) => s.placeIds), isNot(contains(_p5.id)));
    await tester.tap(find.text('UNDO'));
    await _settle(tester);
    expect(find.text('New finds'), findsNothing);
    final restored = BoardStore.instance.byIdOrNull(osaka.id)!;
    final nightlife = restored.sections.indexWhere(
      (s) => s.placeIds.contains(_p5.id),
    );
    expect(restored.sections[nightlife].title, _p5.category.labelEn);
    expect(nightlife, isNot(restored.sections.length - 1));
    expect(_inCard('Osaka', find.text(_p1.name)), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('place page opened from a board offers Move to another board', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceDetailSheet(
            place: _p1,
            source: PlaceDetailSource.personalBoard(osaka.id),
          ),
        ),
      ),
    );
    await tester.pump();

    final move = find.byTooltip('Move to another board');
    await tester.ensureVisible(move);
    await tester.tap(move);
    await _settle(tester);
    await tester.tap(_inPicker(find.text('Kyoto')));
    await _settle(tester);

    expect(BoardStore.instance.containsPlace(osaka.id, _p1.id), isFalse);
    expect(BoardStore.instance.containsPlace(kyoto.id, _p1.id), isTrue);
    expect(find.text('Moved to Kyoto'), findsOneWidget);
    expect(find.text('In Kyoto'), findsOneWidget);
    // No longer on the source board, so no further move from it.
    expect(find.byTooltip('Move to another board'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the plain place page has no move action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlaceDetailSheet(place: _p1)),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Move to another board'), findsNothing);
  });
}
