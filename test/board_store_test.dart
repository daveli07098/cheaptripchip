import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
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
  });
}
