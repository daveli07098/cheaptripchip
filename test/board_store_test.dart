import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardStore', () {
    setUp(() async {
      // Bind fresh in-memory repositories per test and let their initial
      // replay settle before the test body runs any mutations (same
      // reasoning as place_store_test.dart).
      PlaceStore.instance.bindRepository(LocalPlaceRepository());
      BoardStore.instance.bindRepository(LocalBoardRepository());
      await Future<void>.delayed(Duration.zero);
    });

    test('createBoard adds the new board to boards', () async {
      final store = BoardStore.instance;
      final beforeCount = store.boards.value.length;

      final board = await store.createBoard('My Trip', emoji: '🧳');
      // Optimistic update lands synchronously, but let the repository's
      // stream catch up too before asserting, so the two stay consistent.
      await Future<void>.delayed(Duration.zero);

      expect(store.boards.value.length, beforeCount + 1);
      expect(store.boards.value.first.id, board.id);
      expect(store.boards.value.first.name, 'My Trip');
      expect(board.id, startsWith('board-'));
    });

    test('addPlaceToBoard creates a section titled by the category; '
        'second add is a no-op', () async {
      final store = BoardStore.instance;
      final board = await store.createBoard('New Board');
      await Future<void>.delayed(Duration.zero);
      final place = MockData.places.first;

      await store.addPlaceToBoard(boardId: board.id, placeId: place.id);
      await Future<void>.delayed(Duration.zero);

      final afterFirstAdd = store.boards.value.firstWhere(
        (b) => b.id == board.id,
      );
      expect(afterFirstAdd.sections, hasLength(1));
      expect(afterFirstAdd.sections.first.title, place.category.labelEn);
      expect(afterFirstAdd.sections.first.placeIds, [place.id]);

      // Adding the same place to the same (default) section again is a no-op.
      await store.addPlaceToBoard(boardId: board.id, placeId: place.id);
      await Future<void>.delayed(Duration.zero);

      final afterSecondAdd = store.boards.value.firstWhere(
        (b) => b.id == board.id,
      );
      expect(afterSecondAdd.sections, hasLength(1));
      expect(afterSecondAdd.sections.first.placeIds, [place.id]);
    });

    test(
      'addPlaceToBoard with an explicit sectionTitle targets that section',
      () async {
        final store = BoardStore.instance;
        final board = await store.createBoard('New Board');
        await Future<void>.delayed(Duration.zero);
        final place = MockData.places[1];

        await store.addPlaceToBoard(
          boardId: board.id,
          placeId: place.id,
          sectionTitle: 'Custom Section',
        );
        await Future<void>.delayed(Duration.zero);

        final updated = store.boards.value.firstWhere((b) => b.id == board.id);
        expect(updated.sections, hasLength(1));
        expect(updated.sections.first.title, 'Custom Section');
        expect(updated.sections.first.placeIds, [place.id]);
      },
    );

    test('renameBoard trims the name; ignores a blank name', () async {
      final store = BoardStore.instance;
      final board = await store.createBoard('  Old Name  '.trim());
      await Future<void>.delayed(Duration.zero);

      await store.renameBoard(board.id, '  New Name  ');
      await Future<void>.delayed(Duration.zero);
      expect(
        store.boards.value.firstWhere((b) => b.id == board.id).name,
        'New Name',
      );

      await store.renameBoard(board.id, '   ');
      await Future<void>.delayed(Duration.zero);
      expect(
        store.boards.value.firstWhere((b) => b.id == board.id).name,
        'New Name',
      );
    });

    test('deleteBoard removes the board and returns it; restoreBoard '
        're-inserts it at its old index', () async {
      final store = BoardStore.instance;
      // MockData seeds b1, b2 (b1 first); createBoard puts a third at index 0.
      final third = await store.createBoard('Third');
      await Future<void>.delayed(Duration.zero);
      expect(store.boards.value.map((b) => b.id).toList(), [
        third.id,
        'b1',
        'b2',
      ]);

      final removed = await store.deleteBoard('b1');
      expect(removed, isNotNull);
      expect(removed!.id, 'b1');
      // Synchronous optimistic removal, before the repository echo lands.
      expect(store.boards.value.map((b) => b.id).toList(), [third.id, 'b2']);

      final restoreFuture = store.restoreBoard(removed);
      // Assert position synchronously — the repository's `watch` echo can
      // reorder once it lands (see restoreBoard's doc comment).
      expect(store.boards.value.map((b) => b.id).toList(), [
        third.id,
        'b1',
        'b2',
      ]);
      await restoreFuture;
      await Future<void>.delayed(Duration.zero);
      expect(store.boards.value.any((b) => b.id == 'b1'), isTrue);
    });

    test('deleteBoard on an unknown id returns null', () async {
      final result = await BoardStore.instance.deleteBoard('no-such-board');
      expect(result, isNull);
    });

    test('removePlaceFromBoard removes a place, drops an emptied section, and '
        'is undoable via addPlaceToBoard(sectionTitle:)', () async {
      final store = BoardStore.instance;
      // b1: Food -> [p1, p3], Sightseeing -> [p2, p4], ...
      final removedFrom = await store.removePlaceFromBoard(
        boardId: 'b1',
        placeId: 'p1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(removedFrom, ['Food']);
      final afterRemove = store.boards.value.firstWhere((b) => b.id == 'b1');
      final foodSection = afterRemove.sections.where((s) => s.title == 'Food');
      // Food still has p3, so it isn't dropped.
      expect(foodSection, hasLength(1));
      expect(foodSection.first.placeIds, ['p3']);

      // Removing the last place from a section drops that section.
      final removedFrom2 = await store.removePlaceFromBoard(
        boardId: 'b1',
        placeId: 'p3',
      );
      await Future<void>.delayed(Duration.zero);
      expect(removedFrom2, ['Food']);
      final afterSecondRemove = store.boards.value.firstWhere(
        (b) => b.id == 'b1',
      );
      expect(afterSecondRemove.sections.any((s) => s.title == 'Food'), isFalse);

      // Undo restores membership (though not the original section order).
      for (final title in removedFrom2) {
        await store.addPlaceToBoard(
          boardId: 'b1',
          placeId: 'p3',
          sectionTitle: title,
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(store.containsPlace('b1', 'p3'), isTrue);
    });

    test('removePlaceFromBoard is a no-op when the place is not on the '
        'board', () async {
      final result = await BoardStore.instance.removePlaceFromBoard(
        boardId: 'b1',
        placeId: 'p9999',
      );
      expect(result, isEmpty);
    });

    test('containsPlace / boardsContaining reflect MockData seed data', () {
      final store = BoardStore.instance;
      // p3 (Koffee Mameya) is seeded into both b1 (Food) and b2 (Cafés).
      expect(store.containsPlace('b1', 'p3'), isTrue);
      expect(store.containsPlace('b2', 'p3'), isTrue);
      // p1 (Gogo) is only in b1 (Food), not seeded into b2 at all.
      expect(store.containsPlace('b2', 'p1'), isFalse);

      final boards = store.boardsContaining('p3');
      expect(boards.map((b) => b.id).toSet(), {'b1', 'b2'});
      expect(store.boardsContaining('no-such-place'), isEmpty);
    });

    test('deleteBoard persists the removal via the repository', () async {
      final repository = LocalBoardRepository();
      BoardStore.instance.bindRepository(repository);
      await Future<void>.delayed(Duration.zero);

      await BoardStore.instance.deleteBoard('b1');
      await Future<void>.delayed(Duration.zero);

      final persisted = await repository.watch().first;
      expect(persisted.any((b) => b.id == 'b1'), isFalse);
    });

    group('movePlace', () {
      List<String> ids(Board board) => [
        for (final section in board.sections) ...section.placeIds,
      ];
      Map<String, List<String>> shape(Board board) => {
        for (final section in board.sections) section.title: section.placeIds,
      };

      test('moves the place off the source (pruning its emptied section) '
          'onto the target, in the category section; every emit is already '
          'the final state and the repository gets one change', () async {
        final repository = LocalBoardRepository();
        final store = BoardStore.instance..bindRepository(repository);
        await Future<void>.delayed(Duration.zero);
        final nightlife = MockData.placeById('p5').category.labelEn;

        final repoEvents = <List<Board>>[];
        final sub = repository.watch().skip(1).listen(repoEvents.add);
        final snapshots = <List<Board>>[];
        void record() => snapshots.add(store.boards.value);
        store.boards.addListener(record);

        final move = await store.movePlace(
          placeId: 'p5',
          fromBoardId: 'b1',
          toBoardId: 'b2',
        );
        await Future<void>.delayed(Duration.zero);
        store.boards.removeListener(record);
        await sub.cancel();

        expect(move, isNotNull);
        expect(move!.from.id, 'b1');
        expect(move.to.id, 'b2');
        expect(store.containsPlace('b1', 'p5'), isFalse);
        expect(
          store.byIdOrNull('b1')!.sections.map((s) => s.title),
          isNot(contains('Nightlife')),
        );
        expect(shape(store.byIdOrNull('b2')!)[nightlife], ['p5']);

        // No intermediate frame with p5 on both boards or on neither.
        expect(snapshots, isNotEmpty);
        for (final snapshot in snapshots) {
          final b1 = snapshot.firstWhere((b) => b.id == 'b1');
          final b2 = snapshot.firstWhere((b) => b.id == 'b2');
          expect(ids(b1), isNot(contains('p5')));
          expect(ids(b2), contains('p5'));
        }
        // Optimistic update + the repository's single echo.
        expect(snapshots, hasLength(2));
        expect(repoEvents, hasLength(1));
      });

      test('undoMove restores both boards exactly, in one emit', () async {
        final store = BoardStore.instance;
        final b1Before = shape(store.byIdOrNull('b1')!);
        final b2Before = shape(store.byIdOrNull('b2')!);

        final move = await store.movePlace(
          placeId: 'p5',
          fromBoardId: 'b1',
          toBoardId: 'b2',
        );
        await Future<void>.delayed(Duration.zero);

        var emits = 0;
        void count() => emits++;
        store.boards.addListener(count);
        await store.undoMove(move!);
        store.boards.removeListener(count);
        // Optimistic restore only — the echo lands on the next hop.
        expect(emits, 1);
        await Future<void>.delayed(Duration.zero);

        expect(shape(store.byIdOrNull('b1')!), b1Before);
        expect(store.byIdOrNull('b1')!.sections.map((s) => s.title).toList(), [
          'Food',
          'Sightseeing',
          'Nightlife',
          'Stay',
        ]);
        expect(shape(store.byIdOrNull('b2')!), b2Before);
      });

      test('a target already holding the place just loses the source copy '
          '(no duplicate)', () async {
        final store = BoardStore.instance;
        // p3 is seeded into both b1 (Food) and b2 (Cafés).
        final move = await store.movePlace(
          placeId: 'p3',
          fromBoardId: 'b1',
          toBoardId: 'b2',
        );
        await Future<void>.delayed(Duration.zero);

        expect(move, isNotNull);
        expect(store.containsPlace('b1', 'p3'), isFalse);
        expect(
          ids(store.byIdOrNull('b2')!).where((id) => id == 'p3'),
          hasLength(1),
        );
      });

      test('same board, unknown board or a place not on the source is a '
          'no-op returning null with no emit', () async {
        final store = BoardStore.instance;
        var emits = 0;
        void count() => emits++;
        store.boards.addListener(count);

        expect(
          await store.movePlace(
            placeId: 'p5',
            fromBoardId: 'b1',
            toBoardId: 'b1',
          ),
          isNull,
        );
        expect(
          await store.movePlace(
            placeId: 'p5',
            fromBoardId: 'b1',
            toBoardId: 'nope',
          ),
          isNull,
        );
        expect(
          await store.movePlace(
            placeId: 'p1',
            fromBoardId: 'b2',
            toBoardId: 'b1',
          ),
          isNull,
        );
        await Future<void>.delayed(Duration.zero);
        store.boards.removeListener(count);
        expect(emits, 0);
      });
    });
  });
}
