import 'dart:convert';

import 'package:cheaptripchip/models/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('Place JSON round-trip', () {
    test('fully populated place round-trips every field', () {
      final place = Place(
        id: 'gogo-ikebukuro',
        name: '五感 (Gogo)',
        areaLabel: '池袋',
        region: 'Tokyo, Japan',
        category: PlaceCategory.cafe,
        location: const LatLng(35.7295, 139.7109),
        descriptionEn: 'A quiet kissaten known for seasonal fruit parfaits.',
        originalCaption: '池袋の隠れ家カフェ。フルーツパフェが絶品！',
        address: '3-1-1 Nishi-Ikebukuro, Toshima City, Tokyo',
        hours: '11:00–19:00, closed Tuesdays',
        sourceHandle: '@rame.nbon',
        sourcePlatform: SourcePlatform.tiktok,
        award: 'Michelin Bib Gourmand',
        matchConfident: false,
        rating: 4.7,
        reviewCount: 85,
        priceRange: '¥1,200–2,000',
        photoUrls: const [
          'https://example.com/photo1.jpg',
          'https://example.com/photo2.jpg',
        ],
        isFavorite: true,
        myScore: 9,
        myNotes: 'Loved the seasonal parfait, go early to avoid the queue.',
      );

      final json = place.toJson();
      // Confirm toJson() emits plain JSON types (no LatLng/enum objects) by
      // round-tripping through a real JSON encoder/decoder, which is what
      // Firestore/jsonDecode actually hand back (List<dynamic>, nested
      // Map<String, dynamic>) — the shapes fromJson's casts must tolerate.
      final reencoded = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
      final decoded = Place.fromJson(reencoded);

      expect(json['location'], {'lat': 35.7295, 'lng': 139.7109});
      expect(json['category'], 'cafe');
      expect(json['sourcePlatform'], 'tiktok');

      expect(decoded.id, place.id);
      expect(decoded.name, place.name);
      expect(decoded.areaLabel, place.areaLabel);
      expect(decoded.region, place.region);
      expect(decoded.category, place.category);
      expect(decoded.location.latitude, place.location.latitude);
      expect(decoded.location.longitude, place.location.longitude);
      expect(decoded.descriptionEn, place.descriptionEn);
      expect(decoded.originalCaption, place.originalCaption);
      expect(decoded.address, place.address);
      expect(decoded.hours, place.hours);
      expect(decoded.sourceHandle, place.sourceHandle);
      expect(decoded.sourcePlatform, place.sourcePlatform);
      expect(decoded.award, place.award);
      expect(decoded.matchConfident, place.matchConfident);
      expect(decoded.rating, place.rating);
      expect(decoded.reviewCount, place.reviewCount);
      expect(decoded.priceRange, place.priceRange);
      expect(decoded.photoUrls, place.photoUrls);
      expect(decoded.isFavorite, place.isFavorite);
      expect(decoded.myScore, place.myScore);
      expect(decoded.myNotes, place.myNotes);
    });

    test('minimal place (all optionals null/empty) round-trips', () {
      const place = Place(
        id: 'minimal-place',
        name: 'Unnamed Spot',
        areaLabel: '',
        region: '',
        category: PlaceCategory.sightseeing,
        location: LatLng(0, 0),
        descriptionEn: '',
        originalCaption: '',
        address: '',
        hours: '',
        sourceHandle: '',
        sourcePlatform: SourcePlatform.instagram,
      );

      final decoded = Place.fromJson(place.toJson());

      expect(decoded.award, isNull);
      expect(decoded.rating, isNull);
      expect(decoded.reviewCount, isNull);
      expect(decoded.priceRange, isNull);
      expect(decoded.photoUrls, isEmpty);
      expect(decoded.matchConfident, true);
      expect(decoded.isFavorite, false);
      expect(decoded.category, PlaceCategory.sightseeing);
      expect(decoded.sourcePlatform, SourcePlatform.instagram);
      expect(decoded.myScore, isNull);
      expect(decoded.myNotes, isEmpty);
    });

    test('lenient parse: int rating, missing photoUrls, unknown category', () {
      final json = <String, dynamic>{
        'id': 'lenient-place',
        'name': 'Some Temple',
        'areaLabel': 'Asakusa',
        'region': 'Tokyo, Japan',
        'category': 'temple', // unrecognized -> falls back to sightseeing
        'location': {'lat': 35.7148, 'lng': 139.7967},
        'descriptionEn': 'A historic temple.',
        'originalCaption': 'caption',
        'address': 'somewhere',
        'hours': '9:00-17:00',
        'sourceHandle': '@someone',
        'sourcePlatform': 'instagram',
        'rating': 4, // int, should convert to double
        // photoUrls intentionally omitted
      };

      final decoded = Place.fromJson(json);

      expect(decoded.category, PlaceCategory.sightseeing);
      expect(decoded.rating, 4.0);
      expect(decoded.rating, isA<double>());
      expect(decoded.photoUrls, isEmpty);
      expect(decoded.matchConfident, true);
      expect(decoded.isFavorite, false);
    });

    test('myScore clamps out-of-range values into 1..10', () {
      final base = <String, dynamic>{
        'id': 'p',
        'name': 'n',
        'areaLabel': '',
        'region': '',
        'category': 'cafe',
        'location': {'lat': 0, 'lng': 0},
        'descriptionEn': '',
        'originalCaption': '',
        'address': '',
        'hours': '',
        'sourceHandle': '',
        'sourcePlatform': 'instagram',
      };

      expect(Place.fromJson({...base, 'myScore': 15}).myScore, 10);
      expect(Place.fromJson({...base, 'myScore': 0}).myScore, 1);
      expect(Place.fromJson({...base, 'myScore': -5}).myScore, 1);
      expect(Place.fromJson({...base, 'myScore': 9.6}).myScore, 10);
    });

    test('myScore ignores non-numeric garbage and defaults to null', () {
      final base = <String, dynamic>{
        'id': 'p',
        'name': 'n',
        'areaLabel': '',
        'region': '',
        'category': 'cafe',
        'location': {'lat': 0, 'lng': 0},
        'descriptionEn': '',
        'originalCaption': '',
        'address': '',
        'hours': '',
        'sourceHandle': '',
        'sourcePlatform': 'instagram',
      };

      expect(Place.fromJson({...base, 'myScore': 'nine'}).myScore, isNull);
      expect(Place.fromJson({...base, 'myScore': null}).myScore, isNull);
      expect(Place.fromJson(base).myScore, isNull);
    });

    test('myNotes ignores non-string garbage and defaults to empty', () {
      final base = <String, dynamic>{
        'id': 'p',
        'name': 'n',
        'areaLabel': '',
        'region': '',
        'category': 'cafe',
        'location': {'lat': 0, 'lng': 0},
        'descriptionEn': '',
        'originalCaption': '',
        'address': '',
        'hours': '',
        'sourceHandle': '',
        'sourcePlatform': 'instagram',
      };

      expect(Place.fromJson({...base, 'myNotes': 42}).myNotes, '');
      expect(Place.fromJson(base).myNotes, '');
      expect(
        Place.fromJson({...base, 'myNotes': 'great spot'}).myNotes,
        'great spot',
      );
    });
  });
}
