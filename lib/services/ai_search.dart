import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../data/map_filter.dart';
import '../data/place_search.dart';
import '../models/place.dart';
import 'ai_service.dart';

/// "Ask your places": natural-language search over the user's saved places.
///
/// [AiSearch.ask] sends the question plus a compact index of the places
/// ([buildAskPrompt]) to AI and validates the answer
/// ([parseAskResponse]: unknown ids are dropped). When AI isn't
/// configured, is offline, slow or returns garbage, [localAskSearch]
/// answers instead — keyword + category/sub-type synonym matching in
/// English, 中文 and 日本語, so plain words still work.

/// Most places sent to AI in one prompt; more are prefiltered locally.
const int kAskIndexCap = 300;

/// Most ranked ids kept from one answer (the prompt asks for ≤ 30).
const int kAskResultCap = 50;

/// Whether [query] reads like a question or sentence for "Ask" rather than
/// a plain name/area search: a question mark, a question word, a search
/// intent ("cheap", "near me", "rated 8+", 未去過…) or four-plus words.
bool looksLikeQuestion(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  if (q.endsWith('?') || q.endsWith('？')) return true;
  final words = q.split(RegExp(r'\s+'));
  if (words.length >= 4) return true;
  const starters = {
    'what',
    'where',
    'which',
    'who',
    'how',
    'any',
    'show',
    'find',
    'best',
    'recommend',
    'suggest',
    'somewhere',
    'places',
    'is',
    'are',
    'can',
    'should',
  };
  if (starters.contains(words.first)) return true;
  return _intentKeywords.any(q.contains) ||
      RegExp(r'\d\s*\+').hasMatch(q) ||
      _containsAny(q, _minScoreRated);
}

/// Words that signal "ask" by themselves (substring match, all languages).
// dart format off
const _intentKeywords = [
  'cheap', 'budget', 'near me', 'nearby', 'near here', 'late night',
  'late-night', 'favourite', 'favorite', 'not been', "haven't", 'haven’t',
  'never been', 'not visited', 'open now',
  '嗎', '呢', '邊度', '邊間', '哪', '什麼', '咩', '有冇', '有沒有', '推介', '推薦',
  '附近', '未去', '沒去', '便宜', '宵夜', '深夜',
  'どこ', 'おすすめ', '近く', '安い',
];
// dart format on

bool _containsAny(String s, Iterable<String> keys) => keys.any(s.contains);

bool _hasCjk(String s) => RegExp(r'[぀-ヿ㐀-鿿]').hasMatch(s);

/// A structured filter AI may return alongside (or instead of) ids, and
/// that the local fallback can express too. Every field is optional; a
/// place passes when it meets all of the set ones.
class AskFilter {
  const AskFilter({
    this.category,
    this.restaurantType,
    this.city,
    this.favoritesOnly = false,
    this.minScore,
    this.maxPriceLevel,
  });

  final PlaceCategory? category;
  final RestaurantType? restaurantType;
  final String? city;
  final bool favoritesOnly;

  /// The user's own score (1–10).
  final int? minScore;

  /// [PlaceDetails.priceLevel] (1–4); places without one don't pass.
  final int? maxPriceLevel;

  bool get isEmpty =>
      category == null &&
      restaurantType == null &&
      city == null &&
      !favoritesOnly &&
      minScore == null &&
      maxPriceLevel == null;

  bool matches(Place p) {
    if (category != null && p.category != category) return false;
    if (restaurantType != null && restaurantTypeOf(p) != restaurantType) {
      return false;
    }
    if (city != null && p.city.toLowerCase() != city!.toLowerCase()) {
      return false;
    }
    if (favoritesOnly && !p.isFavorite) return false;
    if (minScore != null && (p.myScore ?? 0) < minScore!) return false;
    if (maxPriceLevel != null) {
      final level = p.details?.priceLevel;
      if (level == null || level > maxPriceLevel!) return false;
    }
    return true;
  }

  /// Lenient: unknown enum names, wrong types and out-of-range numbers are
  /// ignored; null when nothing usable is left.
  static AskFilter? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    T? byName<T extends Enum>(List<T> values, dynamic name) {
      if (name is! String) return null;
      for (final v in values) {
        if (v.name.toLowerCase() == name.trim().toLowerCase()) return v;
      }
      return null;
    }

