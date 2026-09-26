import 'package:cheaptripchip/data/map_filter.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(
  String id, {
  PlaceCategory category = PlaceCategory.cafe,
  String name = '',
  String region = '',
  String areaLabel = '',
  LatLng location = const LatLng(35.68, 139.76),
  RestaurantType? restaurantType,
}) => Place(
  id: id,
  name: name.isEmpty ? id : name,
  areaLabel: areaLabel,
  region: region,
  category: category,
  location: location,
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
  restaurantType: restaurantType,
);

final _places = [
  _place('cafe1', region: 'Tokyo, Japan', areaLabel: 'Shibuya'),
  _place(
    'ramen1',
    category: PlaceCategory.restaurant,
    name: 'Ichiran Ramen',
    region: 'Tokyo, Japan',
    areaLabel: 'Shinjuku',
  ),
  _place(
    'sushi1',
    category: PlaceCategory.restaurant,
    restaurantType: RestaurantType.sushi,
    region: 'Osaka, Japan',
  ),
  _place('nan', location: const LatLng(double.nan, double.nan)),
];

void main() {
  group('MapFilterCache', () {
    test('equal filter on the same list returns the identical result', () {
      final cache = MapFilterCache();
      final a = cache.visibleFor(_places, const MapFilter());
      final b = cache.visibleFor(_places, const MapFilter());
      expect(identical(a, b), isTrue);
      expect(identical(cache.indexFor(_places), cache.indexFor(_places)), true);
    });

    test('a changed filter or a new list recomputes', () {
      final cache = MapFilterCache();
      final all = cache.visibleFor(_places, const MapFilter());
      final restaurants = cache.visibleFor(
        _places,
        const MapFilter(category: PlaceCategory.restaurant),
      );
      expect(identical(all, restaurants), isFalse);
      expect(restaurants.map((p) => p.id), ['ramen1', 'sushi1']);

      final copy = List.of(_places);
      final again = cache.visibleFor(
        copy,
        const MapFilter(category: PlaceCategory.restaurant),
      );
      expect(identical(again, restaurants), isFalse);
      expect(again.map((p) => p.id), ['ramen1', 'sushi1']);
    });

    test('drops non-finite places and filters by sub-type, area, query', () {
      final cache = MapFilterCache();
      expect(cache.indexFor(_places).all.map((p) => p.id), [
        'cafe1',
        'ramen1',
        'sushi1',
      ]);
      List<String> ids(MapFilter f) =>
          cache.visibleFor(_places, f).map((p) => p.id).toList();
      expect(
        ids(
          const MapFilter(
            category: PlaceCategory.restaurant,
            restaurantType: RestaurantType.ramen,
          ),
        ),
        ['ramen1'],
      );
      expect(ids(const MapFilter(city: 'Osaka')), ['sushi1']);
      expect(ids(const MapFilter(city: 'Tokyo', district: 'Shibuya')), [
        'cafe1',
      ]);
      expect(ids(const MapFilter(query: 'ichiran')), ['ramen1']);
    });
  });

  test('MapPlaceIndex counts categories, sub-types and areas', () {
    final index = MapPlaceIndex.from(_places);
    expect(index.counts, {PlaceCategory.cafe: 1, PlaceCategory.restaurant: 2});
    expect(index.restaurantTypeCounts, {
      RestaurantType.ramen: 1,
      RestaurantType.sushi: 1,
    });
    expect(index.areas.cities.map((c) => c.city), ['Tokyo', 'Osaka']);
    expect(index.areas.countOf('Tokyo', null), 2);
    expect(index.areas.countOf('Tokyo', 'Shinjuku'), 1);
  });

  test('restaurantTypeOf matches effectiveRestaurantType', () {
    for (final p in _places) {
      expect(restaurantTypeOf(p), p.effectiveRestaurantType);
      expect(restaurantTypeOf(p), p.effectiveRestaurantType); // cached path
    }
  });
}
