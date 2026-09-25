import 'dart:convert';
import 'dart:io';

import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/guest_storage.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/services/import_service.dart';
import 'package:cheaptripchip/services/my_maps_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(String id, String name, LatLng location) => Place(
  id: id,
  name: name,
  areaLabel: '',
  region: '',
  category: PlaceCategory.restaurant,
  location: location,
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
);

void main() {
  final map = parseMyMapsKml(
    File('test/fixtures/my_maps_sample.kml').readAsStringSync(),
  );

  setUp(() async {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    await Future<void>.delayed(Duration.zero);
  });

  test('PlaceStore.addAll prepends in order with one notification', () async {
    final store = PlaceStore.instance;
    final before = store.places.value.length;
    var notifications = 0;
    void listener() => notifications++;
    store.places.addListener(listener);

    await store.addAll([
      _place('n1', 'One', const LatLng(1, 1)),
      _place('n2', 'Two', const LatLng(2, 2)),
    ]);
    store.places.removeListener(listener);
    await Future<void>.delayed(Duration.zero);

    expect(notifications, greaterThanOrEqualTo(1));
    expect(notifications, lessThanOrEqualTo(2)); // optimistic + echo
    expect(store.places.value.length, before + 2);
    expect(store.places.value.take(2).map((p) => p.id), ['n1', 'n2']);
  });

  test('importMyMaps: one board, a section per layer, in-map dupes collapse, '
      'saved places reused', () async {
    // "Sample Inn" is already saved, 20 m away with different casing.
    await PlaceStore.instance.add(
      _place('saved-inn', 'sample INN', const LatLng(35.69858, 139.7745)),
    );
    await Future<void>.delayed(Duration.zero);
    final before = PlaceStore.instance.places.value.length;

    final result = await ImportService.importMyMaps(
      map,
      folders: map.folders,
      boardName: '  ',
    );
    await Future<void>.delayed(Duration.zero);

    // 10 placemarks − 1 area label (skipped by default) − 1 in-map
    // duplicate (Sample Tonkatsu twice) − 1 saved.
    expect(result.added, 7);
    expect(result.alreadySaved, 1);
    expect(PlaceStore.instance.places.value.length, before + 7);

    final board = result.board;
    expect(board.name, 'temp', reason: 'blank name falls back to default');
    expect(board.emoji, '🗺️');
    expect(board.sections.map((s) => s.title), ['Food', 'Hotel', '景點', 'temp']);
    expect(board.sections.map((s) => s.placeIds.length), [4, 1, 1, 3]);
    expect(board.sections[1].placeIds, ['saved-inn']);
    // The collapsed duplicate is the same place in both sections.
    expect(board.sections[3].placeIds, contains(board.sections[0].placeIds[0]));
    expect(BoardStore.instance.byIdOrNull(board.id)?.itemCount, 9);
    expect(
      PlaceStore.instance.places.value.any((p) => p.name == '東京都'),
      isFalse,
    );

    final tonkatsu = PlaceStore.instance.byId(board.sections[0].placeIds[0]);
    expect(tonkatsu.sourcePlatform, SourcePlatform.googleMyMaps);
    expect(tonkatsu.myScore, 8);
  });

  test('importMyMaps imports area labels as sightseeing when asked', () async {
    final result = await ImportService.importMyMaps(
      map,
      folders: [map.folders.last],
      skipAreaLabels: false,
    );
    expect(result.board.sections.single.placeIds.length, 4);
    final label = PlaceStore.instance.places.value.firstWhere(
      (p) => p.name == '東京都',
    );
    expect(label.category, PlaceCategory.sightseeing);
  });

  test('importMyMaps honours the chosen layers and board name', () async {
    final result = await ImportService.importMyMaps(
      map,
      folders: [map.folders[1]],
      boardName: 'Tokyo',
    );
    expect(result.board.name, 'Tokyo');
    expect(result.board.sections.single.title, 'Hotel');
    expect(result.added, 1);
  });

  test('importSections drops empty sections', () async {
    final result = await ImportService.importSections(
      boardName: 'X',
      emoji: '📥',
      sections: const [ImportSection('Empty', [])],
    );
    expect(result.board.sections, isEmpty, reason: 'empty sections dropped');
  });

  test('DuplicateIndex matches only same-name places within 50 m', () {
    final index = DuplicateIndex([
      _place('a', 'Cafe A', const LatLng(35, 139)),
      _place('b', 'Cafe A', const LatLng(36, 139)),
    ]);
    expect(
      index.find(_place('x', ' cafe a ', const LatLng(36.0002, 139)))?.id,
      'b',
    );
    expect(index.find(_place('y', 'Cafe B', const LatLng(35, 139))), isNull);
    expect(index.find(_place('z', 'Cafe A', const LatLng(35.01, 139))), isNull);
  });

  group('guest persistence', () {
    test('places survive a new repository instance (app restart)', () async {
      final storage = MemorySnapshotStore();
      final repo = LocalPlaceRepository(storage: storage);
      expect((await repo.watch().first).length, MockData.places.length);

      await repo.upsertAll([
        _place('p-new', 'New', const LatLng(1, 1)),
        _place('p-new2', 'New 2', const LatLng(2, 2)),
      ]);
      await repo.delete(MockData.places.first.id);
      await repo.flush();
      // The bulk upsert writes before returning; the delete adds one more.
      expect(storage.writes, 2);

      final restarted = LocalPlaceRepository(storage: storage);
      final restored = await restarted.watch().first;
      expect(restored.take(2).map((p) => p.id), ['p-new', 'p-new2']);
      expect(restored.length, MockData.places.length + 1);
      expect(restored.any((p) => p.id == MockData.places.first.id), isFalse);
    });

    test('an empty saved list stays empty (no re-seeding)', () async {
      final storage = MemorySnapshotStore('[]');
      final repo = LocalPlaceRepository(storage: storage);
      expect(await repo.watch().first, isEmpty);
    });

    test(
      'boards survive too; unreadable snapshot falls back to seed',
      () async {
        final storage = MemorySnapshotStore();
        final repo = LocalBoardRepository(storage: storage);
        await repo.upsert(
          const Board(id: 'bx', name: 'Saved', emoji: '📌', sections: []),
        );
        await repo.flush();
        final decoded = jsonDecode(storage.value!) as List;
        expect((decoded.first as Map)['id'], 'bx');
        expect(
          (await LocalBoardRepository(storage: storage).watch().first).first.id,
          'bx',
        );

        final broken = LocalBoardRepository(
          storage: MemorySnapshotStore('{not json'),
        );
        expect((await broken.watch().first).length, MockData.boards.length);
      },
    );

    test('FileSnapshotStore writes atomically and reads back', () async {
      final dir = await Directory.systemTemp.createTemp('ctc_guest_');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileSnapshotStore('places.json', baseDir: () async => dir);
      expect(await store.read(), isNull);
      await store.write('[1]');
      await store.write('[1,2]');
      expect(await store.read(), '[1,2]');
      expect(File('${dir.path}/guest/places.json.tmp').existsSync(), isFalse);
    });
  });
}
