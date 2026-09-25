import 'place.dart';

/// Keyword-based fallback for [Place.effectiveRestaurantType]: guesses a
/// [RestaurantType] from a restaurant's own text (name/description/original
/// caption/address/the user's notes) when nobody — neither the user via the detail-sheet
/// picker, nor Gemini extraction — has set [Place.restaurantType] yet. Pure
/// and read-only: never writes back to the place, so there's nothing to
/// migrate when the keyword list changes; it's just re-derived every time
/// [Place.effectiveRestaurantType] is read.
///
/// Matching is a case-insensitive substring check (haystack is lower-cased;
/// keyword literals below are already lower-case for the ASCII entries — CJK
/// has no case). [_detectionOrder] is checked top to bottom and the first hit
/// wins, so it's ordered specific → generic: named dish/style keywords
/// (ramen, sushi, izakaya, yakiniku, hot pot, dim sum, cha chaan teng,
/// korean, fine-dining cues) are checked before [RestaurantType.japanese],
/// the generic "other Japanese dish" bucket (udon/soba/tempura/tonkatsu/
/// unagi/donburi) — e.g. text mentioning both "ramen" and "udon" on the menu
/// should detect as ramen, the more specific type, not generic Japanese.
///
/// Returns `null` for non-restaurants or when nothing matches (the caller,
/// [Place.effectiveRestaurantType], falls back to [RestaurantType.other]).
RestaurantType? detectRestaurantType(Place place) {
  if (place.category != PlaceCategory.restaurant) return null;

  final haystack = [
    place.name,
    place.descriptionEn,
    place.originalCaption,
    place.address,
    // The user's own notes — e.g. "Cat: Ramen" from a My Maps import.
    place.myNotes,
  ].join('\n').toLowerCase();

  for (final (type, keywords) in _detectionOrder) {
    for (final keyword in keywords) {
      if (haystack.contains(keyword)) return type;
    }
  }
  return null;
}

const List<(RestaurantType, List<String>)> _detectionOrder = [
  (RestaurantType.chaChaanTeng, ['cha chaan teng', '茶餐廳', '茶餐厅']),
  (
    RestaurantType.dimsum,
    ['dim sum', 'dimsum', '點心', '点心', '飲茶', '饮茶', 'cantonese', '粵菜', '粤菜'],
  ),
  (
    RestaurantType.hotpot,
    ['hot pot', 'hotpot', '火鍋', '火锅', 'shabu', 'しゃぶしゃぶ', 'sukiyaki'],
  ),
  (RestaurantType.yakiniku, ['yakiniku', 'bbq', '燒肉', '焼肉', '烤肉']),
  (RestaurantType.izakaya, ['izakaya', '居酒屋', 'yakitori', '焼鳥', '燒鳥']),
  (RestaurantType.sushi, ['sushi', 'sashimi', '壽司', '寿司', '刺身', '鮨']),
  (RestaurantType.ramen, ['ramen', '拉麵', '拉面', 'ラーメン']),
  (RestaurantType.korean, ['korean', '韓國', '韩国', '韓国', 'bibimbap']),
  (
    RestaurantType.fineDining,
    ['omakase', 'fine dining', 'michelin', '米芝蓮', 'kaiseki', '懐石'],
  ),
  (
    RestaurantType.western,
    ['pasta', 'pizza', 'steak', 'western', '西餐', 'burger'],
  ),
  (
    RestaurantType.japanese,
    [
      'tempura',
      '天ぷら',
      'udon',
      'うどん',
      'soba',
      '蕎麦',
      'tonkatsu',
      'とんかつ',
      'unagi',
      '鰻',
      'donburi',
      '丼',
    ],
  ),
];
