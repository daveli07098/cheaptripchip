import 'package:cheaptripchip/data/map_filter.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_area.dart';
import 'package:cheaptripchip/models/shared_board.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(
  String id, {
  PlaceCategory category = PlaceCategory.cafe,
  String name = '',
  String region = '',
  String areaLabel = '',
  String countryCode = '',
  LatLng location = const LatLng(35.68, 139.76),
  RestaurantType? restaurantType,
}) => Place(
  id: id,
  name: name.isEmpty ? id : name,
  areaLabel: areaLabel,
  region: region,
  countryCode: countryCode,
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
    expect(index.areas.cities.map((c) => c.city), ['Osaka', 'Tokyo']);
    expect(index.areas.countOf('Tokyo', null), 2);
    expect(index.areas.countOf('Tokyo', 'Shinjuku'), 1);
  });

  test('restaurantTypeOf matches effectiveRestaurantType', () {
    for (final p in _places) {
      expect(restaurantTypeOf(p), p.effectiveRestaurantType);
      expect(restaurantTypeOf(p), p.effectiveRestaurantType); // cached path
    }
  });

  group('board filter', () {
    const trip = Board(
      id: 'trip',
      name: 'Tokyo trip',
      emoji: '🗼',
      sections: [
        BoardSection(title: 'Food', placeIds: ['ramen1', 'sushi1']),
      ],
    );
    const coffee = Board(
      id: 'coffee',
      name: 'Coffee',
      emoji: '☕',
      sections: [
        BoardSection(title: 'Cafés', placeIds: ['sushi1']),
      ],
    );
    final personal = [trip, coffee];
    // Same id as a personal board, to prove the key spaces don't collide.
    final shared = [
      const SharedBoard(
        id: 'trip',
        ownerId: 'u1',
        ownerName: 'Ann',
        name: 'Group trip',
        emoji: '👯',
        sections: [
          BoardSection(title: 'Cafés', placeIds: ['cafe1']),
        ],
        members: {'u1': BoardRole.owner},
        memberNames: {'u1': 'Ann'},
        inviteCode: 'c',
      ),
    ];
    final sharedKey = BoardRef.keyFor('trip', shared: true);

    test('BoardIndex maps places ↔ boards, with New finds for the rest', () {
      final index = BoardIndex.from(
        places: MapPlaceIndex.from(_places).all,
        personal: personal,
        shared: shared,
      );
      expect(index.boards.map((b) => b.key), [sharedKey, 'trip', 'coffee']);
      expect(index.boardsOf('sushi1').map((b) => b.name), [
        'Tokyo trip',
        'Coffee',
      ]);
      expect(index.boardsOf('cafe1').single.shared, isTrue);
      expect(index.countOf('trip'), 2);
      expect(index.countOf(sharedKey), 1);

      // Drop the shared board: cafe1 is on no board → "New finds", first.
      final noShared = BoardIndex.from(
        places: MapPlaceIndex.from(_places).all,
        personal: personal,
      );
      expect(noShared.boards.first.key, kNewFindsBoardId);
      expect(noShared.boardsOf('cafe1').single.isAuto, isTrue);
      expect(noShared.countOf(kNewFindsBoardId), 1);
    });

    test('ORs picked boards, ANDs with the other filters', () {
      final cache = MapFilterCache();
      final boards = cache.boardsFor(_places, personal, shared);
      List<String> ids(MapFilter f) => cache
          .visibleFor(_places, f, boards: boards)
          .map((p) => p.id)
          .toList();
      expect(ids(const MapFilter(boards: {'coffee'})), ['sushi1']);
      expect(ids(MapFilter(boards: {'coffee', sharedKey})), [
        'cafe1',
        'sushi1',
      ]);
      expect(
        ids(
          const MapFilter(
            boards: {'trip'},
            category: PlaceCategory.restaurant,
            city: 'Tokyo',
          ),
        ),
        ['ramen1'],
      );
      // A board filter with no index matches nothing.
      expect(
        cache.visibleFor(_places, const MapFilter(boards: {'trip'})),
        isEmpty,
      );
    });

    test('memoized on board lists; set filters compare by value', () {
      final cache = MapFilterCache();
      final a = cache.boardsFor(_places, personal, shared);
      expect(identical(a, cache.boardsFor(_places, personal, shared)), isTrue);
      final first = cache.visibleFor(
        _places,
        MapFilter(boards: {'trip', 'coffee'}),
        boards: a,
      );
      final again = cache.visibleFor(
        _places,
        MapFilter(boards: {'coffee', 'trip'}),
        boards: a,
      );
      expect(identical(first, again), isTrue);

      // Same selection, edited board → new index → recomputed.
      final edited = [
        trip.copyWith(
          sections: const [
            BoardSection(title: 'Food', placeIds: ['ramen1']),
          ],
        ),
        coffee,
      ];
      final b = cache.boardsFor(_places, edited, shared);
      expect(identical(a, b), isFalse);
      final after = cache.visibleFor(
        _places,
        MapFilter(boards: {'trip', 'coffee'}),
        boards: b,
      );
      expect(after.map((p) => p.id), ['ramen1', 'sushi1']);
      expect(
        cache
            .visibleFor(_places, const MapFilter(boards: {'trip'}), boards: b)
            .map((p) => p.id),
        ['ramen1'],
      );
    });
  });

  test('areas group country → city → district, each A–Z, unknown last', () {
    final index = MapPlaceIndex.from([
      _place('a', region: 'tokyo', areaLabel: 'Shibuya', countryCode: 'JP'),
      _place('b', region: 'Osaka', areaLabel: 'Namba', countryCode: 'JP'),
      _place('c', region: 'Tokyo', areaLabel: 'Asakusa', countryCode: 'JP'),
      _place('d', region: 'Tokyo', areaLabel: 'shinjuku', countryCode: 'JP'),
      _place('e', region: 'Taipei', countryCode: 'TW'),
      _place('f', region: 'Hong Kong', countryCode: 'HK'),
      _place('g', region: 'Mystery'),
      _place('h'),
    ]);
    final areas = index.areas;
    expect(areas.countries.map((c) => c.name), [
      'Hong Kong',
      'Japan',
      'Taiwan',
      'Unknown country',
    ]);
    final japan = areas.countries[1];
    expect(japan.count, 4);
    expect(japan.cities.map((c) => c.city), ['Osaka', 'Tokyo', 'tokyo']);
    final tokyo = japan.cities[1];
    expect(tokyo.sortedDistricts.map((e) => e.key), ['Asakusa', 'shinjuku']);
    expect(areas.countries.last.cities.single.city, 'Mystery');
    expect(areas.unknownCount, 1);
  });

  test('countryName: known codes, fallback to the code, empty', () {
    expect(countryName('jp'), 'Japan');
    expect(countryName('XK'), 'XK');
    expect(countryName(''), 'Unknown country');
  });

  group('favourites filter', () {
    final fav = _place('fav').copyWith(isFavorite: true);
    final plain = _place('plain');

    test('favoritesOnly keeps only favourites and ANDs with the rest', () {
      const filter = MapFilter(favoritesOnly: true);
      expect(filter.matches(fav), isTrue);
      expect(filter.matches(plain), isFalse);
      expect(
        const MapFilter(
          favoritesOnly: true,
          category: PlaceCategory.restaurant,
        ).matches(fav),
        isFalse,
      );
    });

    test('is part of equality, so the cache recomputes on a toggle', () {
      expect(const MapFilter(favoritesOnly: true), isNot(const MapFilter()));
      expect(
        const MapFilter(favoritesOnly: true).hashCode,
        const MapFilter(favoritesOnly: true).hashCode,
      );
      final cache = MapFilterCache();
      final loaded = [fav, plain];
      final all = cache.visibleFor(loaded, const MapFilter());
      final favs = cache.visibleFor(
        loaded,
        const MapFilter(favoritesOnly: true),
      );
      expect(all, hasLength(2));
      expect(favs.map((p) => p.id), ['fav']);
      expect(
        cache.visibleFor(loaded, const MapFilter(favoritesOnly: true)),
        same(favs),
      );
    });

    test('MapPlaceIndex counts favourites; activeCount counts it', () {
      expect(MapPlaceIndex.from([fav, plain, fav]).favoriteCount, 2);
      expect(const MapFilter(favoritesOnly: true).activeCount, 1);
      expect(
        const MapFilter(
          favoritesOnly: true,
          city: 'Tokyo',
          boards: {'a', 'b'},
          query: 'ramen',
        ).activeCount,
        4,
      );
    });
  });

  test('placeMarkerEmoji/Label: sub-type for restaurants, else category', () {
    final ramen = _place(
      'r',
      category: PlaceCategory.restaurant,
      restaurantType: RestaurantType.ramen,
    );
    final other = _place(
      'o',
      category: PlaceCategory.restaurant,
      restaurantType: RestaurantType.other,
    );
    final cafe = _place('c');
    expect(placeMarkerEmoji(ramen), RestaurantType.ramen.emoji);
    expect(placeMarkerLabel(ramen), 'Ramen');
    expect(placeMarkerEmoji(other), PlaceCategory.restaurant.emoji);
    expect(placeMarkerLabel(other), PlaceCategory.restaurant.labelEn);
    expect(placeMarkerEmoji(cafe), PlaceCategory.cafe.emoji);
  });
}
