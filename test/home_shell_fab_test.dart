import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/screens/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    // Bind fresh in-memory repositories per test and let their initial
    // replay settle before the test body runs any mutations (same reasoning
    // as board_store_test.dart).
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets(
    'Boards tab shows a "New board" FAB; Saved tab keeps "Add a find"',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pumpAndSettle();

      // Saved tab (index 1): unchanged "Add a find" FAB.
      await tester.tap(find.widgetWithText(NavigationDestination, 'Saved'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FloatingActionButton, 'Add a find'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FloatingActionButton, 'New board'),
        findsNothing,
      );

      // Boards tab (index 2): "New board" FAB, not "Add a find".
      await tester.tap(find.widgetWithText(NavigationDestination, 'Boards'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FloatingActionButton, 'New board'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FloatingActionButton, 'Add a find'),
        findsNothing,
      );

      // Explore tab (index 0): no FAB at all (map has its own).
      await tester.tap(find.widgetWithText(NavigationDestination, 'Explore'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
    },
  );
}