    int? intIn(dynamic v, int min, int max) {
      if (v is! num || !v.isFinite) return null;
      final i = v.round();
      return i < min || i > max ? null : i;
    }

    final city = raw['city'];
    final filter = AskFilter(
      category: byName(PlaceCategory.values, raw['category']),
      restaurantType: byName(RestaurantType.values, raw['restaurantType']),
      city: city is String && city.trim().isNotEmpty ? city.trim() : null,
      favoritesOnly: raw['favoritesOnly'] == true,
      minScore: intIn(raw['minScore'], 1, 10),
      maxPriceLevel: intIn(raw['maxPriceLevel'], 1, 4),
    );
    return filter.isEmpty ? null : filter;
  }
}

/// One answer to an "Ask" question.
class AskResult {
  const AskResult({
    required this.question,
    required this.placeIds,
    required this.explanation,
    this.filter,
    this.usedAi = false,
  });

  final String question;

  /// Ranked best-first; every id is one of the user's places.
  final List<String> placeIds;

  /// One short line, in the question's language (EN or 中文).
  final String explanation;

  final AskFilter? filter;

  /// False when the local keyword fallback answered.
  final bool usedAi;
}

/// Validates the AI's JSON answer against [places]: unknown and duplicate
/// ids are dropped (order kept), the explanation is trimmed (with a default
/// when missing), and a structured `filter` is applied locally when no ids
/// came back. Null when the answer has neither `placeIds` nor `filter` —
/// unusable, so the caller falls back to the local search.
AskResult? parseAskResponse(
  Map<String, dynamic> json, {
  required String question,
  required List<Place> places,
}) {
  final rawIds = json['placeIds'] ?? json['ids'];
  final filter = AskFilter.fromJson(json['filter']);
  if (rawIds is! List && filter == null) return null;

  final known = {for (final p in places) p.id};
  final ids = <String>[];
  final seen = <String>{};
  if (rawIds is List) {
    for (final raw in rawIds) {
      final id = raw is String ? raw.trim() : (raw is num ? '$raw' : null);
      if (id == null || !known.contains(id) || !seen.add(id)) continue;
      ids.add(id);
      if (ids.length >= kAskResultCap) break;
    }
  }
  if (ids.isEmpty && filter != null) {
    ids.addAll(
      places.where(filter.matches).take(kAskResultCap).map((p) => p.id),
    );
  }

  final rawExplanation = json['explanation'];
  var explanation = rawExplanation is String ? rawExplanation.trim() : '';
  if (explanation.length > 280) {
    explanation = '${explanation.substring(0, 277)}…';
  }
  if (explanation.isEmpty) {
    explanation = _countLine(ids.length, zh: _hasCjk(question));
  }
  return AskResult(
    question: question,
    placeIds: ids,
    explanation: explanation,
    filter: filter,
    usedAi: true,
  );
}

String _countLine(int n, {required bool zh}) {
  if (zh) return n == 0 ? '沒有符合的地方' : '找到 $n 個地方';
  if (n == 0) return 'No saved places fit';
  return n == 1 ? 'Found 1 place' : 'Found $n places';
}

// --- Prompt -----------------------------------------------------------------

const _distance = Distance();

double _km(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b) / 1000;

String _clip(String s, int max) {
  final t = s.replaceAll(RegExp(r'[\s|]+'), ' ').trim();
  return t.length <= max ? t : '${t.substring(0, max - 1)}…';
}

bool _visited(Place p) =>
    p.myScore != null || p.myPhotoAt != null || p.extraNotes.isNotEmpty;

/// One compact `|`-separated line per place — far smaller than JSON.
String _indexLine(Place p, {LatLng? near, List<int> boards = const []}) {
  final type = restaurantTypeOf(p);
  final details = p.details;
  final price = details?.priceLevel != null
      ? r'$' * details!.priceLevel!
      : _clip(p.priceRange ?? '', 16);
  final hours = details?.openingHours ?? p.hours;
  final fields = [
    p.id,
    _clip(p.name, 40),
    type == null || type == RestaurantType.other
        ? p.category.name
        : '${p.category.name}/${type.name}',
    _clip(
      [p.district, p.city, p.countryCode].where((s) => s.isNotEmpty).join(', '),
      40,
    ),
    p.myScore == null ? '' : 'score ${p.myScore}',
    p.isFavorite ? 'fav' : '',
    _visited(p) ? 'visited' : '',
    price,
    if (details != null && details.tags.isNotEmpty)
      _clip(details.tags.take(5).join(','), 60)
    else
      '',
    if (details != null && details.mustTry.isNotEmpty)
      'try ${_clip(details.mustTry.take(3).join(','), 50)}'
    else
      '',
    _clip(hours, 32),
    if (near != null && isFinitePlace(p))
      '${_km(near, p.location).toStringAsFixed(1)}km'
    else
      '',
    boards.isEmpty ? '' : 'b${boards.join(',')}',
  ];
  return fields.join('|');
}

