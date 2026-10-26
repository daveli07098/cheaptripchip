import 'place.dart';

/// Bump whenever [_detectionOrder] or [_refines] changes in a way that
/// should re-run the one-off refinement rescan over stored automatic types
/// ([refinedRestaurantType] / PlaceStore.rescanRestaurantTypes). Unset
/// places never need it — their guess is re-derived at read time.
const int restaurantTypeDetectionVersion = 2;

/// Keyword-based fallback for [Place.effectiveRestaurantType]: guesses a
/// [RestaurantType] from a restaurant's own text (name/description/original
/// caption/address/the user's notes) when nobody — neither the user via the detail-sheet
/// picker, nor AI extraction — has set [Place.restaurantType] yet. Pure
/// and read-only: never writes back to the place, so unset places need no
/// migration when the keyword list changes; it's just re-derived every time
/// [Place.effectiveRestaurantType] is read. (Stored automatic types are
/// refined separately — see [refinedRestaurantType].)
///
/// Matching is case-insensitive (haystack is lower-cased; keyword literals
/// below are already lower-case for the ASCII entries — CJK has no case).
/// Latin keywords match whole words only (an optional plural "s"/"es" is
/// allowed), so "pho" doesn't fire on "photo" nor "udon" on "Pudong"; CJK
/// keywords are plain substrings. Known false friends ("french fries",
/// "french toast", …) are blanked out first.
///
/// The name is checked on its own first — "Sushi Saito" is sushi even if
/// its description mentions tempura — then all the text together.
/// [_detectionOrder] is checked top to bottom and the first hit wins, so
/// it's ordered specific → generic: e.g. text mentioning both "ramen" and
/// "udon" on the menu detects as ramen, "中華そば" is ramen before it can
/// read as soba, "天丼"/"カツ丼" are tempura/tonkatsu before the generic 丼
/// bowl, cuisines come before fine-dining/bakery/dessert cues, and the
/// generic [RestaurantType.western]/[RestaurantType.japanese] buckets are
/// last.
///
/// Returns `null` for non-restaurants or when nothing matches (the caller,
/// [Place.effectiveRestaurantType], falls back to [RestaurantType.other]).
RestaurantType? detectRestaurantType(Place place) {
  if (place.category != PlaceCategory.restaurant) return null;

  final all = [
    place.name,
    place.descriptionEn,
    place.originalCaption,
    place.address,
    // The user's own notes — e.g. "Cat: Ramen" from a My Maps import.
    place.myNotes,
  ].join('\n');
  return _match(place.name) ?? _match(all);
}

/// The type the one-off rescan should store for [place] instead of its
/// current automatic [Place.restaurantType], or `null` to leave it as is.
///
/// Only ever *refines*: a stored [RestaurantType.other], or a stored generic
/// bucket that a newer, more specific type was split out of (e.g.
/// [RestaurantType.japanese] → [RestaurantType.udonSoba], see [_refines]),
/// is replaced by the keyword-detected type. Never touches a manual pick
/// ([Place.restaurantTypeManual]), an unset type (already re-derived at read
/// time), or a stored specific type that detection merely disagrees with —
/// the AI's pick is trusted over keywords there.
RestaurantType? refinedRestaurantType(Place place) {
  final stored = place.restaurantType;
  if (place.category != PlaceCategory.restaurant ||
      place.restaurantTypeManual ||
      stored == null) {
    return null;
  }
  final detected = detectRestaurantType(place);
  if (detected == null || detected == stored) return null;
  if (stored == RestaurantType.other || _refines[detected] == stored) {
    return detected;
  }
  return null;
}

/// New type → the older, broader type its places used to be filed under
/// (by keyword detection, AI, or the user). Drives
/// [refinedRestaurantType].
const Map<RestaurantType, RestaurantType> _refines = {
  RestaurantType.udonSoba: RestaurantType.japanese,
  RestaurantType.tempura: RestaurantType.japanese,
  RestaurantType.tonkatsu: RestaurantType.japanese,
  RestaurantType.donburi: RestaurantType.japanese,
  RestaurantType.curry: RestaurantType.japanese,
  RestaurantType.okonomiyaki: RestaurantType.japanese,
  RestaurantType.yakitori: RestaurantType.izakaya,
  RestaurantType.italian: RestaurantType.western,
  RestaurantType.french: RestaurantType.western,
  RestaurantType.burger: RestaurantType.western,
};

