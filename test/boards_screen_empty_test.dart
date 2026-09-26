// The Boards tab with nothing at all to show: "Create your first board"
// plus "Import a trip", which reuses the shell's import entries.
import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/guest_storage.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/screens/boards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, BoardsScreen screen) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  await tester.pump();
}

void main() {
  setUp(() async {
    // An empty snapshot skips the mock seed: no places, no boards.
    PlaceStore.instance.bindRepository(
      LocalPlaceRepository(storage: MemorySnapshotStore('[]')),
    );
    BoardStore.instance.bindRepository(
      LocalBoardRepository(storage: MemorySnapshotStore('[]')),
    );
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('no import callbacks: only "Create your first board"', (
    tester,
  ) async {
    await _pump(tester, const BoardsScreen());

    expect(find.text('No boards yet'), findsOneWidget);
    expect(find.text('Create your first board'), findsOneWidget);
    expect(find.text('Import a trip'), findsNothing);
  });

  testWidgets('"Import a trip" offers both import sources', (tester) async {
    final calls = <String>[];
    await _pump(
      tester,
      BoardsScreen(
        onImportTripLink: () => calls.add('link'),
        onImportMyMaps: () => calls.add('myMaps'),
      ),
    );

    await tester.tap(find.text('Import a trip'));
    await tester.pumpAndSettle();
    expect(find.text('From a shared trip link'), findsOneWidget);
    await tester.tap(find.text('From Google My Maps'));
    await tester.pumpAndSettle();

    expect(calls, ['myMaps']);
    expect(find.text('From a shared trip link'), findsNothing);
  });

  testWidgets('with one source, "Import a trip" runs it directly', (
    tester,
  ) async {
    var calls = 0;
    await _pump(tester, BoardsScreen(onImportTripLink: () => calls++));

    await tester.tap(find.text('Import a trip'));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('a lone board starts expanded', (tester) async {
    await BoardStore.instance.createBoard('Solo');
    await _pump(tester, const BoardsScreen());

    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect(tile.initiallyExpanded, isTrue);
    // Let the guest snapshot's debounced write fire before teardown.
    await tester.pump(const Duration(seconds: 1));
  });
}