/// [places] narrowed to at most [cap] for the prompt: local keyword
/// matches first, then (with [near]) the closest, then favourites and the
/// best-rated, then the rest in saved order.
List<Place> prefilterForAsk(
  String question,
  List<Place> places, {
  LatLng? near,
  int cap = kAskIndexCap,
}) {
  if (places.length <= cap) return places;
  final picked = <Place>[];
  final ids = <String>{};
  void add(Iterable<Place> more) {
    for (final p in more) {
      if (picked.length >= cap) return;
      if (ids.add(p.id)) picked.add(p);
    }
  }

  final byId = {for (final p in places) p.id: p};
  add(
    localAskSearch(
      question,
      places,
      near: near,
      limit: cap,
    ).placeIds.map((id) => byId[id]!),
  );
  final rest = places.where((p) => !ids.contains(p.id)).toList();
  if (near != null) {
    rest.sort(
      (a, b) => _distanceOrInf(near, a).compareTo(_distanceOrInf(near, b)),
    );
  } else {
    rest.sort((a, b) {
      final fav = (b.isFavorite ? 1 : 0) - (a.isFavorite ? 1 : 0);
      if (fav != 0) return fav;
      return (b.myScore ?? 0) - (a.myScore ?? 0);
    });
  }
  add(rest);
  return picked;
}

double _distanceOrInf(LatLng near, Place p) =>
    isFinitePlace(p) ? _km(near, p.location) : double.infinity;

/// The prompt for [AiSearch.ask]: the question, what "near" means, the
/// boards, and one [_indexLine] per place (prefiltered to [kAskIndexCap]).
String buildAskPrompt(
  String question,
  List<Place> places, {
  BoardIndex? boards,
  LatLng? near,
}) {
  final picked = prefilterForAsk(question, places, near: near);
  final boardRefs = boards?.boards ?? const <BoardRef>[];
  final boardNumber = {
    for (var i = 0; i < boardRefs.length; i++) boardRefs[i].key: i + 1,
  };
  final location = near == null
      ? 'No location is known. If the question says "near me", say you '
            'can\'t tell where the user is and rank by the other criteria.'
      : '"Near me" / "nearby" means near the centre of the map the user is '
            'looking at (${near.latitude.toStringAsFixed(4)}, '
            '${near.longitude.toStringAsFixed(4)}); the km field is the '
            'distance from it. Say "near the map centre" in the explanation.';
  final buffer = StringBuffer()
    ..writeln(
      'You search a traveller\'s SAVED places. Answer only from the list '
      'below — never invent places.',
    )
    ..writeln('Question: "${question.replaceAll('"', "'")}"')
    ..writeln(location);
  if (boardRefs.isNotEmpty) {
    buffer.writeln(
      'Boards: ${[for (final b in boardRefs) 'b${boardNumber[b.key]}=${_clip(b.name, 30)}'].join('; ')}',
    );
  }
  buffer
    ..writeln(
      'Places, one per line: id|name|category[/restaurantType]|area|my score '
      '(1-10)|fav|visited|price|tags|must-try|hours|distance|boards',
    )
    ..writeln(
      [
        for (final p in picked)
          _indexLine(
            p,
            near: near,
            boards: [
              for (final ref in boards?.boardsOf(p.id) ?? const <BoardRef>[])
                ?boardNumber[ref.key],
            ],
          ),
      ].join('\n'),
    )
    ..writeln(
      'Return JSON only: {"placeIds": [up to 30 ids from the list, best '
      'match first], "explanation": "one short sentence on why these — in '
      'the question\'s language (English, or Traditional Chinese if the '
      'question is in Chinese or Japanese)", "filter": {"category": one of '
      '${PlaceCategory.values.map((c) => c.name).join('/')} or null, '
      '"restaurantType": a restaurantType name or null, "city": string or '
      'null, "favoritesOnly": bool, "minScore": 1-10 or null, '
      '"maxPriceLevel": 1-4 or null}}. "Not visited" means no "visited". '
      'If nothing fits, return an empty placeIds list and say so.',
    );
  return buffer.toString();
}

