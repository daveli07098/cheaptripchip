// Unconfirmed locations: the extractor's stand-in pin (geocoding failed) is
// flagged instead of silently saved as a real one, the card/pin/detail
// sheet say so, and the place page lets the user fix it.
import 'dart:convert';
import 'dart:io';

import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/memory_photo_repository.dart';
import 'package:cheaptripchip/data/photo_store.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/screens/place_detail_sheet.dart';
import 'package:cheaptripchip/services/ai_service.dart';
import 'package:cheaptripchip/services/geocoding_service.dart';
import 'package:cheaptripchip/services/place_extractor.dart';
import 'package:cheaptripchip/widgets/location_fix.dart';
import 'package:cheaptripchip/widgets/map_pin.dart';
import 'package:cheaptripchip/widgets/place_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

const _place = Place(
  id: 'unconfirmed-1',
  name: 'Hidden Bar',
  areaLabel: 'Shibuya',
  region: 'Tokyo, Japan',
  category: PlaceCategory.nightlife,
  location: LatLng(35.68, 139.76),
  descriptionEn: 'Somewhere.',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
  matchConfident: false,
  locationConfirmed: false,
);

PlaceExtractor _extractor({required List<Map<String, String>> geocodeHits}) {
  final ai = AiService(
    apiKey: 'test-key',
    client: MockClient(
      (req) async => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'name': 'Real Place',
                  'address': 'nowhere findable',
                  'region': 'Tokyo, Japan',
                }),
              },
            },
          ],
        }),
        200,
      ),
    ),
  );
  return PlaceExtractor(
    ai: ai,
    geocoder: GeocodingService(
      client: MockClient(
        (req) async => http.Response(jsonEncode(geocodeHits), 200),
      ),
    ),
    metadataFetcher: (_) async => null,
  );
}

void main() {
  group('Place.locationConfirmed JSON', () {
    test('missing key reads as confirmed (data saved before the flag)', () {
      final json = _place.toJson()..remove('locationConfirmed');
      expect(Place.fromJson(json).locationConfirmed, isTrue);
    });

    test('round-trips false, and toJson always writes the key', () {
      expect(_place.toJson()['locationConfirmed'], isFalse);
      expect(Place.fromJson(_place.toJson()).locationConfirmed, isFalse);
      final confirmed = _place.copyWith(locationConfirmed: true).toJson();
      expect(confirmed['locationConfirmed'], isTrue);
    });

    test('firestore.rules validPlace allow-list covers every toJson key', () {
      final rules = File('firestore.rules').readAsStringSync();
      final start = rules.indexOf('function validPlace');
      final list = rules.substring(
        rules.indexOf('hasOnly([', start),
        rules.indexOf('])', start),
      );
      final full = _place.copyWith(locationConfirmed: true).toJson();
      for (final key in full.keys) {
        expect(list, contains("'$key'"), reason: 'missing $key');
      }
    });
  });

  group('PlaceExtractor fallback location', () {
    test('geocoding failure flags the stand-in pin as unconfirmed', () async {
      final place = await _extractor(
        geocodeHits: const [],
      ).extract('a caption with a real place');
      expect(place.name, 'Real Place');
      expect(place.locationConfirmed, isFalse);
    });

    test('a geocoded place is confirmed', () async {
      final place = await _extractor(
        geocodeHits: const [
          {'lat': '35.0', 'lon': '139.0'},
        ],
      ).extract('a caption with a real place');
      expect(place.location, const LatLng(35.0, 139.0));
      expect(place.locationConfirmed, isTrue);
    });
  });

  group('PlaceStore.setLocation', () {
    setUp(() => PlaceStore.instance.bindRepository(LocalPlaceRepository()));

    test('moves, confirms, and only fills an empty address', () async {
      await PlaceStore.instance.add(_place);
      // Local repositories emit after a microtask hop.
      await Future<void>.delayed(Duration.zero);
      await PlaceStore.instance.setLocation(
        _place.id,
        const LatLng(1, 2),
        address: '1 Picked St',
      );
      await Future<void>.delayed(Duration.zero);
      var saved = PlaceStore.instance.byIdOrNull(_place.id)!;
      expect(saved.location, const LatLng(1, 2));
      expect(saved.locationConfirmed, isTrue);
      expect(saved.matchConfident, isTrue);
      expect(saved.address, '1 Picked St');

      await PlaceStore.instance.setLocation(
        _place.id,
        const LatLng(3, 4),
        address: 'Other St',
      );
      await Future<void>.delayed(Duration.zero);
      saved = PlaceStore.instance.byIdOrNull(_place.id)!;
      expect(saved.location, const LatLng(3, 4));
      expect(saved.address, '1 Picked St');
    });
  });

  group('badges', () {
    testWidgets('place card shows the badge instead of "Pinned"', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceCard(place: _place, onTap: () {}),
          ),
        ),
      );
      expect(find.text(kLocationUnconfirmedFixLabel), findsOneWidget);
      expect(find.text('Pinned'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceCard(
              place: _place.copyWith(
                locationConfirmed: true,
                matchConfident: true,
              ),
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text(kLocationUnconfirmedFixLabel), findsNothing);
      expect(find.text('Pinned'), findsOneWidget);
    });

    testWidgets('map pin is dashed and announced as unconfirmed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: MapPin(
              place: _place,
              selected: false,
              brightness: Brightness.light,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp('location unconfirmed')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.foregroundPainter is DashedRingPainter,
        ),
        findsOneWidget,
      );
    });
  });

  group('fix flow on the place page', () {
    setUp(() {
      PlaceStore.instance.bindRepository(LocalPlaceRepository());
      PhotoStore.instance.bindRepository(MemoryPhotoRepository());
    });

    testWidgets('"Use current map center" confirms it and hides the badge', (
      tester,
    ) async {
      await PlaceStore.instance.add(_place);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceDetailSheet(
              place: _place,
              currentMapCenter: () => const LatLng(10, 20),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(kLocationUnconfirmedFixLabel));
      await tester.pumpAndSettle();
      expect(find.text('Fix location'), findsOneWidget);

      await tester.tap(find.text(kUseMapCenterLabel));
      await tester.pumpAndSettle();

      final saved = PlaceStore.instance.byIdOrNull(_place.id)!;
      expect(saved.location, const LatLng(10, 20));
      expect(saved.locationConfirmed, isTrue);
      expect(find.text(kLocationUnconfirmedFixLabel), findsNothing);
    });

    testWidgets('no map centre option off the map; address search picks a '
        'match', (tester) async {
      String? query;
      final geocoder = GeocodingService(
        client: MockClient((req) async {
          query = req.url.queryParameters['q'];
          return http.Response(
            jsonEncode([
              {'lat': '35.66', 'lon': '139.70', 'display_name': '1 Real St'},
            ]),
            200,
          );
        }),
      );
      FixedLocation? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showFixLocationDialog(
                context,
                _place,
                geocoder: geocoder,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(kUseMapCenterLabel), findsNothing);

      await tester.tap(find.byTooltip('Search address'));
      await tester.pumpAndSettle();
      expect(query, 'Hidden Bar Tokyo');

      await tester.tap(find.text('1 Real St'));
      await tester.pumpAndSettle();
      expect(result?.location, const LatLng(35.66, 139.70));
      expect(result?.address, '1 Real St');
    });
  });
}
