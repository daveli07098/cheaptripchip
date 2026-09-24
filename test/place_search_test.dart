import 'package:cheaptripchip/data/place_search.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place({
  String name = '',
  String areaLabel = '',
  String region = '',
  String address = '',
  String descriptionEn = '',
  String sourceHandle = '',
  PlaceCategory category = PlaceCategory.sightseeing,
  RestaurantType? restaurantType,
}) {
  return Place(
    id: 'p',
    name: name,
    areaLabel: areaLabel,
    region: region,
    category: category,
    location: const LatLng(0, 0),
    descriptionEn: descriptionEn,
    originalCaption: '',
    address: address,
    hours: '',
    sourceHandle: sourceHandle,
    sourcePlatform: SourcePlatform.instagram,
    restaurantType: restaurantType,
  );
}

void main() {
  group('placeMatches', () {
    test('empty query matches everything', () {
      expect(placeMatches(_place(name: 'Gogo'), ''), isTrue);
      expect(placeMatches(_place(name: 'Gogo'), '   '), isTrue);
    });

    test('is case-insensitive', () {
      final place = _place(name: 'Gogo Cafe');
      expect(placeMatches(place, 'GOGO'), isTrue);
      expect(placeMatches(place, 'gogo'), isTrue);
    });

    test('multi-term query requires every term to match (AND)', () {
      final place = _place(name: 'Gogo', areaLabel: '池袋');
      expect(placeMatches(place, 'gogo 池袋'), isTrue);
      // "gogo" matches but "shibuya" doesn't — AND across fields fails.
      expect(placeMatches(place, 'gogo shibuya'), isFalse);
    });

    test('matches CJK as a plain substring, not split into words', () {
      final place = _place(areaLabel: '池袋');
      expect(placeMatches(place, '池袋'), isTrue);
      expect(placeMatches(place, '池'), isTrue);
      expect(placeMatches(place, '渋谷'), isFalse);
    });

    test('matches category label (English and Chinese)', () {
      final place = _place(category: PlaceCategory.cafe);
      expect(placeMatches(place, 'cafe'), isTrue);
      expect(placeMatches(place, '咖啡店'), isTrue);
    });

    test('matches region, address, description and source handle', () {
      final place = _place(
        region: 'Tokyo, Japan',
        address: '3-1-1 Nishi-Ikebukuro',
        descriptionEn: 'A quiet kissaten known for parfaits.',
        sourceHandle: '@rame.nbon',
      );
      expect(placeMatches(place, 'tokyo'), isTrue);
      expect(placeMatches(place, 'nishi-ikebukuro'), isTrue);
      expect(placeMatches(place, 'kissaten'), isTrue);
      expect(placeMatches(place, 'rame.nbon'), isTrue);
    });

    test('no match returns false', () {
      final place = _place(name: 'Gogo');
      expect(placeMatches(place, 'nonexistent'), isFalse);
    });

    test('matches an explicitly-set restaurant type (English and Chinese)', () {
      final place = _place(
        name: 'Gogo',
        category: PlaceCategory.restaurant,
        restaurantType: RestaurantType.ramen,
      );
      expect(placeMatches(place, 'ramen'), isTrue);
      expect(placeMatches(place, '拉麵'), isTrue);
      expect(placeMatches(place, 'sushi'), isFalse);
    });

    test('matches a keyword-detected type even when never explicitly set', () {
      final place = _place(
        name: 'Some Sushi Bar',
        category: PlaceCategory.restaurant,
      );
      expect(placeMatches(place, 'sushi'), isTrue);
      expect(placeMatches(place, '壽司'), isTrue);
    });

    test('restaurantType does not affect non-restaurant places', () {
      final place = _place(name: 'Gogo', category: PlaceCategory.cafe);
      expect(placeMatches(place, 'ramen'), isFalse);
      expect(placeMatches(place, 'other'), isFalse);
    });
  });
}
