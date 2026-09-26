import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/data/repositories.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes/failing_place_repository.dart';

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

    group('failed repository write', () {
      late FailingPlaceRepository repo;

      setUp(() async {
        repo = FailingPlaceRepository(failWrites: false);
        PlaceStore.instance.bindRepository(repo);
        await Future<void>.delayed(Duration.zero);
        await PlaceStore.instance.add(_testPlace);
        await Future<void>.delayed(Duration.zero);
        repo.failWrites = true;
      });

      test(
        'toggleFavorite reverts the optimistic change and rethrows',
        () async {
          final store = PlaceStore.instance;
          final before = store.places.value;

          await expectLater(
            store.toggleFavorite(_testPlace.id),
            throwsStateError,
          );

          expect(store.places.value, same(before));
          expect(store.byIdOrNull(_testPlace.id)!.isFavorite, isFalse);
        },
      );

      test('updateReview and addNote revert too', () async {
        final store = PlaceStore.instance;

        await expectLater(
          store.updateReview(_testPlace.id, score: 8, notes: 'x'),
          throwsStateError,
        );
        await expectLater(
          store.addNote(_testPlace.id, 'note'),
          throwsStateError,
        );

        final current = store.byIdOrNull(_testPlace.id)!;
        expect(current.myScore, isNull);
        expect(current.myNotes, isEmpty);
        expect(current.extraNotes, isEmpty);
      });
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

    test(
      'setRestaurantType marks a pick manual, unless told otherwise',
      () async {
        final store = PlaceStore.instance;
        final target = MockData.places.first;

        await store.setRestaurantType(target.id, RestaurantType.udonSoba);
        await Future<void>.delayed(Duration.zero);
        expect(store.byId(target.id).restaurantTypeManual, isTrue);

        await store.setRestaurantType(
          target.id,
          RestaurantType.ramen,
          manual: false,
        );
        await Future<void>.delayed(Duration.zero);
        expect(store.byId(target.id).restaurantTypeManual, isFalse);

        await store.setRestaurantType(target.id, RestaurantType.sushi);
        await Future<void>.delayed(Duration.zero);
        await store.setRestaurantType(target.id, null);
        await Future<void>.delayed(Duration.zero);
        expect(store.byId(target.id).restaurantTypeManual, isFalse);
      },
    );

    test('rescanRestaurantTypes refines automatic types only', () async {
      final store = PlaceStore.instance;
      Place restaurant(
        String id,
        String name,
        RestaurantType? type, {
        bool manual = false,
      }) => _testPlace.copyWith(
        id: id,
        name: name,
        descriptionEn: '',
        originalCaption: '',
        address: '',
        category: PlaceCategory.restaurant,
        restaurantType: type,
        restaurantTypeManual: manual,
      );
      final repository = _RecordingRepository([
        restaurant('auto', 'Udon Shin', RestaurantType.japanese),
        restaurant('other', 'Pizzeria Mario', RestaurantType.other),
        restaurant(
          'manual',
          'Soba Ichi',
          RestaurantType.japanese,
          manual: true,
        ),
        restaurant('unset', 'Tempura Kondo', null),
        restaurant('gemini', 'Udon Taira', RestaurantType.ramen),
        // Enough extra "Other" udon shops to need a second write chunk.
        for (var i = 0; i < PlaceStore.areaWriteChunk; i++)
          restaurant('bulk$i', 'Udon $i', RestaurantType.other),
      ]);
      store.bindRepository(repository);
      await store.loaded;

      expect(
        await store.rescanRestaurantTypes(),
        2 + PlaceStore.areaWriteChunk,
      );
      expect(repository.updateAllSizes, [PlaceStore.areaWriteChunk, 2]);
      expect(store.byId('auto').restaurantType, RestaurantType.udonSoba);
      expect(store.byId('auto').restaurantTypeManual, isFalse);
      expect(store.byId('other').restaurantType, RestaurantType.italian);
      expect(store.byId('manual').restaurantType, RestaurantType.japanese);
      expect(store.byId('unset').restaurantType, isNull);
      expect(
        store.byId('unset').effectiveRestaurantType,
        RestaurantType.tempura,
      );
      expect(store.byId('gemini').restaurantType, RestaurantType.ramen);
      expect(store.byId('bulk0').restaurantType, RestaurantType.udonSoba);
      // Feed order is kept.
      expect(store.places.value.take(5).map((p) => p.id), [
        'auto',
        'other',
        'manual',
        'unset',
        'gemini',
      ]);

      // A second pass has nothing left to do.
      expect(await store.rescanRestaurantTypes(), 0);
      expect(repository.updateAllSizes, hasLength(2));
    });

    test('setRestaurantType does nothing for an unknown id', () async {
      final store = PlaceStore.instance;
      final beforeCount = store.places.value.length;

      await store.setRestaurantType('does-not-exist', RestaurantType.sushi);
      await Future<void>.delayed(Duration.zero);

      expect(store.places.value.length, beforeCount);
    });

    test('updateCategory switches category and keeps restaurantType', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first; // p1, category restaurant
      await store.setRestaurantType(target.id, RestaurantType.izakaya);

      await store.updateCategory(target.id, PlaceCategory.cafe);
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).category, PlaceCategory.cafe);
      // Kept, just not shown off restaurants.
      expect(store.byId(target.id).restaurantType, RestaurantType.izakaya);
      expect(store.byId(target.id).effectiveRestaurantType, isNull);

      await store.updateCategory(target.id, PlaceCategory.restaurant);
      await Future<void>.delayed(Duration.zero);
      expect(
        store.byId(target.id).effectiveRestaurantType,
        RestaurantType.izakaya,
      );
    });

    test('updateCategory does nothing for an unknown id', () async {
      final store = PlaceStore.instance;
      final before = store.places.value;
      await store.updateCategory('does-not-exist', PlaceCategory.stay);
      expect(store.places.value, same(before));
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

/// Minimal [PlaceRepository] that replays a fixed list and records the size
/// of each [updateAll] batch.
class _RecordingRepository implements PlaceRepository {
  _RecordingRepository(this._places);

  final List<Place> _places;
  final List<int> updateAllSizes = [];

  @override
  Stream<List<Place>> watch() => Stream.value(_places);

  @override
  Future<void> updateAll(List<Place> places) async =>
      updateAllSizes.add(places.length);

  @override
  Future<void> upsert(Place place) async {}

  @override
  Future<void> upsertAll(List<Place> places) async {}

  @override
  Future<void> delete(String id) async {}
}