// --- Local fallback ---------------------------------------------------------

/// Category keywords, all languages. A keyword may mean several categories
/// ("food" = restaurants and street food).
// dart format off
final Map<String, Set<PlaceCategory>> _categoryWords = {
  for (final w in ['restaurant', 'dinner', 'lunch', 'meal', '餐廳', '餐厅',
      'レストラン'])
    w: {PlaceCategory.restaurant},
  for (final w in ['food', 'eat', 'eats', '美食', '食嘢', '吃', 'グルメ'])
    w: {PlaceCategory.restaurant, PlaceCategory.food},
  for (final w in ['cafe', 'café', 'coffee', '咖啡', 'カフェ', 'コーヒー', '珈琲'])
    w: {PlaceCategory.cafe},
  for (final w in ['sightseeing', 'sights', 'sight', 'attraction', 'museum',
      'temple', 'shrine', 'park', '景點', '景点', '観光', '神社', '寺'])
    w: {PlaceCategory.sightseeing},
  for (final w in ['shopping', 'shop', 'store', 'mall', '購物', '買嘢',
      'ショッピング', '買い物'])
    w: {PlaceCategory.shopping},
  for (final w in ['hotel', 'stay', 'ryokan', 'hostel', '住宿', '酒店', 'ホテル',
      '旅館'])
    w: {PlaceCategory.stay},
  for (final w in ['nightlife', 'drinks', 'cocktail', '夜生活', '飲酒'])
    w: {PlaceCategory.nightlife},
};
// dart format on

/// Restaurant sub-type keywords: each type's own English/中文 labels (split
/// on "&" and "/"), plus Japanese and common extras.
final Map<String, Set<RestaurantType>> _typeWords = () {
  final words = <String, Set<RestaurantType>>{};
  void add(RestaurantType t, Iterable<String> keys) {
    for (final k in keys) {
      final key = k.trim().toLowerCase();
      if (key.length < 2 && !_hasCjk(key)) continue;
      (words[key] ??= {}).add(t);
    }
  }

  for (final t in RestaurantType.values) {
    if (t == RestaurantType.other) continue;
    // "Japanese (washoku)" → "japanese", "washoku".
    add(t, t.labelEn.split(RegExp(r'&| and |,|\(|\)')));
    add(t, t.labelZh.split('/'));
  }
  // dart format off
  const extras = <RestaurantType, List<String>>{
    RestaurantType.sushi: ['すし', '寿司', '鮨', '刺身', 'omakase'],
    RestaurantType.ramen: ['ラーメン', 'らーめん', '拉面', 'tsukemen', 'つけ麺'],
    RestaurantType.udonSoba: ['udon', 'soba', 'うどん', 'そば', '蕎麦', '烏冬'],
    RestaurantType.tempura: ['天ぷら', '天麩羅'],
    RestaurantType.tonkatsu: ['とんかつ', 'katsu', '豬扒'],
    RestaurantType.donburi: ['丼', 'unagi', '鰻', 'うなぎ'],
    RestaurantType.curry: ['カレー', '咖哩'],
    RestaurantType.okonomiyaki: ['お好み焼き', 'たこ焼き', 'takoyaki'],
    RestaurantType.yakitori: ['焼き鳥', '焼鳥', '串カツ'],
    RestaurantType.yakiniku: ['焼肉', 'bbq', '燒肉', '烤肉'],
    RestaurantType.japanese: ['和食', 'kaiseki', '懐石'],
    RestaurantType.hotpot: ['hotpot', 'shabu', 'しゃぶしゃぶ', '打邊爐'],
    RestaurantType.dimsum: ['yum cha', '飲茶', '點心', '点心'],
    RestaurantType.chaChaanTeng: ['茶記'],
    RestaurantType.korean: ['韓國', '韓国', '韓式'],
    RestaurantType.thai: ['泰國', 'タイ料理'],
    RestaurantType.vietnamese: ['越南', 'pho'],
    RestaurantType.indian: ['印度', 'インド'],
    RestaurantType.western: ['ステーキ', '牛扒'],
    RestaurantType.italian: ['pizza', 'pasta', 'ピザ', 'パスタ', '意粉'],
    RestaurantType.french: ['フレンチ', '法式'],
    RestaurantType.burger: ['ハンバーガー'],
    RestaurantType.seafood: ['海鮮', 'oyster'],
    RestaurantType.fineDining: ['michelin', '米芝蓮'],
    RestaurantType.bakery: ['bread', 'パン', '麵包', '面包'],
    RestaurantType.dessert: ['sweets', 'cake', '甜品', 'スイーツ', '蛋糕'],
    RestaurantType.bar: ['pub', 'beer', 'バー', '酒吧', '啤酒'],
  };
  // dart format on
  extras.forEach(add);
  return words;
}();

