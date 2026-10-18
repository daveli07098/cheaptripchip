import 'dart:convert';

import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_details.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place({String id = 'pd-1', PlaceDetails? details}) => Place(
  id: id,
  name: 'Ichiran',
  areaLabel: 'Shibuya',
  region: 'Tokyo',
  category: PlaceCategory.restaurant,
  location: const LatLng(35.66, 139.7),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
  restaurantType: RestaurantType.ramen,
  restaurantTypeManual: true,
  myNotes: 'my note',
  details: details,
);

final _details = PlaceDetails(
  mustTry: const ['tonkotsu ramen', 'kae-dama'],
  priceLevel: 2,
  nativeName: '一蘭 渋谷店',
  tags: const ['late-night', 'solo-friendly'],
  openingHours: 'Daily 24h',
  summaryEn: 'Solo-booth tonkotsu ramen.',
  summaryZh: '一人座豚骨拉麵。',
  captionEn: 'Best ramen',
  captionZh: '最好的拉麵',
  enrichedAt: DateTime.utc(2026, 10, 18, 9),
);

void main() {
  group('PlaceDetails JSON', () {
    test('round-trips every field (through jsonEncode too)', () {
      final decoded =
          jsonDecode(jsonEncode(_details.toJson())) as Map<String, dynamic>;
      final back = PlaceDetails.fromJson(decoded)!;
      expect(back.mustTry, _details.mustTry);
      expect(back.priceLevel, 2);
      expect(back.nativeName, '一蘭 渋谷店');
      expect(back.tags, _details.tags);
      expect(back.openingHours, 'Daily 24h');
      expect(back.summaryEn, _details.summaryEn);
      expect(back.summaryZh, _details.summaryZh);
      expect(back.captionEn, 'Best ramen');
      expect(back.captionZh, '最好的拉麵');
      expect(back.enrichedAt, _details.enrichedAt);
    });

    test('non-map is null; garbage fields fall back leniently', () {
      expect(PlaceDetails.fromJson(null), isNull);
      expect(PlaceDetails.fromJson('x'), isNull);
      final parsed = PlaceDetails.fromJson({
        'mustTry': ['gyoza', '', 3, null],
        'priceLevel': 7,
        'nativeName': '  ',
        'tags': ['Late-Night', 'late-night', 'VIEW'],
        'openingHours': 'null',
        'summaryEn': 42,
        'enrichedAt': 'garbage',
      })!;
      expect(parsed.mustTry, ['gyoza']);
      expect(parsed.priceLevel, isNull);
      expect(parsed.nativeName, isNull);
      expect(parsed.tags, ['late-night', 'view']);
      expect(parsed.openingHours, isNull);
      expect(parsed.summaryEn, isNull);
      expect(
        parsed.enrichedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(PlaceDetails.fromJson({'priceLevel': '3'})!.priceLevel, 3);
      expect(PlaceDetails.fromJson({'priceLevel': 2.0})!.priceLevel, 2);
      expect(PlaceDetails.fromJson({})!.isEmpty, isTrue);
    });

    test('priceSymbolFor uses the local currency', () {
      expect(priceSymbolFor(2, 'JP'), '¥¥');
      expect(priceSymbolFor(3, 'hk'), r'$$$');
      expect(priceSymbolFor(1, 'KR'), '₩');
      expect(priceSymbolFor(4, ''), r'$$$$');
    });
  });

  group('Place.details', () {
    test('missing in JSON → null, and not emitted when null', () {
      final json = _place().toJson();
      expect(json.containsKey('details'), isFalse);
      expect(Place.fromJson(json).details, isNull);
      expect(Place.fromJson({...json, 'details': 'garbage'}).details, isNull);
    });

    test('round-trips through Place JSON', () {
      final json =
          jsonDecode(jsonEncode(_place(details: _details).toJson()))
              as Map<String, dynamic>;
      final back = Place.fromJson(json).details!;
      expect(back.nativeName, '一蘭 渋谷店');
      expect(back.priceLevel, 2);
      expect(back.enrichedAt, _details.enrichedAt);
    });

    test('copyWith keeps, replaces and clears details', () {
      final place = _place(details: _details);
      expect(place.copyWith(name: 'x').details, same(_details));
      final other = _details.copyWith(priceLevel: 4);
      expect(place.copyWith(details: other).details!.priceLevel, 4);
      expect(place.copyWith(clearDetails: true).details, isNull);
    });
  });

  group('PlaceStore.updateDetails', () {
    setUp(() async {
      PlaceStore.instance.bindRepository(LocalPlaceRepository());
      await Future<void>.delayed(Duration.zero);
      await PlaceStore.instance.addAll([
        _place(id: 'a'),
        _place(id: 'b', details: _details),
      ]);
      await Future<void>.delayed(Duration.zero);
    });

    test('sets details only, leaving user-edited fields alone', () async {
      final store = PlaceStore.instance;
      final fresh = _details.copyWith(priceLevel: 1);
      final changed = await store.updateDetails({'a': fresh, 'nope': fresh});
      await Future<void>.delayed(Duration.zero);
      expect(changed, 1);
      final a = store.byId('a');
      expect(a.details!.priceLevel, 1);
      expect(a.restaurantType, RestaurantType.ramen);
      expect(a.restaurantTypeManual, isTrue);
      expect(a.myNotes, 'my note');
      expect(a.category, PlaceCategory.restaurant);
    });

    test('onlyMissing keeps details that already exist', () async {
      final store = PlaceStore.instance;
      final fresh = _details.copyWith(priceLevel: 4);
      final changed = await store.updateDetails({
        'a': fresh,
        'b': fresh,
      }, onlyMissing: true);
      await Future<void>.delayed(Duration.zero);
      expect(changed, 1);
      expect(store.byId('a').details!.priceLevel, 4);
      expect(store.byId('b').details!.priceLevel, 2);
      // Without onlyMissing (a manual refresh) it replaces.
      await store.updateDetails({'b': fresh});
      await Future<void>.delayed(Duration.zero);
      expect(store.byId('b').details!.priceLevel, 4);
    });
  });
}
