import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/screens/home_shell.dart';
import 'package:cheaptripchip/widgets/place_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Saved tab and the map share one filter + search (owned by the home
/// shell): whatever is set on one tab applies on the other.
void main() {
  setUp(() async {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    await Future<void>.delayed(Duration.zero);
  });

  final total = MockData.places.length;
  final restaurants = MockData.places
      .where((p) => p.category == PlaceCategory.restaurant)
      .length;

  Finder inDrawer(Finder finder) =>
      find.descendant(of: find.byType(Drawer), matching: finder);

  /// Cards in the Saved list — including ones not built yet (lazy list).
  int savedCount(WidgetTester tester) {
    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(ListView),
      ),
    );
    final items = list.childrenDelegate.estimatedChildCount ?? 0;
    return (items + 1) ~/ 2; // ListView.separated: n cards, n - 1 gaps.
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(NavigationDestination, label));
    await tester.pumpAndSettle();
  }

  testWidgets('a category picked on the map filters Saved, with its chip', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(inDrawer(find.text('Restaurant')));
    await tester.pumpAndSettle();
    expect(find.text('Restaurant · $restaurants'), findsOneWidget);

    await openTab(tester, 'Saved');
    expect(find.text('Restaurant · $restaurants'), findsOneWidget);
    expect(savedCount(tester), restaurants);

    // Clearing the chip on Saved clears it on the map too.
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Clear category filter',
      ),
    );
    await tester.pumpAndSettle();
    await openTab(tester, 'Explore');
    expect(find.text('Restaurant · $restaurants'), findsNothing);
    expect(find.text('$total of $total places'), findsOneWidget);
  });

  testWidgets('search and drawer on Saved apply on the map', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Saved');
    expect(savedCount(tester), total);

    // Honest hint: it searches saved places only.
    expect(find.text('Search saved places'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Gogo');
    await tester.pumpAndSettle();
    expect(find.byType(PlaceCard), findsOneWidget);

    // The same Filters drawer opens from the Saved pill.
    expect(
      find.widgetWithText(FloatingActionButton, 'Add a find').hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(inDrawer(find.text('Categories')), findsOneWidget);
    // The drawer's scrim covers the Saved tab's FAB.
    expect(
      find.widgetWithText(FloatingActionButton, 'Add a find').hitTestable(),
      findsNothing,
    );
    await tester.tap(inDrawer(find.text('All')).first);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);

    await openTab(tester, 'Explore');
    expect(find.text('1 of $total places'), findsOneWidget);
    // The map's pill shows the same query, with its clear ✕.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('$total of $total places'), findsOneWidget);
    await openTab(tester, 'Saved');
    expect(savedCount(tester), total);
  });
}