// dart format off
const _cheapWords = ['cheap', 'budget', 'inexpensive', 'affordable', '便宜',
    '抵食', '平價', '平嘢', '安い', '格安'];
const _lateWords = ['late night', 'late-night', 'midnight', 'night owl', '宵夜',
    '深夜', '夜宵', '夜食'];
const _favouriteWords = ['favourite', 'favorite', 'faves', 'fav', '最愛', '收藏',
    'お気に入り'];
const _notVisitedWords = ["haven't been", 'haven’t been', 'not been',
    'never been', 'not visited', 'unvisited', 'not yet', '還未去過', '还没去过',
    '未去過', '未去', '沒去過', '没去过', '還沒去', '行ったことない', '未訪問',
    '行ってない'];
const _visitedWords = ['been to', 'visited', '去過', '去过', '行った'];
const _nearWords = ['near me', 'nearby', 'near here', 'around here', 'close by',
    'near', '附近', '周圍', '近く', '近所'];
const _minScoreRated = ['i rated', 'rated', 'my score', '評分', '評過', '分以上'];

/// Filler words dropped before leftover terms are matched by name/notes.
const _stopwords = {
  'i', 'me', 'my', 'we', 'our', 'the', 'a', 'an', 'any', 'some', 'show',
  'find', 'where', 'what', 'which', 'who', 'how', 'can', 'could', 'should',
  'to', 'go', 'in', 'at', 'on', 'for', 'with', 'and', 'or', 'of', 'place',
  'places', 'spot', 'spots', 'good', 'best', 'great', 'nice', 'is', 'are',
  'do', 'did', 'have', 'has', 'there', 'that', 'want', 'please', 'recommend',
  'suggest', 'something', 'somewhere', 'get', 'try', 'it', 'its', 'open',
  'now', 'tonight', 'today', 'rated', 'yet', 'than', 'more', 'above', 'over',
  'out', 'up', 'around', 'saved', 'list', 'all', 'you',
};
const _cjkFillers = [
  '有冇', '有沒有', '有没有', '邊度', '邊間', '哪裡', '哪里', '哪間', '什麼', '什么',
  '推介', '推薦', '推荐', '一間', '我', '嘅', '的', '咩', '呢', '嗎', '吗', '啊',
  '呀', '想', '去', '食', '間', '好', '可以', '同', '和', '在', '係', '是', '過',
  'どこ', 'おすすめ', 'ある', 'の', 'は', 'を', 'に', 'で', 'が', 'か',
];
// dart format on

/// [needle] in [haystack]: CJK as a substring, Latin as a whole word
/// (optionally plural) so "bar" doesn't hit "barber".
RegExp _wordPattern(String needle) {
  if (_hasCjk(needle)) return RegExp(RegExp.escape(needle));
  return RegExp('(?<![a-zà-ÿ])${RegExp.escape(needle)}(?:s|es)?(?![a-zà-ÿ])');
}

/// Removes every match of any of [keys] from [text]; whether any matched.
(bool, String) _take(String text, Iterable<String> keys) {
  var out = text;
  var hit = false;
  // Longest first, so "late night" wins over "night", "near me" over "near".
  final sorted = keys.toList()..sort((a, b) => b.length - a.length);
  for (final k in sorted) {
    final pattern = _wordPattern(k);
    if (pattern.hasMatch(out)) {
      hit = true;
      out = out.replaceAll(pattern, ' ');
    }
  }
  return (hit, out);
}

