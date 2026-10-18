/// AI-filled extra facts about a [Place] (lib/models/place.dart) — see
/// PlaceEnricher (lib/services/place_enricher.dart). Kept separate from the
/// place's own fields so enrichment never overwrites anything the user
/// edited (category, type, notes): the whole object is replaced on refresh.
///
/// Not private — a shared-board copy keeps it (see `sharedCopyOf`).
class PlaceDetails {
  const PlaceDetails({
    this.mustTry = const [],
    this.priceLevel,
    this.nativeName,
    this.tags = const [],
    this.openingHours,
    this.summaryEn,
    this.summaryZh,
    this.captionEn,
    this.captionZh,
    required this.enrichedAt,
  });

  /// Signature dishes/items worth ordering, e.g. ["tonkotsu ramen", "gyoza"].
  final List<String> mustTry;

  /// Price level 1–4 (cheap … very expensive); null when unknown. Rendered
  /// as ¥¥ / $$ etc. by country (see [priceSymbolFor]).
  final int? priceLevel;

  /// The name in the local language/script (e.g. "一蘭 渋谷店"); null when
  /// unknown or the same as the place name.
  final String? nativeName;

  /// Short lowercase English tags, e.g. "late-night", "solo-friendly",
  /// "cash-only", "reservation", "queue", "view", "kid-friendly".
  final List<String> tags;

  /// Human-readable opening hours, e.g. "Daily 11:00–23:00".
  final String? openingHours;

  /// One-or-two sentence summaries in English / Traditional Chinese.
  final String? summaryEn;
  final String? summaryZh;

  /// The source caption translated to English / Traditional Chinese.
  final String? captionEn;
  final String? captionZh;

  /// When these details were generated.
  final DateTime enrichedAt;

  /// Whether nothing useful was filled in (every field empty/null).
  bool get isEmpty =>
      mustTry.isEmpty &&
      priceLevel == null &&
      nativeName == null &&
      tags.isEmpty &&
      openingHours == null &&
      summaryEn == null &&
      summaryZh == null &&
      captionEn == null &&
      captionZh == null;

  PlaceDetails copyWith({
    List<String>? mustTry,
    int? priceLevel,
    String? nativeName,
    List<String>? tags,
    String? openingHours,
    String? summaryEn,
    String? summaryZh,
    String? captionEn,
    String? captionZh,
    DateTime? enrichedAt,
  }) {
    return PlaceDetails(
      mustTry: mustTry ?? this.mustTry,
      priceLevel: priceLevel ?? this.priceLevel,
      nativeName: nativeName ?? this.nativeName,
      tags: tags ?? this.tags,
      openingHours: openingHours ?? this.openingHours,
      summaryEn: summaryEn ?? this.summaryEn,
      summaryZh: summaryZh ?? this.summaryZh,
      captionEn: captionEn ?? this.captionEn,
      captionZh: captionZh ?? this.captionZh,
      enrichedAt: enrichedAt ?? this.enrichedAt,
    );
  }

  /// Plain JSON only (Firestore-safe); null fields are emitted as null so a
  /// merge write clears them on refresh.
  Map<String, dynamic> toJson() => {
    'mustTry': mustTry,
    'priceLevel': priceLevel,
    'nativeName': nativeName,
    'tags': tags,
    'openingHours': openingHours,
    'summaryEn': summaryEn,
    'summaryZh': summaryZh,
    'captionEn': captionEn,
    'captionZh': captionZh,
    'enrichedAt': enrichedAt.toUtc().toIso8601String(),
  };

  /// Lenient parse: non-map → null; bad fields fall back to empty/null;
  /// priceLevel outside 1–4 → null; tags lower-cased, blanks dropped;
  /// a missing/garbage `enrichedAt` falls back to the epoch (still "enriched",
  /// so the backfill won't loop on it).
  static PlaceDetails? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    return PlaceDetails(
      mustTry: _stringList(raw['mustTry']),
      priceLevel: _priceLevel(raw['priceLevel']),
      nativeName: _string(raw['nativeName']),
      tags: {
        for (final t in _stringList(raw['tags'])) t.toLowerCase(),
      }.toList(),
      openingHours: _string(raw['openingHours']),
      summaryEn: _string(raw['summaryEn']),
      summaryZh: _string(raw['summaryZh']),
      captionEn: _string(raw['captionEn']),
      captionZh: _string(raw['captionZh']),
      enrichedAt: _date(raw['enrichedAt']),
    );
  }

  static String? _string(dynamic raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return null;
    return value;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return [for (final e in raw) ?_string(e)];
  }

  static int? _priceLevel(dynamic raw) {
    final value = raw is num
        ? raw
        : (raw is String ? num.tryParse(raw.trim()) : null);
    if (value == null || !value.isFinite) return null;
    final level = value.round();
    return level >= 1 && level <= 4 ? level : null;
  }

  static DateTime _date(dynamic raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

/// Price-level glyphs by ISO country code — the local currency symbol
/// (¥ for JP/CN, ₩ for KR, € for the eurozone…, else "$") repeated
/// [level] times, e.g. "¥¥".
String priceSymbolFor(int level, String countryCode) {
  final symbol = switch (countryCode.toUpperCase()) {
    'JP' || 'CN' => '¥',
    'KR' => '₩',
    'GB' => '£',
    'TH' => '฿',
    'VN' => '₫',
    'IN' => '₹',
    'FR' || 'DE' || 'IT' || 'ES' || 'NL' || 'PT' || 'AT' || 'BE' => '€',
    _ => r'$',
  };
  return symbol * level.clamp(1, 4);
}
