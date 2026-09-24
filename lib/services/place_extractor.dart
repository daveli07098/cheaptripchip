import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/mock_data.dart';
import '../models/place.dart';
import 'gemini_service.dart';
import 'geocoding_service.dart';
import 'post_metadata.dart';

/// Turns a shared caption / link into a structured [Place] (ANALYSIS.md §2).
///
/// Pipeline: for a bare IG/TikTok URL, [fetchPostMetadata] first scrapes the
/// post page's og:meta tags for a caption (crawler-UA fetch — CORS blocks
/// this on web, see [fetchPostMetadata]'s doc); that caption feeds Gemini
/// alongside the original input. Gemini extracts the structured fields from
/// text → Nominatim resolves the address to coordinates. The AI-extraction
/// half mirrors event-calendar's JSON-mode prompt + lenient parse.
///
/// NOTE: on web, or when the metadata fetch fails (private account, deleted
/// post, rate-limited), a bare URL with no caption text throws
/// [CaptionUnavailableException] rather than sending Gemini a link it can
/// only guess from.
class PlaceExtractor {
  PlaceExtractor({
    GeminiService? gemini,
    GeocodingService? geocoder,
    Future<PostMetadata?> Function(Uri url)? metadataFetcher,
  }) : _gemini = gemini ?? GeminiService(),
       _geocoder = geocoder ?? GeocodingService(),
       _metadataFetcher = metadataFetcher ?? fetchPostMetadata;

  final GeminiService _gemini;
  final GeocodingService _geocoder;
  final Future<PostMetadata?> Function(Uri url) _metadataFetcher;

  bool get isConfigured => _gemini.isConfigured;

  Future<Place> extract(String input) async {
    final trimmed = input.trim();
    final postUrl = extractFirstPostUrl(trimmed);
    PostMetadata? meta;
    if (postUrl != null) {
      final uri = Uri.tryParse(postUrl);
      if (uri != null) meta = await _metadataFetcher(uri);
      final bareUrl = trimmed.replaceFirst(postUrl, '').trim().isEmpty;
      final caption = meta?.caption;
      if (bareUrl && (caption == null || caption.isEmpty)) {
        throw CaptionUnavailableException(postUrl);
      }
    }

    final json = await _gemini.extractJson(_prompt(trimmed, meta));

    final name = _str(json['name'], fallback: 'Untitled place');
    final address = _str(json['address']);
    final areaLabel = _str(json['areaLabel']);
    final region = _str(json['region'], fallback: 'Unknown');

    // Prefer model-provided coords; otherwise geocode the address/name.
    LatLng? loc = _coords(json['latitude'], json['longitude']);
    final isPlaceholder = name == 'Untitled place';
    if (isPlaceholder && address.isEmpty && loc == null) {
      // Nothing to geocode either — don't send "Untitled place Unknown" to
      // Nominatim (it can return a false hit) and don't save a placeholder.
      throw const NoPlaceFoundException();
    }
    var confident = loc != null;
    loc ??= await _geocoder.geocode(
      address.isNotEmpty ? address : '$name $region',
    );
    if (loc == null && isPlaceholder) {
      // Would otherwise silently save "Untitled place" pinned to
      // MockData.tokyoCenter — surface the failure instead.
      throw const NoPlaceFoundException();
    }
    final resolved = loc ?? MockData.tokyoCenter; // last-resort default

    final category = _category(_str(json['category']));

    return Place(
      id: 'gx${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      areaLabel: areaLabel.isNotEmpty ? areaLabel : region,
      region: region,
      category: category,
      location: resolved,
      descriptionEn: _str(
        json['descriptionEn'],
        fallback: 'No description extracted.',
      ),
      originalCaption: _str(
        json['originalCaption'],
        fallback: meta?.caption ?? trimmed,
      ),
      address: address,
      hours: _str(json['hours'], fallback: 'Hours unknown'),
      sourceHandle: _str(
        json['sourceHandle'],
        fallback: meta?.author ?? '@unknown',
      ),
      sourcePlatform: _platform(_str(json['sourcePlatform']), postUrl),
      award: _nullableStr(json['award']),
      matchConfident: confident || loc != null,
      rating: _nullableDouble(json['rating']),
      reviewCount: _nullableInt(json['reviewCount']),
      priceRange: _nullableStr(json['priceRange']),
      restaurantType: parseRestaurantType(
        _str(json['restaurantType']),
        category,
      ),
    );
  }

