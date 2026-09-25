import 'dart:ui' show Tristate;

import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/widgets/new_board_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const NewBoardDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
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

  testWidgets('Create is disabled until a name is entered, and trims it', (
    tester,
  ) async {
    await _openDialog(tester);

    var createButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create'),
    );
    expect(createButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), '  Osaka trip  ');
    await tester.pump();
    createButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create'),
    );
    expect(createButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    await tester.pump();

    final board = BoardStore.instance.boards.value.firstWhere(
      (b) => b.name == 'Osaka trip',
    );
    expect(board.name, 'Osaka trip'); // whitespace trimmed
  });

  testWidgets('selecting an emoji highlights it and is used on create', (
    tester,
  ) async {
    await _openDialog(tester);

    bool isSelected(String label) =>
        tester
            .getSemantics(find.bySemanticsLabel(label))
            .flagsCollection
            .isSelected ==
        Tristate.isTrue;

    // Default emoji (📌) starts selected.
    expect(isSelected('Pin'), isTrue);
    expect(isSelected('Noodles'), isFalse);

    await tester.tap(find.bySemanticsLabel('Noodles'));
    await tester.pump();

    expect(isSelected('Noodles'), isTrue);
    expect(isSelected('Pin'), isFalse);

    await tester.enterText(find.byType(TextField), 'Ramen tour');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    await tester.pump();

    final board = BoardStore.instance.boards.value.firstWhere(
      (b) => b.name == 'Ramen tour',
    );
    expect(board.emoji, '🍜');
  });

  testWidgets('showAndContinue creates the board, shows a SnackBar and opens '
      'AddPlacesSheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => NewBoardDialog.showAndContinue(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Kyoto trip');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump(); // dialog pop animation
    await tester.pump();
    await tester.pump(); // AddPlacesSheet route transition
    await tester.pump();

    expect(find.text('Created “Kyoto trip”'), findsOneWidget);
    expect(find.textContaining('Add places to “Kyoto trip”'), findsOneWidget);

    // Let the SnackBar's timer finish so no pending-timer failure at
    // teardown.
    await tester.pump(const Duration(seconds: 5));
  });
}
