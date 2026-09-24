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

    test('updateReview sets score and notes, then clears the score', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first;

      await store.updateReview(target.id, score: 9, notes: 'So good');
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).myScore, 9);
      expect(store.byId(target.id).myNotes, 'So good');

      // Clearing the score must not touch notes — callers pass the current
      // notes back through, and this should be a no-op for them.
      await store.updateReview(target.id, score: null, notes: 'So good');
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).myScore, isNull);
      expect(store.byId(target.id).myNotes, 'So good');
    });

    test('updateReview does nothing for an unknown id', () async {
      final store = PlaceStore.instance;
      final beforeCount = store.places.value.length;

      await store.updateReview('does-not-exist', score: 5, notes: 'x');
      await Future<void>.delayed(Duration.zero);

      expect(store.places.value.length, beforeCount);
    });

    test('byIdOrNull returns null for an unknown id', () {
      expect(PlaceStore.instance.byIdOrNull('does-not-exist'), isNull);
      expect(
        PlaceStore.instance.byIdOrNull(MockData.places.first.id),
        isNotNull,
      );
    });

    test('setRestaurantType sets the type, then clears it', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first; // p1, category restaurant

      await store.setRestaurantType(target.id, RestaurantType.izakaya);
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).restaurantType, RestaurantType.izakaya);

      await store.setRestaurantType(target.id, null);
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).restaurantType, isNull);
    });

    test('setRestaurantType does nothing for an unknown id', () async {
      final store = PlaceStore.instance;
      final beforeCount = store.places.value.length;

      await store.setRestaurantType('does-not-exist', RestaurantType.sushi);
      await Future<void>.delayed(Duration.zero);

      expect(store.places.value.length, beforeCount);
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