  String _prompt(String input, PostMetadata? meta) =>
      '''
You extract a single travel place from a social-media post (Instagram/TikTok).
Return ONLY a JSON object, no prose, with these keys:
- name: place name, keep the original language (e.g. "五感 (Gogo)")
- areaLabel: short neighbourhood/area tag (e.g. "池袋")
- region: "City, Country" (e.g. "Tokyo, Japan")
- category: one of restaurant, cafe, food, sightseeing, shopping, stay, nightlife
- restaurantType: only when category is "restaurant" — cuisine/style, one of:
  ramen, sushi, izakaya, yakiniku, hotpot, dimsum, chaChaanTeng, japanese,
  korean, western, fineDining, other. Else null.
- latitude: number or null if unknown
- longitude: number or null if unknown
- descriptionEn: a 1-2 sentence English summary
- originalCaption: the original caption text, language preserved
- address: full street address, original language if applicable
- hours: opening hours if mentioned, else ""
- sourceHandle: the author handle if present (e.g. "@rame.nbon"), else ""
- sourcePlatform: "instagram" or "tiktok"
- award: any award/recognition mentioned (e.g. "Michelin Bib Gourmand"), else null
- rating: average rating out of 5 (e.g. 4.7) if mentioned, else null
- reviewCount: number of reviews backing the rating (e.g. 85) if mentioned, else null
- priceRange: price indicator in the original currency (e.g. "\$600–1,400"), else null

If a value is unknown, use "" (or null for latitude/longitude/award/rating/reviewCount/priceRange).

POST CONTENT:
$input
${meta == null ? '' : '''
CAPTION (from the post page): ${meta.caption ?? '(unavailable)'}
AUTHOR: ${meta.author ?? '(unknown)'}
'''}''';

  // --- coercion helpers (LLM output is untrusted) ---

  String _str(Object? v, {String fallback = ''}) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty || s.toLowerCase() == 'null' ? fallback : s;
  }

  String? _nullableStr(Object? v) {
    final s = _str(v);
    return s.isEmpty ? null : s;
  }

  double? _nullableDouble(Object? v) {
    if (v == null) return null;
    return v is num ? v.toDouble() : double.tryParse('$v');
  }

  int? _nullableInt(Object? v) {
    if (v == null) return null;
    return v is num ? v.toInt() : int.tryParse('$v');
  }

  LatLng? _coords(Object? lat, Object? lng) {
    final a = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final b = lng is num ? lng.toDouble() : double.tryParse('$lng');
    if (a == null || b == null) return null;
    if (a == 0 && b == 0) return null; // common "unknown" sentinel
    return LatLng(a, b);
  }

  PlaceCategory _category(String raw) {
    final v = raw.toLowerCase();
    return PlaceCategory.values.firstWhere(
      (c) => c.name == v,
      orElse: () => PlaceCategory.food,
    );
  }

  SourcePlatform _platform(String raw, [String? urlHint]) {
    final v = raw.toLowerCase();
    if (v.contains('tik')) return SourcePlatform.tiktok;
    if (v.contains('insta')) return SourcePlatform.instagram;
    // Model didn't say — fall back to the URL we found in the input, if any.
    if (urlHint != null && urlHint.toLowerCase().contains('tiktok')) {
      return SourcePlatform.tiktok;
    }
    return SourcePlatform.instagram;
  }

  /// Parses Gemini's `restaurantType`, leniently: `null` outright for a
  /// non-restaurant [category] or empty/missing input; an exact
  /// [RestaurantType.name] match; else a small set of common synonyms the
  /// model tends to use instead of the enum name; else `null` — deliberately
  /// NOT a forced fallback to [RestaurantType.other] here, so an
  /// unrecognized guess still leaves room for [Place.effectiveRestaurantType]'s
  /// own keyword detection (see restaurant_type_detect.dart) to try next.
  ///
  /// Public (not `_`-prefixed) only so tests can exercise it directly without
  /// a network round trip — not meant to be called from outside this class.
  @visibleForTesting
  RestaurantType? parseRestaurantType(String raw, PlaceCategory category) {
    if (category != PlaceCategory.restaurant) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final type in RestaurantType.values) {
      if (type.name.toLowerCase() == v) return type;
    }
    const synonyms = <String, RestaurantType>{
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
    return synonyms[v];
  }

  void dispose() {
    _gemini.dispose();
    _geocoder.dispose();
  }
}

/// Thrown when [PlaceExtractor.extract]'s input is nothing but a bare
/// Instagram/TikTok URL and [fetchPostMetadata] couldn't read a caption for
/// it (private account, deleted post, rate-limited, or running on web where
/// the fetch is CORS-blocked) — sending Gemini just the raw link produces a
/// guess, not an extraction.
class CaptionUnavailableException implements Exception {
  const CaptionUnavailableException(this.url);

  final String url;

  @override
  String toString() =>
      "CaptionUnavailableException: couldn't read caption for $url";
}

/// Thrown when Gemini's response has no name, no address, and no
/// coordinates (or a placeholder name that a geocode also failed to
/// resolve) — surfacing this beats silently saving an "Untitled place"
/// pinned to [MockData.tokyoCenter].
class NoPlaceFoundException implements Exception {
  const NoPlaceFoundException();

  @override
  String toString() => 'NoPlaceFoundException: no place found in this post';
}
