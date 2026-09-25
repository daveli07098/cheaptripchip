import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/widgets/add_places_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(int i, {String name = ''}) => Place(
  id: 'p$i',
  name: name.isEmpty ? 'Place number $i' : name,
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

Future<void> _open(WidgetTester tester, Board board) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => AddPlacesSheet.show(context, board),
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

  testWidgets('pre-checks places already on the board', (tester) async {
    final places = [_place(1), _place(2), _place(3)];
    await PlaceStore.instance.addAll(places);
    var board = await BoardStore.instance.createBoard('Trip');
    await BoardStore.instance.addPlaceToBoard(
      boardId: board.id,
      placeId: places[0].id,
    );
    board = BoardStore.instance.byIdOrNull(board.id)!;

    await _open(tester, board);

    final tile1 = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, places[0].name),
    );
    final tile2 = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, places[1].name),
    );
    expect(tile1.value, isTrue);
    expect(tile2.value, isFalse);
  });

  testWidgets('search narrows the list to matching places', (tester) async {
    final places = [
      _place(1, name: 'Ichiran Ramen'),
      _place(2, name: 'Blue Bottle Coffee'),
    ];
    await PlaceStore.instance.addAll(places);
    final board = await BoardStore.instance.createBoard('Trip');

    await _open(tester, board);

    expect(find.text('Ichiran Ramen'), findsOneWidget);
    expect(find.text('Blue Bottle Coffee'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ramen');
    await tester.pump();

    expect(find.text('Ichiran Ramen'), findsOneWidget);
    expect(find.text('Blue Bottle Coffee'), findsNothing);
  });

  testWidgets(
    'adding and removing places in one batch applies both to the store '
    'and shows a confirming SnackBar',
    (tester) async {
      final places = [_place(1), _place(2), _place(3)];
      await PlaceStore.instance.addAll(places);
      var board = await BoardStore.instance.createBoard('Trip');
      // p1 starts on the board; p2 and p3 don't.
      await BoardStore.instance.addPlaceToBoard(
        boardId: board.id,
        placeId: places[0].id,
      );
      board = BoardStore.instance.byIdOrNull(board.id)!;

      await _open(tester, board);

      // Uncheck the pre-checked place (removal) and check the two others
      // (additions) — all in one batch before hitting the button.
      await tester.tap(find.widgetWithText(CheckboxListTile, places[0].name));
      await tester.tap(find.widgetWithText(CheckboxListTile, places[1].name));
      await tester.tap(find.widgetWithText(CheckboxListTile, places[2].name));
      await tester.pump();

      expect(find.text('Save changes'), findsOneWidget);

      await tester.tap(find.text('Save changes'));
      await tester.pump(); // flush the updateBoardPlaces microtask hop
      await tester.pump();

      expect(
        BoardStore.instance.containsPlace(board.id, places[0].id),
        isFalse,
      );
      expect(BoardStore.instance.containsPlace(board.id, places[1].id), isTrue);
      expect(BoardStore.instance.containsPlace(board.id, places[2].id), isTrue);
      expect(find.text('Added 2 places to “Trip”'), findsOneWidget);

      // Let the SnackBar's timer finish so no pending-timer failure at
      // teardown.
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