RestaurantType? _match(String text) {
  var haystack = text.toLowerCase();
  for (final phrase in _falseFriends) {
    haystack = haystack.replaceAll(phrase, ' ');
  }
  for (final rule in _rules) {
    if (rule.matches(haystack)) return rule.type;
  }
  return null;
}

/// Phrases that contain a cuisine keyword but don't mean that cuisine.
const List<String> _falseFriends = [
  'french fries',
  'french toast',
  'フレンチトースト',
  'フレンチフライ',
  '法式多士',
  '法式吐司',
];

class _Rule {
  _Rule(this.type, List<String> keywords)
    : _cjk = [
        for (final k in keywords)
          if (!_latin.hasMatch(k)) k,
      ],
      _words = _wordPattern([
        for (final k in keywords)
          if (_latin.hasMatch(k)) k,
      ]);

  static final _latin = RegExp('[a-z]');

  /// Whole-word match for any of [keywords], optionally pluralized.
  static RegExp? _wordPattern(List<String> keywords) {
    if (keywords.isEmpty) return null;
    final alternatives = keywords.map(RegExp.escape).join('|');
    return RegExp('(?<![a-z0-9])(?:$alternatives)(?:e?s)?(?![a-z0-9])');
  }

  final RestaurantType type;
  final List<String> _cjk;
  final RegExp? _words;

  bool matches(String haystack) =>
      _cjk.any(haystack.contains) || (_words?.hasMatch(haystack) ?? false);
}

final List<_Rule> _rules = [
  for (final (type, keywords) in _detectionOrder) _Rule(type, keywords),
];

