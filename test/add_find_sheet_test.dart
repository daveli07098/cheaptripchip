import 'dart:convert';

import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/services/extraction_cache.dart';
import 'package:cheaptripchip/services/gemini_service.dart';
import 'package:cheaptripchip/services/geocoding_service.dart';
import 'package:cheaptripchip/services/place_extractor.dart';
import 'package:cheaptripchip/widgets/accessible_emoji.dart';
import 'package:cheaptripchip/widgets/add_find_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

PlaceExtractor _extractor(Map<String, Object?> geminiJson) => PlaceExtractor(
  gemini: GeminiService(
    apiKey: 'test-key',
    client: MockClient(
      (req) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': jsonEncode(geminiJson)},
                  ],
                },
              },
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  ),
  geocoder: GeocodingService(
    client: MockClient((req) async => http.Response('[]', 200)),
  ),
  metadataFetcher: (uri) async => null,
  cache: MemoryExtractionCache(),
  delay: (d) async {},
);

Future<void> _openSheet(WidgetTester tester, PlaceExtractor extractor) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AddFindSheet(extractor: extractor),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'a caption');
  await tester.tap(find.text('Extract & save'));
  await _settle(tester);
}

/// pumpAndSettle can't settle while the sheet's busy spinner animates
/// behind a dialog — pump a bounded number of frames instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Map<String, Object?> _spot(String name, double lat, double lng, [double? c]) =>
    {
      'name': name,
      'latitude': lat,
      'longitude': lng,
      'category': 'cafe',
      'areaLabel': 'Testville',
      'confidence': ?c,
    };

void main() {
  setUp(() async {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('multi-place post shows a ticked checklist and saves the '
      'ticked ones', (tester) async {
    final before = PlaceStore.instance.places.value.length;
    await _openSheet(
      tester,
      _extractor({
        'places': [
          _spot('Zeta Cafe', -40.1, 170.1),
          _spot('Eta Cafe', -40.2, 170.2),
          _spot('Theta Cafe', -40.3, 170.3),
        ],
      }),
    );

    expect(find.text('3 places in this post'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    expect(find.byType(AccessibleEmoji), findsNWidgets(3));
    await tester.tap(find.text('Eta Cafe'));
    await tester.pump();
    await tester.tap(find.text('Save 2 finds'));
    await _settle(tester);

    final names = PlaceStore.instance.places.value.map((p) => p.name);
    expect(names, containsAll(['Zeta Cafe', 'Theta Cafe']));
    expect(names, isNot(contains('Eta Cafe')));
    expect(PlaceStore.instance.places.value.length, before + 2);
    expect(find.text('Saved 2 finds'), findsOneWidget);
  });

  testWidgets('a duplicate offers merge, which notes the post on the '
      'existing place instead of saving a copy', (tester) async {
    final existing = PlaceStore.instance.places.value.first;
    final before = PlaceStore.instance.places.value.length;
    await _openSheet(
      tester,
      _extractor({
        'places': [
          {
            ..._spot(
              existing.name,
              existing.location.latitude,
              existing.location.longitude,
            ),
            'sourceHandle': '@new.source',
          },
          _spot('Brand New Cafe', -41.0, 171.0),
        ],
      }),
    );
    await tester.tap(find.text('Save 2 finds'));
    await _settle(tester);

    expect(find.text('Already saved'), findsOneWidget);
    await tester.tap(find.text('Merge'));
    await _settle(tester);

    final store = PlaceStore.instance;
    expect(store.places.value.length, before + 1);
    expect(
      store.byId(existing.id).extraNotes.map((n) => n.text),
      contains('Also saved from a post by @new.source'),
    );
    expect(
      find.text('Saved 1 find, merged 1 into saved places'),
      findsOneWidget,
    );
  });

  testWidgets('a low-confidence guess asks "Which one?" and is never saved '
      'silently', (tester) async {
    final before = PlaceStore.instance.places.value.length;
    await _openSheet(
      tester,
      _extractor({
        'places': [
          {
            ..._spot('Maybe Cafe', -42.0, 172.0, 0.3),
            'alternatives': [
              {'name': 'Maybe Cafe Annex', 'region': 'Testville'},
            ],
          },
        ],
      }),
    );

    expect(find.text('Which one?'), findsOneWidget);
    expect(find.text('Maybe Cafe Annex'), findsOneWidget);
    await tester.tap(find.text('None of these — skip'));
    await _settle(tester);

    expect(PlaceStore.instance.places.value.length, before);
    expect(find.text('Nothing saved.'), findsOneWidget);
  });

  testWidgets('caption fetch failure offers "Use a screenshot instead"', (
    tester,
  ) async {
    final extractor = _extractor({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddFindSheet(
            extractor: extractor,
            initialText: 'https://www.instagram.com/reel/abc/',
            autoExtract: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Use a screenshot instead'), findsOneWidget);
    expect(find.text('Add from screenshot'), findsOneWidget);
  });

  test('ExtractedPlace.needsConfirmation threshold', () {
    const place = Place(
      id: 'x',
      name: 'X',
      areaLabel: '',
      region: '',
      category: PlaceCategory.cafe,
      location: LatLng(0, 0),
      descriptionEn: '',
      originalCaption: '',
      address: '',
      hours: '',
      sourceHandle: '',
      sourcePlatform: SourcePlatform.instagram,
    );
    expect(
      const ExtractedPlace(place: place, confidence: 0.59).needsConfirmation,
      isTrue,
    );
    expect(
      const ExtractedPlace(place: place, confidence: 0.6).needsConfirmation,
      isFalse,
    );
    expect(
      const ExtractedPlace(
        place: place,
        geocodeAmbiguous: true,
      ).needsConfirmation,
      isTrue,
    );
  });
}