/// Whether [p] is open late: a `late-night` tag, 24h, or hours whose
/// closing time is 23:00 or later (or past midnight).
bool isLateNight(Place p) {
  final tags = p.details?.tags ?? const [];
  if (tags.any((t) => t.contains('late') || t.contains('24'))) return true;
  final hours = '${p.details?.openingHours ?? ''} ${p.hours}'.toLowerCase();
  if (RegExp(r'24\s*(h|hours|hrs|小時|時間)').hasMatch(hours)) return true;
  final ranges = RegExp(
    r'(\d{1,2}):(\d{2})\s*[–\-~〜至to]+\s*(\d{1,2}):(\d{2})',
  ).allMatches(hours);
  for (final m in ranges) {
    final start = int.parse(m.group(1)!);
    final end = int.parse(m.group(3)!);
    if (end >= 23 || end < start) return true;
  }
  return false;
}

/// Whether [p] is cheap: [PlaceDetails.priceLevel] ≤ 2, a `cheap`/`budget`
/// tag, or a free entry.
bool isCheap(Place p) {
  final level = p.details?.priceLevel;
  if (level != null) return level <= 2;
  final tags = p.details?.tags ?? const [];
  if (tags.any((t) => t.contains('cheap') || t.contains('budget'))) return true;
  return (p.priceRange ?? '').toLowerCase().trim() == 'free';
}

