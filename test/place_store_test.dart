import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _testPlace = Place(
  id: 'test-place',
  name: 'Test Place',
  areaLabel: 'Test Area',
  region: 'Testland',
  category: PlaceCategory.cafe,
  location: LatLng(1, 1),
  descriptionEn: 'A place used only in tests.',
  originalCaption: 'caption',
  address: 'addr',
  hours: 'hours',
  sourceHandle: '@test',
  sourcePlatform: SourcePlatform.instagram,
);

void main() {
  group('PlaceStore', () {
    setUp(() async {
      // Bind a fresh in-memory repository per test and let its initial
      // replay settle before the test body runs any mutations, so a stale
      // async replay can't race a synchronous optimistic update below.
      PlaceStore.instance.bindRepository(LocalPlaceRepository());
      await Future<void>.delayed(Duration.zero);
    });

    test('add puts the new place first', () async {
      final store = PlaceStore.instance;
      final beforeCount = store.places.value.length;

      await store.add(_testPlace);
      // Optimistic update lands synchronously, but let the repository's
      // stream catch up too before asserting, so the two stay consistent.
      await Future<void>.delayed(Duration.zero);

      expect(store.places.value.length, beforeCount + 1);
      expect(store.places.value.first.id, _testPlace.id);
    });

    test('toggleFavorite flips isFavorite for the given id', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first;
      expect(store.byId(target.id).isFavorite, target.isFavorite);

      await store.toggleFavorite(target.id);
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).isFavorite, !target.isFavorite);

      await store.toggleFavorite(target.id);
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).isFavorite, target.isFavorite);
    });

    test('byIdOrNull returns null for an unknown id', () {
      expect(PlaceStore.instance.byIdOrNull('does-not-exist'), isNull);
      expect(
        PlaceStore.instance.byIdOrNull(MockData.places.first.id),
        isNotNull,
      );
    });

    test('binding a second repository replaces the list', () async {
      final store = PlaceStore.instance;

      final repo1 = LocalPlaceRepository();
      store.bindRepository(repo1);
      await Future<void>.delayed(Duration.zero);
      expect(store.places.value.length, MockData.places.length);

      final repo2 = LocalPlaceRepository();
      await repo2.upsert(_testPlace);

      store.bindRepository(repo2);
      await Future<void>.delayed(Duration.zero);

      expect(store.places.value.length, MockData.places.length + 1);
      expect(store.places.value.first.id, _testPlace.id);
    });
  });
}
