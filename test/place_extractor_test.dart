import 'dart:convert';

import 'package:cheaptripchip/models/place.dart';
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
          'yakitori': RestaurantType.izakaya,
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
}
