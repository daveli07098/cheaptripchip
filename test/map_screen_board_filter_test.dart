import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/screens/map_screen.dart';
import 'package:cheaptripchip/widgets/map_pin.dart';
import 'package:cheaptripchip/widgets/place_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock places p1–p6; "Tokyo trip" holds p1+p3, "Coffee" p3+p4, so p2, p5
/// and p6 fall into the auto "New finds" board.
const _boards = [
  Board(
    id: 'b1',
    name: 'Tokyo trip',
    emoji: '🗼',
    sections: [
      BoardSection(title: 'Food', placeIds: ['p1', 'p3']),
    ],
  ),
  Board(
    id: 'b2',
    name: 'Coffee',
    emoji: '☕',
    sections: [
      BoardSection(title: 'Cafés', placeIds: ['p3', 'p4']),
    ],
  ),
];

final _total = MockData.places.length;

Finder _inDrawer(Finder finder) =>
    find.descendant(of: find.byType(Drawer), matching: finder);

Future<void> _pumpMap(WidgetTester tester) async {
  PlaceStore.instance.places.value = List.of(MockData.places);
  BoardStore.instance.boards.value = List.of(_boards);
  await tester.pumpWidget(MaterialApp(home: MapScreen(onAddFind: () {})));
  await tester.pump();
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Filters'));
  await tester.pumpAndSettle();
}

/// Drawer rows below the fold aren't built until scrolled to.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    _inDrawer(target),
    100,
    scrollable: _inDrawer(find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Boards section: multi-select ORs boards, keeps the drawer '
      'open, chips clear one board each', (tester) async {
    await _pumpMap(tester);
    await _openDrawer(tester);

    // Favourites + Categories come first; Boards sits below the fold.
    await _scrollTo(tester, find.text('Boards'));
    expect(_inDrawer(find.text('Boards')), findsOneWidget);
    expect(_inDrawer(find.text('New finds')), findsOneWidget);
    await _scrollTo(tester, find.text('Coffee'));
    await tester.tap(_inDrawer(find.text('Tokyo trip')));
    await tester.pumpAndSettle();
    // Still open, row now checked.
    expect(find.byType(Drawer), findsOneWidget);
    expect(
      tester.getSemantics(_inDrawer(find.text('Tokyo trip'))),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    await tester.tap(_inDrawer(find.text('Coffee')));
    await tester.pumpAndSettle();

    // Close the drawer.
    await tester.tapAt(const Offset(390, 300));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Tokyo trip · 2'), findsOneWidget);
    expect(find.text('Coffee · 2'), findsOneWidget);
    expect(find.text('3 of $_total places'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Clear board filter Tokyo trip',
        ),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tokyo trip · 2'), findsNothing);
    expect(find.text('2 of $_total places'), findsOneWidget);
  });

  testWidgets('board filter ANDs with the category filter', (tester) async {
    await _pumpMap(tester);
    await _openDrawer(tester);
    await _scrollTo(tester, find.text('New finds'));
    await tester.tap(_inDrawer(find.text('New finds')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(390, 300));
    await tester.pumpAndSettle();
    final newFinds = find.text('${_total - 3} of $_total places');
    expect(newFinds, findsOneWidget);

    final p2 = MockData.places.firstWhere((p) => p.id == 'p2');
    await _openDrawer(tester);
    await tester.tap(_inDrawer(find.text(p2.category.labelEn)).first);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    final expected = MockData.places
        .where(
          (p) => {'p2', 'p5', 'p6'}.contains(p.id) && p.category == p2.category,
        )
        .length;
    expect(find.text('$expected of $_total places'), findsOneWidget);
  });

  testWidgets('the Boards section collapses', (tester) async {
    await _pumpMap(tester);
    await _openDrawer(tester);
    await _scrollTo(tester, find.text('All boards'));
    await tester.drag(
      _inDrawer(find.byType(Scrollable)).first,
      const Offset(0, 150),
    );
    await tester.pumpAndSettle();
    await tester.tap(_inDrawer(find.text('Boards')));
    await tester.pumpAndSettle();
    expect(_inDrawer(find.text('All boards')), findsNothing);
    expect(_inDrawer(find.text('New finds')), findsNothing);
    expect(
      tester.getSemantics(_inDrawer(find.text('Boards'))),
      isSemantics(hasExpandedState: true, isExpanded: false),
    );
  });

  testWidgets('the preview card names the tapped place\'s boards', (
    tester,
  ) async {
    await _pumpMap(tester);
    final pin = find.byWidgetPredicate(
      (w) => w is MapPin && w.place.id == 'p3',
    );
    await tester.tap(pin, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PlacePreviewCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PlacePreviewCard),
        matching: find.text('Tokyo trip · Coffee'),
      ),
      findsOneWidget,
    );
  });
}
