// The shared empty state on Saved, Boards and the map's place list: same
// "three views of the same finds" copy, with each view's primary actions.
import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/guest_storage.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/screens/boards_screen.dart';
import 'package:cheaptripchip/screens/feed_screen.dart';
import 'package:cheaptripchip/widgets/empty_state_card.dart';
import 'package:cheaptripchip/widgets/place_list_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // An empty snapshot skips the mock seed: no places, no boards.
    PlaceStore.instance.bindRepository(
      LocalPlaceRepository(storage: MemorySnapshotStore('[]')),
    );
    BoardStore.instance.bindRepository(
      LocalBoardRepository(storage: MemorySnapshotStore('[]')),
    );
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('Saved: "Add a find" in the card (not a duplicate FAB)', (
    tester,
  ) async {
    var adds = 0;
    await tester.pumpWidget(
      MaterialApp(home: FeedScreen(onAddFind: () => adds++)),
    );
    await tester.pump();

    expect(find.byType(EmptyStateCard), findsOneWidget);
    expect(find.text('No finds yet'), findsOneWidget);
    expect(find.textContaining(kSameFindsExplainer), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Add a find'));
    expect(adds, 1);

    await tester.tap(find.text('How it works'));
    await tester.pumpAndSettle();
    expect(find.text('How cheaptripchip works'), findsOneWidget);
  });

  testWidgets('Boards: create, import and add actions', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BoardsScreen(
            onImportTripLink: () => calls.add('import'),
            onAddFind: () => calls.add('add'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(EmptyStateCard), findsOneWidget);
    expect(find.textContaining(kSameFindsExplainer), findsOneWidget);
    expect(find.text('Create your first board'), findsOneWidget);

    await tester.tap(find.text('Import a trip'));
    await tester.tap(find.text('Add a find'));
    expect(calls, ['import', 'add']);
  });

  Widget listSheet({required int total}) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          PlaceListSheet(
            places: const [],
            total: total,
            selectedId: ValueNotifier<String?>(null),
            onSelectPlace: (_) {},
            onOpenDetail: (_) {},
            onAddFind: () {},
          ),
        ],
      ),
    ),
  );

  testWidgets('map list: explains the views and offers "How it works"', (
    tester,
  ) async {
    await tester.pumpWidget(listSheet(total: 0));
    await tester.pump();

    expect(find.byType(EmptyStateCard), findsOneWidget);
    expect(find.text('No finds yet'), findsOneWidget);
    expect(find.textContaining(kSameFindsExplainer), findsOneWidget);
    // The header already has the one "Add a find" button.
    expect(find.text('Add a find'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
  });

  testWidgets('map list: filtered to nothing reads "No matches"', (
    tester,
  ) async {
    await tester.pumpWidget(listSheet(total: 3));
    await tester.pump();

    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('How it works'), findsNothing);
  });
}
