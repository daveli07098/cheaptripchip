import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_filter_controller.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/screens/map_screen.dart';
import 'package:cheaptripchip/widgets/place_list_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

final _total = MockData.places.length;

Finder _inDrawer(Finder finder) =>
    find.descendant(of: find.byType(Drawer), matching: finder);

Future<void> _pumpMap(
  WidgetTester tester, {
  List<Place>? places,
  PlaceFilterController? filters,
}) async {
  PlaceStore.instance.places.value = places ?? List.of(MockData.places);
  BoardStore.instance.boards.value = const [];
  await tester.pumpWidget(
    MaterialApp(
      home: MapScreen(onAddFind: () {}, filters: filters),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('drawer: Favourites (top) filters to favourite places', (
    tester,
  ) async {
    final places = [
      for (final p in MockData.places)
        p.id == MockData.places[1].id ? p.copyWith(isFavorite: true) : p,
    ];
    await _pumpMap(tester, places: places);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(_inDrawer(find.text('Filters')), findsOneWidget);
    // Favourites is the first section, above Categories.
    expect(
      tester.getTopLeft(_inDrawer(find.text('Favourites').last)).dy,
      lessThan(tester.getTopLeft(_inDrawer(find.text('Categories'))).dy),
    );
    await tester.tap(_inDrawer(find.text('Favourites').last));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Favourites · 1'), findsOneWidget);
    expect(find.text('1 of $_total places'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.label == 'Clear favourites filter',
      ),
    );
    await tester.pump();
    expect(find.text('$_total of $_total places'), findsOneWidget);
  });

  testWidgets('with no favourites the row is disabled and explains why', (
    tester,
  ) async {
    await _pumpMap(tester);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(_inDrawer(find.text('Tap ♡ on a place to add it')), findsOneWidget);
    await tester.tap(_inDrawer(find.text('Favourites').last));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget, reason: 'nothing to pick');
  });

  testWidgets('"Clear all" shows from two filters and keeps the search', (
    tester,
  ) async {
    final filters = PlaceFilterController();
    addTearDown(filters.dispose);
    await _pumpMap(tester, filters: filters);

    filters.setCategory(PlaceCategory.restaurant);
    await tester.pump();
    expect(find.text('Clear all'), findsNothing);

    filters
      ..setArea('', null)
      ..search.text = 'a';
    await tester.pump();
    expect(find.text('Clear all'), findsOneWidget);
    // Two active filters badge the ☰ button.
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('2')),
      findsOneWidget,
    );

    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(filters.filter.hasActiveFilters, isFalse);
    expect(filters.filter.query, 'a');
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('chip ✕ hit area is at least 44dp', (tester) async {
    final filters = PlaceFilterController();
    addTearDown(filters.dispose);
    await _pumpMap(tester, filters: filters);
    filters.setCategory(PlaceCategory.restaurant);
    await tester.pump();
    final clear = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Clear category filter',
    );
    final size = tester.getSize(clear);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('searching with no matches says so in a SnackBar', (
    tester,
  ) async {
    await _pumpMap(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No places match “zzz”'), findsOneWidget);
  });

  testWidgets('the list header stays pinned and still drags the sheet', (
    tester,
  ) async {
    final places = [
      for (var i = 0; i < 40; i++)
        MockData.places.first.copyWith(
          id: 'many$i',
          name: 'Place $i',
          location: LatLng(35.6 + i * 0.001, 139.7),
        ),
    ];
    await _pumpMap(tester, places: places);
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    final extent = sheet.controller!;
    extent.jumpTo(kSheetFull);
    await tester.pumpAndSettle();

    // Scroll the rows well past the header.
    await tester.drag(find.text('Place 5'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Place 0').hitTestable(), findsNothing);
    expect(find.text('Add a find').hitTestable(), findsOneWidget);

    // Dragging down from the pinned header scrolls back, then shrinks.
    // A real finger sends many small moves (one big move would all go to
    // the list scroll).
    await tester.timedDrag(
      find.text('40 of 40 places'),
      const Offset(0, 700),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(extent.size, lessThan(kSheetFull - 0.05));
  });
}
