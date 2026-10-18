import 'dart:convert';
import 'dart:typed_data';

import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/services/extraction_cache.dart';
import 'package:cheaptripchip/services/geocoding_service.dart';
import 'package:cheaptripchip/services/gemini_service.dart';
import 'package:cheaptripchip/services/place_extractor.dart';
import 'package:cheaptripchip/services/post_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

/// Wraps a JSON map the way the real Gemini REST response nests model output,
/// so [GeminiService] with a [MockClient] behaves like the real API.
http.Response _geminiResponse(Map<String, Object?> json) {
  return http.Response(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(json)},
            ],
          },
        },
      ],
    }),
    200,
  );
}

void main() {
  // Only PlaceExtractor.parseRestaurantType is exercised here — it's a pure
  // string→enum mapper with no network calls, unlike extract() itself (see
  // the class doc comment: PlaceExtractor()'s constructor has no side
  // effects, it just stores config).
  group('PlaceExtractor.parseRestaurantType', () {
    final extractor = PlaceExtractor();

    test('returns null for a non-restaurant category, whatever the text', () {
      expect(
        extractor.parseRestaurantType('ramen', PlaceCategory.cafe),
        isNull,
      );
    });

    test('returns null for empty/missing input', () {
      expect(
        extractor.parseRestaurantType('', PlaceCategory.restaurant),
        isNull,
      );
    });

    test('matches an exact RestaurantType.name, case-insensitively', () {
      expect(
        extractor.parseRestaurantType('ramen', PlaceCategory.restaurant),
        RestaurantType.ramen,
      );
      expect(
        extractor.parseRestaurantType('ChaChaanTeng', PlaceCategory.restaurant),
        RestaurantType.chaChaanTeng,
      );
    });

    test(
      'maps common synonyms the model might use instead of the enum name',
      () {
        const cases = {
          'sushi': RestaurantType.sushi,
          'sashimi': RestaurantType.sushi,
          'yakitori': RestaurantType.yakitori,
          'udon': RestaurantType.udonSoba,
          'soba': RestaurantType.udonSoba,
          'pizza': RestaurantType.italian,
          'French': RestaurantType.french,
          'unagi': RestaurantType.donburi,
          'dim sum': RestaurantType.dimsum,
          'cantonese': RestaurantType.dimsum,
          'bbq': RestaurantType.yakiniku,
          'barbecue': RestaurantType.yakiniku,
          'cha chaan teng': RestaurantType.chaChaanTeng,
          '茶餐廳': RestaurantType.chaChaanTeng,
        };
        for (final entry in cases.entries) {
          expect(
            extractor.parseRestaurantType(entry.key, PlaceCategory.restaurant),
            entry.value,
            reason: 'for "${entry.key}"',
          );
        }
      },
    );

    test('returns null for an unrecognized value rather than guessing', () {
      expect(
        extractor.parseRestaurantType(
          'some cuisine gemini invented',
          PlaceCategory.restaurant,
        ),
        isNull,
      );
    });
  });

  group('PlaceExtractor.extract', () {
    const bareUrl = 'https://www.instagram.com/reel/abc123/';

    PlaceExtractor build({
      required Map<String, Object?> geminiJson,
      Future<PostMetadata?> Function(Uri)? metadataFetcher,
      LatLng? geocoded,
    }) {
      final gemini = GeminiService(
        apiKey: 'test-key',
        client: MockClient((req) async => _geminiResponse(geminiJson)),
      );
      final geocoder = GeocodingService(
        client: MockClient((req) async {
          final body = geocoded == null
              ? '[]'
              : jsonEncode([
                  {
                    'lat': '${geocoded.latitude}',
                    'lon': '${geocoded.longitude}',
                  },
                ]);
          return http.Response(body, 200);
        }),
      );
      return PlaceExtractor(
        gemini: gemini,
        geocoder: geocoder,
        metadataFetcher: metadataFetcher,
      );
    }

    test(
      'throws CaptionUnavailableException for a bare post URL with no fetchable metadata',
      () async {
        // apiKey deliberately blank: if the guard were skipped this would
        // throw a StateError from GeminiService instead, so the assertion
        // below genuinely distinguishes "guard fired" from "guard skipped".
        final extractor = PlaceExtractor(
          gemini: GeminiService(apiKey: ''),
          metadataFetcher: (uri) async => null,
        );
        await expectLater(
          extractor.extract(bareUrl),
          throwsA(isA<CaptionUnavailableException>()),
        );
      },
    );

    test('does not throw for a bare URL when metadata has a caption, and feeds '
        'the caption + author to Gemini', () async {
      String? sentPrompt;
      final gemini = GeminiService(
        apiKey: 'test-key',
        client: MockClient((req) async {
          sentPrompt =
              jsonDecode(req.body)['contents'][0]['parts'][0]['text'] as String;
          return _geminiResponse({
            'name': 'Ramen Bon',
            'address': '1 Ikebukuro, Tokyo',
            'region': 'Tokyo, Japan',
          });
        }),
      );
      final geocoder = GeocodingService(
        client: MockClient(
          (req) async => http.Response(
            jsonEncode([
              {'lat': '35.0', 'lon': '139.0'},
            ]),
            200,
          ),
        ),
      );
      final extractor = PlaceExtractor(
        gemini: gemini,
        geocoder: geocoder,
        metadataFetcher: (uri) async => const PostMetadata(
          title: 'Ramen Bon on Instagram: "Best tonkotsu in town"',
          description: '1 like - rame.nbon on Jan 1, 2024: "Best tonkotsu"',
          author: '@rame_test_handle',
        ),
      );
      final place = await extractor.extract(bareUrl);
      expect(place.name, 'Ramen Bon');
      // Assert the exact injected lines, not just a substring the prompt's
      // own instructions might also contain (e.g. the sourceHandle example).
      expect(
        sentPrompt,
        contains('CAPTION (from the post page): Best tonkotsu in town'),
      );
      expect(sentPrompt, contains('AUTHOR: @rame_test_handle'));
    });

    test(
      'throws NoPlaceFoundException when Gemini returns nothing to geocode',
      () async {
        final extractor = build(
          geminiJson: {'name': '', 'address': ''},
          metadataFetcher: (uri) async => null,
        );
        await expectLater(
          extractor.extract('just a caption, no place mentioned'),
          throwsA(isA<NoPlaceFoundException>()),
        );
      },
    );

    test(
      'throws NoPlaceFoundException when the placeholder name also fails to geocode',
      () async {
        final extractor = build(
          geminiJson: {'name': '', 'address': 'somewhere vague'},
          geocoded: null, // geocoder returns []
        );
        await expectLater(
          extractor.extract('somewhere vague, no real name'),
          throwsA(isA<NoPlaceFoundException>()),
        );
      },
    );

    test(
      'saves normally when Gemini finds a real name even if geocoding fails',
      () async {
        final extractor = build(
          geminiJson: {'name': 'Real Place', 'address': 'nowhere findable'},
          geocoded: null,
        );
        final place = await extractor.extract('a caption with a real place');
        expect(place.name, 'Real Place');
        expect(place.matchConfident, isFalse);
      },
    );

    test(
      'fills sourceHandle/sourcePlatform from metadata when Gemini omits them',
      () async {
        final extractor = build(
          geminiJson: {'name': 'Ramen Bon', 'address': '1 Ikebukuro, Tokyo'},
          geocoded: const LatLng(35.0, 139.0),
          metadataFetcher: (uri) async =>
              const PostMetadata(author: '@rame.nbon'),
        );
        final place = await extractor.extract('$bareUrl caption text here');
        expect(place.sourceHandle, '@rame.nbon');
        expect(place.sourcePlatform, SourcePlatform.instagram);
      },
    );
  });

  group('PlaceExtractor parsing helpers', () {
    test('rawCandidates reads {"places": [...]}', () {
      final raws = PlaceExtractor.rawCandidates({
        'places': [
          {'name': 'A'},
          'junk',
          {'name': 'B'},
        ],
      });
      expect(raws.map((r) => r['name']), ['A', 'B']);
    });

    test('rawCandidates accepts the legacy single bare object', () {
      final raws = PlaceExtractor.rawCandidates({
        'name': 'Solo',
        'address': '',
      });
      expect(raws, hasLength(1));
      expect(raws.first['name'], 'Solo');
    });

    test('rawCandidates returns nothing for an empty or unrelated reply', () {
      expect(PlaceExtractor.rawCandidates({'places': []}), isEmpty);
      expect(PlaceExtractor.rawCandidates({}), isEmpty);
    });

    test('parseConfidence: missing → 1.0, percent scaled, clamped', () {
      expect(PlaceExtractor.parseConfidence(null), 1.0);
      expect(PlaceExtractor.parseConfidence('n/a'), 1.0);
      expect(PlaceExtractor.parseConfidence(0.42), 0.42);
      expect(PlaceExtractor.parseConfidence('0.3'), 0.3);
      expect(PlaceExtractor.parseConfidence(85), 0.85);
      expect(PlaceExtractor.parseConfidence(-1), 0.0);
      expect(PlaceExtractor.parseConfidence(500), 1.0);
    });

    test('parseAlternatives keeps up to 3 distinct named ones, minus the '
        'primary', () {
      final alts = PlaceExtractor.parseAlternatives([
        {'name': 'Ichiran', 'region': 'Tokyo'},
        {'name': 'Ichiran Shibuya', 'areaLabel': 'Shibuya'},
        {'name': ''},
        {'name': 'ichiran shibuya'},
        {'name': 'Ichiran Shinjuku'},
        {'name': 'Ichiran Ueno'},
        {'name': 'Ichiran Roppongi'},
      ], exclude: 'Ichiran');
      expect(alts.map((a) => a.name), [
        'Ichiran Shibuya',
        'Ichiran Shinjuku',
        'Ichiran Ueno',
      ]);
      expect(alts.first.subtitle, 'Shibuya');
      expect(PlaceExtractor.parseAlternatives('nope'), isEmpty);
    });
  });

  group('PlaceExtractor.extractAll', () {
    PlaceExtractor build(
      Map<String, Object?> geminiJson, {
      List<List<Map<String, String>>> geocodeReplies = const [],
      ExtractionCache? cache,
      Future<PostMetadata?> Function(Uri)? metadataFetcher,
      void Function(http.Request)? onGemini,
      List<Duration>? delays,
    }) {
      var geocodeCall = 0;
      return PlaceExtractor(
        gemini: GeminiService(
          apiKey: 'test-key',
          client: MockClient((req) async {
            onGemini?.call(req);
            return _geminiResponse(geminiJson);
          }),
        ),
        geocoder: GeocodingService(
          client: MockClient((req) async {
            final reply = geocodeCall < geocodeReplies.length
                ? geocodeReplies[geocodeCall]
                : const <Map<String, String>>[];
            geocodeCall++;
            return http.Response(jsonEncode(reply), 200);
          }),
        ),
        metadataFetcher: metadataFetcher ?? (uri) async => null,
        cache: cache ?? MemoryExtractionCache(),
        delay: (d) async => delays?.add(d),
      );
    }

    test(
      'single place: one confident result, no confirmation needed',
      () async {
        final result = await build({
          'places': [
            {'name': 'Ramen Bon', 'latitude': 35.7, 'longitude': 139.7},
          ],
        }).extractAll('Ramen Bon in Ikebukuro is great');
        expect(result.places, hasLength(1));
        expect(result.places.single.place.name, 'Ramen Bon');
        expect(result.places.single.needsConfirmation, isFalse);
      },
    );

    test('multi-place post returns every place, geocoding each with a '
        'Nominatim-friendly gap', () async {
      final delays = <Duration>[];
      final result = await build(
        {
          'places': [
            {'name': 'Cafe A', 'address': '1 A St', 'category': 'cafe'},
            {'name': 'Cafe B', 'address': '2 B St', 'category': 'cafe'},
            {'name': 'Shrine C', 'latitude': 35.0, 'longitude': 135.7},
            {'name': '', 'address': ''}, // placeholder — dropped
          ],
        },
        geocodeReplies: [
          [
            {'lat': '35.01', 'lon': '135.76'},
          ],
          [
            {'lat': '35.02', 'lon': '135.77'},
          ],
        ],
        delays: delays,
      ).extractAll('Top 3 in Kyoto: Cafe A, Cafe B, Shrine C');
      expect(result.places.map((p) => p.place.name), [
        'Cafe A',
        'Cafe B',
        'Shrine C',
      ]);
      expect(result.places[1].place.location, const LatLng(35.02, 135.77));
      expect(result.places[2].place.category, PlaceCategory.food);
      // Unique ids even within one extraction.
      expect(result.places.map((p) => p.place.id).toSet(), hasLength(3));
      // Second geocode waited (first doesn't; Shrine C had coords).
      expect(delays, hasLength(1));
      expect(delays.single, lessThanOrEqualTo(const Duration(seconds: 1)));
    });

    test('low confidence with alternatives needs confirmation', () async {
      final result = await build({
        'places': [
          {
            'name': 'Ichiran',
            'latitude': 35.66,
            'longitude': 139.70,
            'confidence': 0.4,
            'alternatives': [
              {'name': 'Ichiran Shibuya', 'region': 'Tokyo, Japan'},
              {'name': 'Ichiran Shinjuku', 'region': 'Tokyo, Japan'},
            ],
          },
        ],
      }).extractAll('ramen at ichiran');
      final item = result.places.single;
      expect(item.confidence, 0.4);
      expect(item.needsConfirmation, isTrue);
      expect(item.alternatives.map((a) => a.name), [
        'Ichiran Shibuya',
        'Ichiran Shinjuku',
      ]);
    });

    test('confident name but ambiguous geocode needs confirmation', () async {
      final result = await build(
        {
          'places': [
            {'name': 'Blue Bottle', 'region': 'Japan', 'confidence': 0.9},
          ],
        },
        geocodeReplies: [
          [
            {'lat': '35.66', 'lon': '139.70', 'display_name': 'Shibuya'},
            {'lat': '35.0', 'lon': '135.77', 'display_name': 'Kyoto'},
          ],
        ],
      ).extractAll('blue bottle coffee');
      final item = result.places.single;
      expect(item.geocodeAmbiguous, isTrue);
      expect(item.needsConfirmation, isTrue);
      expect(item.geocodeCandidates.map((c) => c.displayName), [
        'Shibuya',
        'Kyoto',
      ]);
    });

    test('nearby duplicate geocode hits are not ambiguous', () async {
      final result = await build(
        {
          'places': [
            {'name': 'Gogo', 'address': '1 Ikebukuro'},
          ],
        },
        geocodeReplies: [
          [
            {'lat': '35.7300', 'lon': '139.7100'},
            {'lat': '35.7301', 'lon': '139.7101'},
          ],
        ],
      ).extractAll('gogo');
      expect(result.places.single.needsConfirmation, isFalse);
    });

    test('resolveAlternative geocodes the picked alternative', () async {
      final extractor = build(
        {
          'places': [
            {
              'name': 'Ichiran',
              'latitude': 35.66,
              'longitude': 139.70,
              'confidence': 0.3,
              'alternatives': [
                {'name': 'Ichiran Ueno', 'areaLabel': 'Ueno'},
              ],
            },
          ],
        },
        geocodeReplies: [
          [
            {'lat': '35.71', 'lon': '139.77'},
          ],
        ],
      );
      final item = (await extractor.extractAll('ichiran')).places.single;
      final picked = await extractor.resolveAlternative(
        item,
        item.alternatives.single,
      );
      expect(picked!.name, 'Ichiran Ueno');
      expect(picked.areaLabel, 'Ueno');
      expect(picked.location, const LatLng(35.71, 139.77));
      expect(picked.matchConfident, isTrue);
    });

    test('empty places list throws NoPlaceFoundException', () async {
      await expectLater(
        build({'places': []}).extractAll('just vibes'),
        throwsA(isA<NoPlaceFoundException>()),
      );
    });

    test('a bare post URL is cached per normalized URL: the second share '
        'skips the caption fetch and Gemini', () async {
      final cache = MemoryExtractionCache();
      var geminiCalls = 0;
      var metaCalls = 0;
      PlaceExtractor make() => build(
        {
          'places': [
            {'name': 'Ramen Bon', 'latitude': 35.7, 'longitude': 139.7},
          ],
        },
        cache: cache,
        onGemini: (_) => geminiCalls++,
        metadataFetcher: (uri) async {
          metaCalls++;
          return const PostMetadata(
            title: 'Bon on Instagram: "Best ramen"',
            author: '@bon',
          );
        },
      );
      await make().extractAll('https://www.instagram.com/reel/abc123/?igsh=x');
      final again = await make().extractAll('https://instagram.com/p/abc123');
      expect(geminiCalls, 1);
      expect(metaCalls, 1);
      expect(again.places.single.place.name, 'Ramen Bon');
      expect(again.places.single.place.sourceHandle, '@bon');
      expect(again.places.single.place.originalCaption, 'Best ramen');
      expect(cache.entries.keys, ['https://instagram.com/p/abc123']);
    });

    test('URL plus pasted caption is not cached', () async {
      final cache = MemoryExtractionCache();
      await build({
        'name': 'Ramen Bon',
        'latitude': 35.7,
        'longitude': 139.7,
      }, cache: cache).extractAll('https://www.instagram.com/p/abc/ caption');
      expect(cache.entries, isEmpty);
    });

    test('extractFromImage sends the prompt plus an inline image', () async {
      Map<String, dynamic>? body;
      final result =
          await build(
            {
              'places': [
                {'name': 'Shot Cafe', 'latitude': 1.3, 'longitude': 103.8},
              ],
            },
            onGemini: (req) =>
                body = jsonDecode(req.body) as Map<String, dynamic>,
          ).extractFromImage(
            Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/png',
            hint: 'https://www.tiktok.com/@a/video/1',
          );
      final parts = body!['contents'][0]['parts'] as List;
      expect(parts[0]['text'], contains('attached screenshot'));
      expect(parts[1]['inline_data']['mime_type'], 'image/png');
      expect(parts[1]['inline_data']['data'], base64Encode([1, 2, 3]));
      expect(body!['generationConfig']['temperature'], 0);
      expect(result.places.single.place.name, 'Shot Cafe');
      expect(result.places.single.place.sourcePlatform, SourcePlatform.tiktok);
    });
  });
}