/// The keyword fallback: detects intents (category / restaurant sub-type,
/// cheap, late night, favourites, "rated N+", (not) visited, an area that
/// exists in [places], near) and matches the leftover words through
/// [placeMatches]. Hard intents (kind, area, favourites, score, visited)
/// must hold; soft ones (cheap, late night, leftover words) narrow the
/// results only when at least one place meets them — so a missing price
/// level never empties the list. "Near" ranks by distance from [near].
AskResult localAskSearch(
  String question,
  List<Place> places, {
  LatLng? near,
  int limit = kAskResultCap,
  String? note,
}) {
  final zh = _hasCjk(question);
  var text =
      ' ${question.toLowerCase().replaceAll(RegExp(r'[?？!！,，.。、]'), ' ')} ';
  final parts = <String>[];

  // "rated 8+", "8+", "8 or more", "8分以上", "8分或以上".
  int? minScore;
  final scoreMatch =
      RegExp(
        r'(\d{1,2})(?:\s*/\s*10)?\s*(?:\+|分或以上|分以上|點以上|以上|or (?:more|higher|above)|and (?:up|above))',
      ).firstMatch(text) ??
      RegExp(
        r'(?:rated|score)\s*(?:above|over|>=?|at least)?\s*(\d{1,2})',
      ).firstMatch(text);
  if (scoreMatch != null) {
    final n = int.parse(scoreMatch.group(1)!);
    if (n >= 1 && n <= 10) {
      minScore = n;
      parts.add(zh ? '$n分或以上' : 'rated $n+');
    }
    text = text.replaceFirst(scoreMatch.group(0)!, ' ');
  }
  final (_, afterRated) = _take(text, _minScoreRated);
  text = afterRated;

  final (notVisited, t1) = _take(text, _notVisitedWords);
  text = t1;
  var visited = false;
  if (!notVisited) {
    final (v, t2) = _take(text, _visitedWords);
    visited = v;
    text = t2;
  }
  final (favourites, t3) = _take(text, _favouriteWords);
  final (cheap, t4) = _take(t3, _cheapWords);
  final (late, t5) = _take(t4, _lateWords);
  final (nearHit, t6) = _take(t5, _nearWords);
  text = t6;

  final types = <RestaurantType>{};
  final typeKeys = _typeWords.keys
      .where((k) => _wordPattern(k).hasMatch(text))
      .toList();
  for (final k in typeKeys) {
    types.addAll(_typeWords[k]!);
  }
  final (_, t7) = _take(text, typeKeys);
  text = t7;

  final categories = <PlaceCategory>{};
  final categoryKeys = _categoryWords.keys
      .where((k) => _wordPattern(k).hasMatch(text))
      .toList();
  for (final k in categoryKeys) {
    categories.addAll(_categoryWords[k]!);
  }
  final (_, t8) = _take(text, categoryKeys);
  text = t8;
  // A sub-type already implies "restaurant" / "food".
  if (types.isNotEmpty) {
    categories
      ..remove(PlaceCategory.restaurant)
      ..remove(PlaceCategory.food);
  }

  // An area the user actually has places in (city or district).
  final areas = <String>{
    for (final p in places) ...[p.city, p.district],
  }..removeWhere((a) => a.isEmpty);
  final pickedAreas = areas
      .where((a) => _wordPattern(a.toLowerCase()).hasMatch(text))
      .toSet();
  final (_, t9) = _take(text, pickedAreas.map((a) => a.toLowerCase()));
  text = t9;

  for (final f in _cjkFillers) {
    text = text.replaceAll(f, ' ');
  }
  final terms = text
      .split(RegExp(r'\s+'))
      .where(
        (w) =>
            w.isNotEmpty &&
            !_stopwords.contains(w) &&
            !RegExp(r'^\d+$').hasMatch(w),
      )
      .toList();

  if (types.isNotEmpty || categories.isNotEmpty) {
    parts.insert(
      0,
      [
        for (final t in types) zh ? t.labelZh : t.labelEn,
        for (final c in categories) zh ? c.labelZh : c.labelEn,
      ].join(' / '),
    );
  }
  if (pickedAreas.isNotEmpty) parts.add(pickedAreas.join(' / '));
  if (favourites) parts.add(zh ? '最愛' : 'favourites');
  if (notVisited) parts.add(zh ? '未去過' : 'not visited yet');
  if (visited) parts.add(zh ? '去過' : 'visited');

  final hasHard =
      types.isNotEmpty ||
      categories.isNotEmpty ||
      pickedAreas.isNotEmpty ||
      favourites ||
      minScore != null ||
      notVisited ||
      visited;

  var candidates = places.where((p) {
    if (types.isNotEmpty || categories.isNotEmpty) {
      final type = restaurantTypeOf(p);
      final kind =
          (type != null && types.contains(type)) ||
          categories.contains(p.category);
      if (!kind) return false;
    }
    if (pickedAreas.isNotEmpty &&
        !pickedAreas.contains(p.city) &&
        !pickedAreas.contains(p.district)) {
      return false;
    }
    if (favourites && !p.isFavorite) return false;
    if (minScore != null && (p.myScore ?? 0) < minScore) return false;
    if (notVisited && _visited(p)) return false;
    if (visited && !_visited(p)) return false;
    return true;
  }).toList();

  var softHit = false;
  void soft(bool on, bool Function(Place) test, String label) {
    if (!on) return;
    final kept = candidates.where(test).toList();
    if (kept.isEmpty) return;
    candidates = kept;
    softHit = true;
    parts.add(label);
  }

  soft(cheap, isCheap, zh ? '平' : 'cheap');
  soft(late, isLateNight, zh ? '夜晚營業' : 'open late');

  final hits = <String, int>{};
  if (terms.isNotEmpty) {
    for (final p in candidates) {
      final n = terms.where((t) => placeMatches(p, t)).length;
      if (n > 0) hits[p.id] = n;
    }
    if (hits.isNotEmpty) {
      candidates = candidates.where((p) => hits.containsKey(p.id)).toList();
      softHit = true;
      parts.add('“${terms.join(' ')}”');
    }
  }

  final useNear = nearHit && near != null;
  if (!hasHard && !softHit && !useNear) candidates = [];

  final order = {for (var i = 0; i < places.length; i++) places[i].id: i};
  candidates.sort((a, b) {
    if (useNear) {
      final d = _distanceOrInf(near, a).compareTo(_distanceOrInf(near, b));
      if (d != 0) return d;
    }
    final h = (hits[b.id] ?? 0) - (hits[a.id] ?? 0);
    if (h != 0) return h;
    final fav = (b.isFavorite ? 1 : 0) - (a.isFavorite ? 1 : 0);
    if (fav != 0) return fav;
    final score = (b.myScore ?? 0) - (a.myScore ?? 0);
    if (score != 0) return score;
    return order[a.id]! - order[b.id]!;
  });
  // "Near" alone ranks everything — keep just the closest few.
  final cap = useNear && !hasHard && !softHit ? 10 : limit;
  final ids = [for (final p in candidates.take(cap)) p.id];

  if (nearHit) {
    parts.add(
      near == null
          ? (zh ? '不知道你的位置' : 'location unknown')
          : (zh ? '近地圖中心' : 'nearest the map centre'),
    );
  }
  final summary = parts.isEmpty ? '' : '${parts.join(' · ')} — ';
  final source = note ?? (zh ? '關鍵字搜尋' : 'keyword match');
  return AskResult(
    question: question,
    placeIds: ids,
    explanation: '$summary${_countLine(ids.length, zh: zh)} ($source)',
  );
}

