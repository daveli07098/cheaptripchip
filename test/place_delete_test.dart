import 'dart:typed_data';

import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/memory_photo_repository.dart';
import 'package:cheaptripchip/data/photo_store.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/data/repositories.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/failing_place_repository.dart';

/// [LocalBoardRepository] that counts writes and can fail them.
class _RecordingBoardRepository implements BoardRepository {
  final LocalBoardRepository _inner = LocalBoardRepository();
  int upserts = 0;
  int upsertAlls = 0;
  bool failWrites = false;

  @override
  Stream<List<Board>> watch() => _inner.watch();

  @override
  Future<void> upsert(Board board) async {
    upserts++;
    if (failWrites) throw StateError('offline');
    await _inner.upsert(board);
  }

  @override
  Future<void> upsertAll(List<Board> boards) async {
    upsertAlls++;
    if (failWrites) throw StateError('offline');
    await _inner.upsertAll(boards);
  }

  @override
  Future<void> delete(String id) => _inner.delete(id);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

List<String> _ids(Board board, String section) =>
    board.sections.firstWhere((s) => s.title == section).placeIds;

void main() {
  final places = PlaceStore.instance;
  final boards = BoardStore.instance;
  late FailingPlaceRepository placeRepo;
  late _RecordingBoardRepository boardRepo;

  setUp(() async {
    placeRepo = FailingPlaceRepository(failWrites: false);
    boardRepo = _RecordingBoardRepository();
    places.bindRepository(placeRepo);
    boards.bindRepository(boardRepo);
    await _settle();
  });

  test('deletePlace drops the place and takes it off every board in one '
      'board write', () async {
    // p3 is on "Tokyo Trip 2026" (Food, 2nd) and "Coffee & Quiet" (Cafés,
    // alone — that section is pruned).
    final deleted = await places.deletePlace('p3');
    await _settle();

    expect(deleted, isNotNull);
    expect(deleted!.index, 2);
    expect(places.byIdOrNull('p3'), isNull);
    expect(boardRepo.upsertAlls, 1);
    expect(boardRepo.upserts, 0);
    expect(_ids(boards.byIdOrNull('b1')!, 'Food'), ['p1']);
    expect(
      boards.byIdOrNull('b2')!.sections.map((s) => s.title),
      isNot(contains('Cafés')),
    );
    expect(boards.boardsContaining('p3'), isEmpty);
  });

  test('the optimistic update lands before the first await', () {
    places.deletePlace('p3');
    expect(places.byIdOrNull('p3'), isNull);
    expect(boards.boardsContaining('p3'), isEmpty);
  });

  test('restoreDeleted puts the place and its board positions back', () async {
    final deleted = (await places.deletePlace('p3'))!;
    await _settle();
    // An unrelated edit during the undo window survives the restore.
    await boards.removePlaceFromBoard(boardId: 'b1', placeId: 'p1');
    await _settle();
    final before = boardRepo.upsertAlls;

    final restoring = places.restoreDeleted(deleted);
    // Optimistically at its old index.
    expect(places.places.value.indexWhere((p) => p.id == 'p3'), 2);
    await restoring;
    await _settle();

    expect(places.byIdOrNull('p3'), isNotNull);
    expect(boardRepo.upsertAlls, before + 1);
    final b1 = boards.byIdOrNull('b1')!;
    expect(_ids(b1, 'Food'), ['p3']);
    final b2 = boards.byIdOrNull('b2')!;
    expect(b2.sections.map((s) => s.title), ['Cafés', 'Walks']);
    expect(_ids(b2, 'Cafés'), ['p3']);

    // A second UNDO is a no-op.
    await places.restoreDeleted(deleted);
    expect(places.places.value.where((p) => p.id == 'p3'), hasLength(1));
  });

  test('restore keeps the position inside a section', () async {
    await boards.createBoard(
      'Mixed',
      sections: const [
        BoardSection(title: 'Food', placeIds: ['p1', 'p3', 'p5']),
      ],
    );
    await _settle();
    final mixed = boards.boards.value.first.id;
    final deleted = (await places.deletePlace('p3'))!;
    await _settle();
    expect(_ids(boards.byIdOrNull(mixed)!, 'Food'), ['p1', 'p5']);

    await places.restoreDeleted(deleted);
    await _settle();
    expect(_ids(boards.byIdOrNull(mixed)!, 'Food'), ['p1', 'p3', 'p5']);
  });

  test('a failed place delete reverts the list and the boards', () async {
    placeRepo.failDeletes = true;
    final before = places.places.value;

    await expectLater(places.deletePlace('p3'), throwsStateError);
    await _settle();

    expect(places.places.value.map((p) => p.id), before.map((p) => p.id));
    expect(_ids(boards.byIdOrNull('b1')!, 'Food'), ['p1', 'p3']);
    expect(_ids(boards.byIdOrNull('b2')!, 'Cafés'), ['p3']);
  });

  test(
    'a failed board write reverts both and skips the place delete',
    () async {
      boardRepo.failWrites = true;

      await expectLater(places.deletePlace('p3'), throwsStateError);
      await _settle();

      expect(places.byIdOrNull('p3'), isNotNull);
      expect(_ids(boards.byIdOrNull('b1')!, 'Food'), ['p1', 'p3']);
    },
  );

  test('unknown id returns null and changes nothing', () async {
    final before = places.places.value;
    expect(await places.deletePlace('nope'), isNull);
    expect(places.places.value, same(before));
    expect(boardRepo.upsertAlls, 0);
  });

  group('PhotoStore.discardPhotoOf', () {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 1]);
    late MemoryPhotoRepository photoRepo;

    setUp(() async {
      photoRepo = MemoryPhotoRepository();
      PhotoStore.instance.bindRepository(photoRepo);
      await PhotoStore.instance.setPhoto('p1', jpeg);
      await _settle();
    });

    test('deletePlace leaves the photo; discard removes it', () async {
      final deleted = (await places.deletePlace('p1'))!;
      expect(deleted.hadPhoto, isTrue);
      expect(await photoRepo.load('p1'), jpeg);

      await PhotoStore.instance.discardPhotoOf(deleted);
      expect(await photoRepo.load('p1'), isNull);
    });

    test('a restored place keeps its photo', () async {
      final deleted = (await places.deletePlace('p1'))!;
      await places.restoreDeleted(deleted);
      await _settle();

      await PhotoStore.instance.discardPhotoOf(deleted);
      expect(await photoRepo.load('p1'), jpeg);
      expect(places.byId('p1').myPhotoAt, isNotNull);
    });
  });

  tearDown(() {
    // Leave later test files with plain seeded stores.
    places.bindRepository(LocalPlaceRepository());
    boards.bindRepository(LocalBoardRepository());
    PhotoStore.instance.bindRepository(MemoryPhotoRepository());
  });
}
