import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/widgets/board_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(int i) => Place(
  id: 'p$i',
  name: 'Place number $i',
  areaLabel: 'Area $i',
  region: 'Tokyo, Japan',
  category: PlaceCategory.food,
  location: LatLng(35 + i / 1000, 139 + i / 1000),
  descriptionEn: '',
  originalCaption: '',
  address: 'Address $i',
  hours: '',
  sourceHandle: '@handle$i',
  sourcePlatform: SourcePlatform.tiktok,
);

Future<void> _open(WidgetTester tester, Place place) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => BoardPickerSheet.show(context, place),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Bounded rather than the default 10-minute pumpAndSettle timeout, so a
  // genuine hang fails fast with a readable error instead of burning the
  // whole suite's time budget.
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

void main() {
  setUp(() async {
    // Bind fresh in-memory repositories per test and let their initial
    // replay settle before the test body runs any mutations (same reasoning
    // as board_store_test.dart).
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('shows a checked box for a board already containing the '
      'place, unchecked for one that does not', (tester) async {
    final place = _place(1);
    final boardA = await BoardStore.instance.createBoard('Board A');
    final boardB = await BoardStore.instance.createBoard('Board B');
    await BoardStore.instance.addPlaceToBoard(
      boardId: boardA.id,
      placeId: place.id,
    );

    await _open(tester, place);

    final tileA = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, boardA.name),
    );
    final tileB = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, boardB.name),
    );
    expect(tileA.value, isTrue);
    expect(tileB.value, isFalse);
  });

  testWidgets('tapping an unchecked board adds the place and shows a '
      'SnackBar; sheet stays open', (tester) async {
    final place = _place(2);
    final board = await BoardStore.instance.createBoard('Trip board');

    await _open(tester, place);

    await tester.tap(find.widgetWithText(CheckboxListTile, board.name));
    await tester.pump(); // flush the addPlaceToBoard microtask hop
    await tester.pump();

    expect(BoardStore.instance.containsPlace(board.id, place.id), isTrue);
    expect(find.text('Added to Trip board'), findsOneWidget);
    // The picker sheet (its "Add to board" title) is still showing.
    expect(find.text('Add to board'), findsOneWidget);

    // Let the SnackBar's timer finish so no pending-timer failure at
    // teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tapping a checked board removes the place and shows a '
      'SnackBar', (tester) async {
    final place = _place(3);
    final board = await BoardStore.instance.createBoard('Trip board');
    await BoardStore.instance.addPlaceToBoard(
      boardId: board.id,
      placeId: place.id,
    );

    await _open(tester, place);

    await tester.tap(find.widgetWithText(CheckboxListTile, board.name));
    await tester.pump();
    await tester.pump();

    expect(BoardStore.instance.containsPlace(board.id, place.id), isFalse);
    expect(find.text('Removed from Trip board'), findsOneWidget);
    expect(find.text('UNDO'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('"New board…" creates a board with the place already added '
      'and checked', (tester) async {
    final place = _place(4);
    await _open(tester, place);

    await tester.tap(find.text('New board…'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Osaka trip');
    await tester.tap(find.text('Create'));
    await tester.pump();
    await tester.pump();

    final board = BoardStore.instance.boards.value.firstWhere(
      (b) => b.name == 'Osaka trip',
    );
    expect(BoardStore.instance.containsPlace(board.id, place.id), isTrue);
    final tile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, board.name),
    );
    expect(tile.value, isTrue);
    expect(find.text('Add to board'), findsOneWidget); // sheet still open

    await tester.pump(const Duration(seconds: 5));
  });

  test('addToBoardLabel: none / one / many', () {
    const boardA = Board(id: 'a', name: 'Trip A', emoji: '📌', sections: []);
    const boardB = Board(id: 'b', name: 'Trip B', emoji: '📌', sections: []);
    expect(addToBoardLabel(const []), 'Add to board');
    expect(addToBoardLabel(const [boardA]), 'In Trip A');
    expect(addToBoardLabel(const [boardA, boardB]), 'In 2 boards');
  });
}