/// Suggestion chips for the search pill, grounded in [places]: each one is
/// only offered when [localAskSearch] finds at least one place for it.
List<String> askSuggestionsFor(List<Place> places, {int max = 5}) {
  if (places.isEmpty) return const [];
  final typeCounts = <RestaurantType, int>{};
  final cityCounts = <String, int>{};
  for (final p in places) {
    final t = restaurantTypeOf(p);
    if (t != null && t != RestaurantType.other) {
      typeCounts[t] = (typeCounts[t] ?? 0) + 1;
    }
    if (p.city.isNotEmpty) cityCounts[p.city] = (cityCounts[p.city] ?? 0) + 1;
  }
  String? topOf<K>(Map<K, int> counts, String Function(K) label) {
    if (counts.isEmpty) return null;
    final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    return label(top.key);
  }

  final topType = topOf<RestaurantType>(
    typeCounts,
    (t) => t.labelEn.split(RegExp(r' & | \(')).first.toLowerCase(),
  );
  final topCity = topOf<String>(cityCounts, (c) => c);
  // Each candidate with the extra condition its wording promises — the
  // local search treats "cheap"/"late night" as soft, so check them here.
  bool always(Place _) => true;
  final candidates = <(String, bool Function(Place))>[
    if (topType != null) ('cheap $topType', isCheap),
    ('cafés I rated 8+', always),
    ('places I rated 8+', always),
    ('late night food', isLateNight),
    ('還未去過嘅', always),
    if (topCity != null)
      ('favourites in $topCity', always)
    else
      ('my favourites', always),
    if (topType != null) ('$topType spots', always),
    if (topCity != null) ('food in $topCity', always),
  ];
  final byId = {for (final p in places) p.id: p};
  final out = <String>[];
  for (final (text, holds) in candidates) {
    if (out.length >= max) break;
    // "places I rated 8+" only when the café one didn't make it.
    if (text == 'places I rated 8+' && out.contains('cafés I rated 8+')) {
      continue;
    }
    final ids = localAskSearch(text, places).placeIds;
    if (ids.any((id) => holds(byId[id]!))) out.add(text);
  }
  return out;
}

/// Runs an "Ask" question: AI when configured, else (or on any error,
/// timeout or unusable answer) [localAskSearch]. Never throws.
class AiSearch {
  /// [ask] replaces the AI call (tests); [configured] defaults to true
  /// when [ask] is given, else to whether an AI key is set.
  AiSearch({
    Future<Map<String, dynamic>> Function(String prompt)? ask,
    bool? configured,
    this.timeout = const Duration(seconds: 12),
  }) : _ask = ask,
       _configured = configured ?? (ask != null ? true : null);

  final Future<Map<String, dynamic>> Function(String prompt)? _ask;
  bool? _configured;
  final Duration timeout;
  AiService? _ai;

  AiService get _service => _ai ??= AiService();

  bool get isConfigured => _configured ??= _service.isConfigured;

  Future<AskResult> ask(
    String question, {
    required List<Place> places,
    BoardIndex? boards,
    LatLng? near,
  }) async {
    final zh = _hasCjk(question);
    if (!isConfigured || places.isEmpty) {
      return localAskSearch(question, places, near: near);
    }
    try {
      final prompt = buildAskPrompt(
        question,
        places,
        boards: boards,
        near: near,
      );
      final call = _ask ?? _service.extractJson;
      final json = await call(prompt).timeout(timeout);
      final parsed = parseAskResponse(json, question: question, places: places);
      if (parsed != null) return parsed;
    } catch (_) {
      // Offline, geo-blocked, timed out… — the keyword search still works.
    }
    return localAskSearch(
      question,
      places,
      near: near,
      note: zh ? 'AI 暫時用不到，改用關鍵字搜尋' : 'AI unavailable — keyword match',
    );
  }

  void dispose() => _ai?.dispose();
}
