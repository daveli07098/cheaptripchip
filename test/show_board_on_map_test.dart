import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/screens/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guest repositories seed MockData: "Tokyo Trip 2026" holds all six
/// places, "Coffee & Quiet" two of them.
void main() {
  setUp(() async {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    await Future<void>.delayed(Duration.zero);
  });

  final total = MockData.places.length;

  int selectedTab(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  Future<void> openBoards(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(NavigationDestination, 'Boards'));
    await tester.pumpAndSettle();
  }

  Finder inCard(String board, Finder finder) =>
      find.descendant(of: find.widgetWithText(Card, board), matching: finder);

  testWidgets('"Show on map" switches to the map with only that board, '
      'replacing the search', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'no such place');
    await tester.pumpAndSettle();
    expect(find.text('0 of $total places'), findsOneWidget);

    // With several boards every card starts collapsed, so this one is in
    // view.
    await openBoards(tester);
    await tester.tap(inCard('Coffee & Quiet', find.byTooltip('Show on map')));
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 0);
    expect(find.text('Coffee & Quiet · 2'), findsOneWidget);
    expect(find.text('2 of $total places'), findsOneWidget);
  });

  testWidgets('the ⋮ menu item does the same; an empty board says so', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    await openBoards(tester);

    await tester.tap(
      inCard('Tokyo Trip 2026', find.byTooltip('Board options')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show on map').last);
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 0);
    expect(find.text('Tokyo Trip 2026 · $total'), findsOneWidget);
    expect(find.text('$total of $total places'), findsOneWidget);

    await BoardStore.instance.createBoard('Empty plans');
    await openBoards(tester);
    await tester.tap(inCard('Empty plans', find.byTooltip('Show on map')));
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 0);
    expect(
      find.text('None of “Empty plans”’s places are on your map'),
      findsOneWidget,
    );
  });

  testWidgets('a one-place board flies the camera close to that place', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    MapCamera camera() => tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!
        .camera;
    final startZoom = camera().zoom;

    final solo = MockData.places.last;
    await BoardStore.instance.createBoard(
      'Solo',
      sections: [
        BoardSection(title: 'Stay', placeIds: [solo.id]),
      ],
    );
    await openBoards(tester);
    await tester.tap(inCard('Solo', find.byTooltip('Show on map')));
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 0);
    expect(find.text('1 of $total places'), findsOneWidget);
    expect(camera().zoom, greaterThan(startZoom + 1));
    expect(camera().visibleBounds.contains(solo.location), isTrue);
    expect(camera().center.latitude.isFinite, isTrue);
  });
}
