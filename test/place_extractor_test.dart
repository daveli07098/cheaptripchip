import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/services/place_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
