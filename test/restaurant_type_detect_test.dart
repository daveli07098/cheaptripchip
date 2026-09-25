import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/restaurant_type_detect.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _restaurant({
  String name = '',
  String descriptionEn = '',
  String originalCaption = '',
  String address = '',
}) {
  return Place(
    id: 'p',
    name: name,
    areaLabel: '',
    region: '',
    category: PlaceCategory.restaurant,
    location: const LatLng(0, 0),
    descriptionEn: descriptionEn,
    originalCaption: originalCaption,
    address: address,
    hours: '',
    sourceHandle: '',
    sourcePlatform: SourcePlatform.instagram,
  );
}

void main() {
  group('detectRestaurantType', () {
    test('returns null for a non-restaurant category, whatever the text', () {
      final cafe = _restaurant(
        descriptionEn: 'Best ramen in town',
      ).copyWith(category: PlaceCategory.cafe);
      expect(detectRestaurantType(cafe), isNull);
    });

    test('returns null when nothing in the text matches a keyword', () {
      final place = _restaurant(
        name: 'Untitled',
        descriptionEn: 'A lovely place to eat with friends.',
      );
      expect(detectRestaurantType(place), isNull);
    });

    test("reads the user's notes (e.g. imported from My Maps)", () {
      final place = _restaurant(
        name: 'Menya Honda',
      ).copyWith(myNotes: 'Cat: Ramen\n評分: 4/5');
      expect(detectRestaurantType(place), RestaurantType.ramen);
      expect(place.effectiveRestaurantType, RestaurantType.ramen);
    });

    test('matches English keywords across name/description/address', () {
      expect(
        detectRestaurantType(_restaurant(descriptionEn: 'Best ramen in town')),
        RestaurantType.ramen,
      );
      expect(
        detectRestaurantType(_restaurant(name: 'Sushi & Sashimi House')),
        RestaurantType.sushi,
      );
      expect(
        detectRestaurantType(
          _restaurant(descriptionEn: 'Classic izakaya vibes'),
        ),
        RestaurantType.izakaya,
      );
      expect(
        detectRestaurantType(
          _restaurant(descriptionEn: 'All-you-can-eat yakiniku'),
        ),
        RestaurantType.yakiniku,
      );
      expect(
        detectRestaurantType(
          _restaurant(descriptionEn: 'Steamy hot pot for winter'),
        ),
        RestaurantType.hotpot,
      );
      expect(
        detectRestaurantType(
          _restaurant(descriptionEn: 'Cantonese dim sum brunch'),
        ),
        RestaurantType.dimsum,
      );
      expect(
        detectRestaurantType(_restaurant(name: 'Golden Cha Chaan Teng')),
        RestaurantType.chaChaanTeng,
      );
      expect(
        detectRestaurantType(
          _restaurant(descriptionEn: 'Korean bibimbap bowls'),
        ),
        RestaurantType.korean,
      );
      expect(
        detectRestaurantType(
          _restaurant(descriptionEn: 'An omakase tasting counter'),
        ),
        RestaurantType.fineDining,
      );
      expect(
        detectRestaurantType(
          _restaurant(descriptionEn: 'Wood-fired pizza and pasta'),
        ),
        RestaurantType.western,
      );
      expect(
        detectRestaurantType(
          _restaurant(descriptionEn: 'Crispy tonkatsu set meal'),
        ),
        RestaurantType.japanese,
      );
    });

    test('matches Traditional/Simplified Chinese and Japanese keywords', () {
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '正宗拉麵，濃厚豚骨湯頭')),
        RestaurantType.ramen,
      );
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '拉面很好吃')),
        RestaurantType.ramen,
      );
      expect(
        detectRestaurantType(_restaurant(name: '鮨 一之瀬')),
        RestaurantType.sushi,
      );
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '居酒屋，深夜營業')),
        RestaurantType.izakaya,
      );
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '燒肉放題')),
        RestaurantType.yakiniku,
      );
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '正宗火鍋店')),
        RestaurantType.hotpot,
      );
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '粵菜點心專門店')),
        RestaurantType.dimsum,
      );
      expect(
        detectRestaurantType(_restaurant(name: '老字號茶餐廳')),
        RestaurantType.chaChaanTeng,
      );
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '道地韓國料理')),
        RestaurantType.korean,
      );
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '米芝蓮一星懷石料理')),
        RestaurantType.fineDining,
      );
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '手打うどん専門店')),
        RestaurantType.japanese,
      );
    });

    test(
      'priority: a more specific type wins over the generic Japanese bucket',
      () {
        // Mentions both "ramen" (specific) and "udon"/"tonkatsu" (generic
        // Japanese) — the specific type should win because it's checked first.
        final place = _restaurant(
          descriptionEn: 'Famous for ramen, also serves udon and tonkatsu.',
        );
        expect(detectRestaurantType(place), RestaurantType.ramen);
      },
    );

    test('matches dim sum from "cantonese"/"dim sum" without misfiring', () {
      final place = _restaurant(
        descriptionEn: 'Cantonese roast meats and dim sum',
      );
      expect(detectRestaurantType(place), RestaurantType.dimsum);
    });
  });
}
