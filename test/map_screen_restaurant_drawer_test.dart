import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/screens/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('drawer expands Restaurant to filter by cuisine sub-type', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: MapScreen(onAddFind: () {})));
    await tester.pump();

    final total = PlaceStore.instance.places.value.length;
    expect(find.text('$total of $total places'), findsOneWidget);

    // Open the category drawer.
    await tester.tap(find.byTooltip('Categories'));
    await tester.pumpAndSettle();

    // Mock data has exactly one restaurant (Gogo, auto-detected as ramen
    // from its descriptionEn — no explicit tag) — the Restaurant row
    // should offer a "Show cuisines" expand affordance.
    expect(find.text('Restaurant'), findsOneWidget);
    expect(find.byTooltip('Show cuisines'), findsOneWidget);
    expect(find.text('Ramen'), findsNothing);

    await tester.tap(find.byTooltip('Show cuisines'));
    await tester.pumpAndSettle();
    expect(find.text('Ramen'), findsOneWidget);

    await tester.tap(find.text('Ramen'));
    await tester.pumpAndSettle();

    // Drawer closed, filter applied: the active-category chip shows the
    // sub-type, and the list sheet narrows to just that one place.
    expect(find.text('Ramen · 1'), findsOneWidget);
    expect(find.text('1 of $total places'), findsOneWidget);

    // Clearing the chip drops both the category and the sub-type filter.
    await tester.tap(find.widgetWithIcon(InkWell, Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('$total of $total places'), findsOneWidget);
    expect(find.text('Ramen · 1'), findsNothing);
  });

  testWidgets(
    'tapping the Restaurant row itself (not a sub-type) filters to all restaurants',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: MapScreen(onAddFind: () {})));
      await tester.pump();
      final total = PlaceStore.instance.places.value.length;

      await tester.tap(find.byTooltip('Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restaurant'));
      await tester.pumpAndSettle();

      // No sub-type selected — the chip shows the bare category.
      expect(find.text('Restaurant · 1'), findsOneWidget);
      expect(find.text('1 of $total places'), findsOneWidget);
    },
  );
}
