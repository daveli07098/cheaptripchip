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
        RestaurantType.italian,
      );
      expect(
        detectRestaurantType(
          _restaurant(descriptionEn: 'Crispy tonkatsu set meal'),
        ),
        RestaurantType.tonkatsu,
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
        RestaurantType.udonSoba,
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

    test('detects every newer sub-type in English', () {
      const cases = {
        'Hand-cut soba and tempura': RestaurantType.udonSoba,
        'Crispy tempura counter': RestaurantType.tempura,
        'Grilled unagi over rice': RestaurantType.donburi,
        'Hokkaido soup curry': RestaurantType.curry,
        'Osaka okonomiyaki and takoyaki': RestaurantType.okonomiyaki,
        'Smoky yakitori skewers': RestaurantType.yakitori,
        'Sichuan mala and xiaolongbao': RestaurantType.chinese,
        'Taiwanese beef noodle soup': RestaurantType.chinese,
        'Spicy tom yum and pad thai': RestaurantType.thai,
        'A steaming bowl of pho': RestaurantType.vietnamese,
        'Tandoori chicken and garlic naan': RestaurantType.indian,
        'Classic French bistro': RestaurantType.french,
        'Juicy smash burgers': RestaurantType.burger,
        'Fresh oysters and lobster': RestaurantType.seafood,
        'Neighbourhood bakery with sourdough': RestaurantType.bakery,
        'Matcha parfait and kakigori': RestaurantType.dessert,
        'Cocktail bar with a speakeasy door': RestaurantType.bar,
        'Dry-aged steakhouse': RestaurantType.western,
        'Traditional washoku set': RestaurantType.japanese,
      };
      for (final entry in cases.entries) {
        expect(
          detectRestaurantType(_restaurant(descriptionEn: entry.key)),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('detects every newer sub-type in Japanese and Chinese', () {
      const cases = {
        '老舗の蕎麦屋': RestaurantType.udonSoba,
        '讚岐烏冬專門店': RestaurantType.udonSoba,
        '江戸前天ぷら': RestaurantType.tempura,
        '天婦羅定食': RestaurantType.tempura,
        'ロースかつ丼': RestaurantType.tonkatsu,
        '炸豬排飯': RestaurantType.tonkatsu,
        '鰻魚飯老店': RestaurantType.donburi,
        '海鮮丼': RestaurantType.donburi,
        '欧風カレー': RestaurantType.curry,
        '日式咖喱飯': RestaurantType.curry,
        'お好み焼き 鉄板': RestaurantType.okonomiyaki,
        '章魚燒小店': RestaurantType.okonomiyaki,
        '炭火焼き鳥': RestaurantType.yakitori,
        '日式串燒': RestaurantType.yakitori,
        '町中華の中華料理': RestaurantType.chinese,
        '台式滷肉飯': RestaurantType.chinese,
        '泰式船麵': RestaurantType.thai,
        '越南河粉': RestaurantType.vietnamese,
        '本格インドカレー': RestaurantType.indian,
        '意大利薄餅': RestaurantType.italian,
        'ナポリピッツァ': RestaurantType.italian,
        'フレンチビストロ': RestaurantType.french,
        '法國菜': RestaurantType.french,
        '手作漢堡': RestaurantType.burger,
        '生蠔吧': RestaurantType.seafood,
        '人氣麵包店': RestaurantType.bakery,
        '港式糖水': RestaurantType.dessert,
        '宇治抹茶パフェ': RestaurantType.dessert,
        '隱世酒吧': RestaurantType.bar,
        '懷舊扒房': RestaurantType.western,
        'ふわとろオムライス': RestaurantType.western,
        '懐石料理': RestaurantType.fineDining,
        '家庭的な和食': RestaurantType.japanese,
      };
      for (final entry in cases.entries) {
        expect(
          detectRestaurantType(_restaurant(descriptionEn: entry.key)),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('priority: specific beats generic', () {
      const cases = {
        // Ramen over its soup/noodle cues and over soba.
        'Rich tonkotsu ramen': RestaurantType.ramen,
        '東京の中華そば': RestaurantType.ramen,
        'まぜそば専門店': RestaurantType.ramen,
        // Yakisoba is teppan food, not soba.
        'Okonomiyaki and yakisoba': RestaurantType.okonomiyaki,
        '焼きそば屋台': RestaurantType.okonomiyaki,
        // Tempura/katsu bowls before the generic 丼.
        '天丼てんや': RestaurantType.tempura,
        'カツ丼専門': RestaurantType.tonkatsu,
        // Korean BBQ is Korean, not yakiniku.
        'Korean BBQ samgyeopsal': RestaurantType.korean,
        // Indian / Thai curry before the generic curry.
        'Indian butter chicken curry': RestaurantType.indian,
        'Thai green curry': RestaurantType.thai,
        // Kushikatsu is yakitori-style, not tonkatsu.
        'Osaka kushikatsu stand': RestaurantType.yakitori,
        // A named cuisine beats fine-dining cues.
        'Michelin-starred French restaurant': RestaurantType.french,
        'Omakase sushi counter': RestaurantType.sushi,
        // Italian gelato is Italian; plain gelato is dessert.
        'Italian trattoria with gelato': RestaurantType.italian,
      };
      for (final entry in cases.entries) {
        expect(
          detectRestaurantType(_restaurant(descriptionEn: entry.key)),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('the name wins over dishes mentioned in the description', () {
      final place = _restaurant(
        name: 'Sushi Saito',
        descriptionEn: 'Also serves tempura and udon.',
      );
      expect(detectRestaurantType(place), RestaurantType.sushi);
    });

    test('latin keywords match whole words, not substrings', () {
      const misses = [
        'Great photo spot', // pho
        'Near Pudong airport', // udon
        'Public square', // pub
        'Southwestern decor', // western
        'Thailand trip', // thai
      ];
      for (final text in misses) {
        expect(
          detectRestaurantType(_restaurant(descriptionEn: text)),
          isNull,
          reason: text,
        );
      }
    });

    test('false friends are ignored', () {
      expect(
        detectRestaurantType(_restaurant(descriptionEn: 'Crispy french fries')),
        isNull,
      );
      expect(
        detectRestaurantType(_restaurant(descriptionEn: '招牌法式多士')),
        isNull,
      );
    });

    test('matches dim sum from "cantonese"/"dim sum" without misfiring', () {
      final place = _restaurant(
        descriptionEn: 'Cantonese roast meats and dim sum',
      );
      expect(detectRestaurantType(place), RestaurantType.dimsum);
    });
  });

  group('refinedRestaurantType', () {
    final udonShop = _restaurant(name: 'Udon Shin');

    test('refines a stored generic bucket into the split-out type', () {
      expect(
        refinedRestaurantType(
          udonShop.copyWith(restaurantType: RestaurantType.japanese),
        ),
        RestaurantType.udonSoba,
      );
      expect(
        refinedRestaurantType(
          _restaurant(
            name: 'Torikizoku',
            descriptionEn: 'Cheap yakitori',
          ).copyWith(restaurantType: RestaurantType.izakaya),
        ),
        RestaurantType.yakitori,
      );
      expect(
        refinedRestaurantType(
          _restaurant(
            name: 'Pizzeria Mario',
          ).copyWith(restaurantType: RestaurantType.western),
        ),
        RestaurantType.italian,
      );
    });

    test('replaces a stored Other with any detected type', () {
      expect(
        refinedRestaurantType(
          _restaurant(
            name: 'Pho 24',
          ).copyWith(restaurantType: RestaurantType.other),
        ),
        RestaurantType.vietnamese,
      );
    });

    test('never touches a manual pick', () {
      expect(
        refinedRestaurantType(
          udonShop.copyWith(
            restaurantType: RestaurantType.japanese,
            restaurantTypeManual: true,
          ),
        ),
        isNull,
      );
    });

    test('leaves unset, matching and unrelated stored types alone', () {
      // Unset: detection already applies at read time.
      expect(refinedRestaurantType(udonShop), isNull);
      // Already the detected type.
      expect(
        refinedRestaurantType(
          udonShop.copyWith(restaurantType: RestaurantType.udonSoba),
        ),
        isNull,
      );
      // A specific stored type (e.g. Gemini's) isn't overridden by keywords.
      expect(
        refinedRestaurantType(
          udonShop.copyWith(restaurantType: RestaurantType.ramen),
        ),
        isNull,
      );
      // Nothing detected.
      expect(
        refinedRestaurantType(
          _restaurant(
            name: 'Untitled',
          ).copyWith(restaurantType: RestaurantType.japanese),
        ),
        isNull,
      );
    });

    test('ignores non-restaurants', () {
      expect(
        refinedRestaurantType(
          udonShop.copyWith(
            category: PlaceCategory.cafe,
            restaurantType: RestaurantType.japanese,
          ),
        ),
        isNull,
      );
    });
  });
}