const List<(RestaurantType, List<String>)> _detectionOrder = [
  (
    RestaurantType.chaChaanTeng,
    [
      'cha chaan teng',
      'cha chan teng',
      'hong kong style cafe',
      'hk-style cafe',
      '茶餐廳',
      '茶餐厅',
      '冰室',
    ],
  ),
  (
    RestaurantType.dimsum,
    [
      'dim sum',
      'dimsum',
      'yum cha',
      'cantonese',
      'har gow',
      'siu mai',
      'roast goose',
      '點心',
      '点心',
      '飲茶',
      '饮茶',
      '粵菜',
      '粤菜',
      '蝦餃',
      '虾饺',
      '燒賣',
      '烧卖',
      '燒味',
      '烧味',
      '燒鵝',
      '烧鹅',
    ],
  ),
  (
    RestaurantType.hotpot,
    [
      'hot pot',
      'hotpot',
      'shabu',
      'sukiyaki',
      'motsunabe',
      'chanko',
      'nabe',
      '火鍋',
      '火锅',
      'しゃぶしゃぶ',
      'すき焼',
      'すきやき',
      '壽喜燒',
      '寿喜烧',
      '涮涮鍋',
      '涮涮锅',
      'もつ鍋',
      'ちゃんこ',
      '打邊爐',
      '打边炉',
      '麻辣燙',
      '麻辣烫',
    ],
  ),
  (
    RestaurantType.okonomiyaki,
    [
      'okonomiyaki',
      'takoyaki',
      'monjayaki',
      'monja',
      'yakisoba',
      'お好み焼',
      'たこ焼',
      'もんじゃ',
      '焼きそば',
      '焼そば',
      '大阪燒',
      '大阪烧',
      '御好燒',
      '章魚燒',
      '章鱼烧',
      '章魚小丸子',
    ],
  ),
  (
    RestaurantType.yakitori,
    [
      'yakitori',
      'kushikatsu',
      'kushiage',
      'kushiyaki',
      'skewer',
      '焼鳥',
      '焼き鳥',
      'やきとり',
      '燒鳥',
      '烧鸟',
      '串燒',
      '串烧',
      '串カツ',
      '串かつ',
      '串揚げ',
      '烤雞串',
    ],
  ),
  // Before yakiniku, so "Korean BBQ" reads as Korean.
  (
    RestaurantType.korean,
    [
      'korean',
      'bibimbap',
      'bulgogi',
      'samgyeopsal',
      'tteokbokki',
      'jjigae',
      'samgyetang',
      'kimbap',
      'gimbap',
      '韓國',
      '韩国',
      '韓国',
      '韓式',
      '韩式',
      'サムギョプサル',
      '石鍋拌飯',
      '部隊鍋',
      '部队锅',
      '參雞湯',
      '参鸡汤',
    ],
  ),
  (
    RestaurantType.yakiniku,
    [
      'yakiniku',
      'bbq',
      'barbecue',
      'barbeque',
      'horumon',
      'jingisukan',
      '焼肉',
      '燒肉',
      '烧肉',
      '烤肉',
      'ホルモン',
      'ジンギスカン',
      '成吉思汗',
    ],
  ),
  (RestaurantType.izakaya, ['izakaya', 'tachinomi', '居酒屋', '立ち飲み']),
  (
    RestaurantType.sushi,
    [
      'sushi',
      'sashimi',
      'nigiri',
      'kaitenzushi',
      '壽司',
      '寿司',
      '鮨',
      '刺身',
      'すし',
      'スシ',
    ],
  ),
  // Before udon/soba: 中華そば, まぜそば and 油そば are ramen.
  (
    RestaurantType.ramen,
    [
      'ramen',
      'tsukemen',
      'tonkotsu',
      'mazesoba',
      'abura soba',
      'aburasoba',
      'chuka soba',
      'chukasoba',
      'tantanmen',
      'ラーメン',
      'らーめん',
      'らあめん',
      '拉麵',
      '拉面',
      'つけ麺',
      '沾麵',
      '沾面',
      '中華そば',
      'まぜそば',
      '油そば',
      '担々麺',
      '擔擔麵',
      '豚骨',
    ],
  ),
  (
    RestaurantType.udonSoba,
    [
      'udon',
      'soba',
      'kishimen',
      'うどん',
      'ウドン',
      'そば',
      '蕎麦',
      '蕎麥',
      '荞麦',
      '烏冬',
      '乌冬',
      '烏龍麵',
      '乌龙面',
      'きしめん',
    ],
  ),
  (
    RestaurantType.tonkatsu,
    [
      'tonkatsu',
      'katsu',
      'katsudon',
      'とんかつ',
      'トンカツ',
      '豚カツ',
      'カツ丼',
      'かつ丼',
      '炸豬排',
      '炸猪排',
      '吉列豬扒',
      '吉列猪扒',
    ],
  ),
  (RestaurantType.tempura, ['tempura', '天ぷら', '天麩羅', '天婦羅', '天妇罗', '天丼']),
  // After tempura/tonkatsu so 天丼/カツ丼 don't land on the generic bowl.
  (
    RestaurantType.donburi,
    [
      'donburi',
      'unagi',
      'unadon',
      'unaju',
      'hitsumabushi',
      'kaisendon',
      'gyudon',
      'oyakodon',
      'butadon',
      '鰻',
      '鳗',
      'うなぎ',
      'ウナギ',
      'ひつまぶし',
      '丼',
    ],
  ),
  (
    RestaurantType.thai,
    [
      'thai',
      'tom yum',
      'tom yam',
      'som tam',
      'khao soi',
      '泰式',
      '泰國',
      '泰国',
      'タイ料理',
      'ガパオ',
      '冬蔭功',
      '冬阴功',
    ],
  ),
  (
    RestaurantType.vietnamese,
    [
      'vietnamese',
      'pho',
      'phở',
      'banh mi',
      'bánh mì',
      'bun cha',
      'bún chả',
      '越南',
      '越式',
      'ベトナム',
      'バインミー',
    ],
  ),
  // Before curry: an Indian curry house is Indian.
  (
    RestaurantType.indian,
    [
      'indian',
      'naan',
      'tandoori',
      'biryani',
      'masala',
      'dosa',
      'nepali',
      'nepalese',
      'インド',
      '印度',
    ],
  ),
  (
    RestaurantType.chinese,
    [
      'chinese',
      'sichuan',
      'szechuan',
      'shanghainese',
      'xiaolongbao',
      'dumpling',
      'peking duck',
      'taiwanese',
      'mala',
      'beef noodle',
      '中華料理',
      '中国料理',
      '中菜',
      '中餐',
      '中式',
      '川菜',
      '四川料理',
      '上海菜',
      '小籠包',
      '小笼包',
      '北京烤鴨',
      '北京烤鸭',
      '麻辣',
      '台菜',
      '台式',
      '牛肉麵',
      '牛肉面',
      '滷肉飯',
      '卤肉饭',
      '湘菜',
    ],
  ),
  (RestaurantType.curry, ['curry', 'カレー', '咖喱', '咖哩']),
  // Before italian/french/western: a burger joint's menu often mentions
  // steak, pasta or a bistro vibe too.
  (
    RestaurantType.burger,
    ['burger', 'hamburger', 'cheeseburger', 'ハンバーガー', 'バーガー', '漢堡', '汉堡'],
  ),
  (
    RestaurantType.italian,
    [
      'italian',
      'pizza',
      'pizzeria',
      'pasta',
      'trattoria',
      'osteria',
      'ristorante',
      'risotto',
      'spaghetti',
      'carbonara',
      'イタリアン',
      'イタリア料理',
      'ピザ',
      'ピッツァ',
      'パスタ',
      '意大利',
      '義大利',
      '意式',
      '義式',
      '意粉',
    ],
  ),
  (
    RestaurantType.french,
    [
      'french',
      'bistro',
      'bistrot',
      'brasserie',
      'フレンチ',
      'フランス料理',
      'ビストロ',
      '法國',
      '法国',
      '法式',
    ],
  ),
  (
    RestaurantType.seafood,
    [
      'seafood',
      'oyster',
      'crab',
      'lobster',
      'fish market',
      '海鮮',
      '海鲜',
      '生蠔',
      '生蚝',
      '牡蠣',
      '蟹',
      '龍蝦',
      '龙虾',
    ],
  ),
  (
    RestaurantType.fineDining,
    [
      'omakase',
      'fine dining',
      'fine-dining',
      'michelin',
      'tasting menu',
      'degustation',
      'kaiseki',
      'kappo',
      '米芝蓮',
      '米其林',
      'ミシュラン',
      '懐石',
      '懷石',
      '怀石',
      '会席',
      '割烹',
      'おまかせ',
    ],
  ),
  (
    RestaurantType.bakery,
    [
      'bakery',
      'bakeries',
      'boulangerie',
      'croissant',
      'bagel',
      'sourdough',
      'ベーカリー',
      'パン屋',
      'ブーランジェリー',
      '麵包',
      '面包',
      '餅店',
      '饼店',
      '烘焙',
    ],
  ),
  (
    RestaurantType.dessert,
    [
      'dessert',
      'patisserie',
      'pâtisserie',
      'gelato',
      'ice cream',
      'soft serve',
      'parfait',
      'kakigori',
      'shaved ice',
      'crepe',
      'crêpe',
      'pancake',
      'cheesecake',
      'cake shop',
      'wagashi',
      'sweets',
      'パティスリー',
      'パフェ',
      'かき氷',
      'スイーツ',
      'ケーキ',
      'クレープ',
      'パンケーキ',
      '和菓子',
      '甜品',
      '甜點',
      '甜点',
      '糖水',
      '刨冰',
      '蛋糕',
      '豆花',
    ],
  ),
  (
    RestaurantType.bar,
    [
      'wine bar',
      'sake bar',
      'cocktail',
      'pub',
      'gastropub',
      'speakeasy',
      'taproom',
      'brewery',
      'craft beer',
      'whisky',
      'whiskey',
      '酒吧',
      '酒館',
      '酒馆',
      'ワインバー',
    ],
  ),
  (
    RestaurantType.western,
    [
      'western',
      'steak',
      'steakhouse',
      'grill',
      'yoshoku',
      'omurice',
      'brunch',
      '西餐',
      '西式',
      '洋食',
      'ステーキ',
      'ハンバーグ',
      'オムライス',
      '牛扒',
      '扒房',
      '蛋包飯',
    ],
  ),
  (
    RestaurantType.japanese,
    [
      'japanese',
      'washoku',
      'teishoku',
      'onigiri',
      '和食',
      '日本料理',
      '日式',
      '日料',
      '定食',
      'おにぎり',
    ],
  ),
];
