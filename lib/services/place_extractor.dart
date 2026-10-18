import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/mock_data.dart';
import '../models/place.dart';
import 'extraction_cache.dart';
import 'gemini_service.dart';
import 'geocoding_service.dart';
import 'post_metadata.dart';

/// Turns a shared caption / link into a structured [Place] (ANALYSIS.md §2).
///
/// Pipeline: for a bare IG/TikTok URL, [fetchPostMetadata] first scrapes the
/// post page's og:meta tags for a caption (crawler-UA fetch — native does
/// this directly, web routes it through the server-side proxy's `/api/meta`
/// since a browser can't do the fetch itself, see [fetchPostMetadata]'s
/// doc); that caption feeds Gemini alongside the original input. Gemini
/// extracts the structured fields from text → Nominatim resolves the address
/// to coordinates. The AI-extraction half mirrors event-calendar's JSON-mode
/// prompt + lenient parse.
///
/// NOTE: when the metadata fetch fails (private account, deleted post,
/// rate-limited, or — on web — the proxy not configured), a bare URL with no
/// caption text throws [CaptionUnavailableException] rather than sending
/// Gemini a link it can only guess from.
class PlaceExtractor {
  PlaceExtractor({
    GeminiService? gemini,
    GeocodingService? geocoder,
    Future<PostMetadata?> Function(Uri url)? metadataFetcher,
    ExtractionCache? cache,
    Future<void> Function(Duration)? delay,
  }) : _gemini = gemini ?? GeminiService(),
       _geocoder = geocoder ?? GeocodingService(),
       _metadataFetcher = metadataFetcher ?? fetchPostMetadata,
       _cache = cache ?? SharedPrefsExtractionCache(),
       _delay = delay ?? Future<void>.delayed;

  final GeminiService _gemini;
  final GeocodingService _geocoder;
  final Future<PostMetadata?> Function(Uri url) _metadataFetcher;
  final ExtractionCache _cache;

  /// Waits between consecutive Nominatim calls (usage policy: ≤1 req/s) —
  /// injectable so tests don't actually sleep.
  final Future<void> Function(Duration) _delay;
  DateTime? _lastGeocodeAt;

  /// Below this, a candidate is a guess and must be confirmed in the "Which
  /// one?" picker before it is saved — never saved silently.
  static const lowConfidenceThreshold = 0.6;

  /// Max alternatives kept per candidate (the prompt asks for up to 3).
  static const maxAlternatives = 3;

  bool get isConfigured => _gemini.isConfigured;

  /// Single-place convenience over [extractAll]: the first extracted place.
  /// Kept for callers that only want one [Place]; the add-a-find sheet uses
  /// [extractAll] so it can show multi-place posts and low-confidence picks.
  Future<Place> extract(String input) async =>
      (await extractAll(input)).places.first.place;

  /// Extracts every place a shared caption / link mentions (a "top 5 cafés"
  /// post yields five). Throws [CaptionUnavailableException] for a bare URL
  /// whose caption can't be read, [NoPlaceFoundException] when nothing
  /// usable comes back. A bare post URL's Gemini result is cached on device
  /// per normalized URL ([ExtractionCache]), so re-sharing the same post
  /// skips the caption fetch and the Gemini call.
  Future<ExtractionResult> extractAll(String input) async {
    final trimmed = input.trim();
    final postUrl = extractFirstPostUrl(trimmed);
    final bareUrl =
        postUrl != null && trimmed.replaceFirst(postUrl, '').trim().isEmpty;
    final cacheKey = bareUrl ? normalizePostUrl(postUrl) : null;

    final cached = cacheKey == null ? null : await _cache.read(cacheKey);
    Map<String, dynamic> json;
    String? caption;
    String? author;
    if (cached != null) {
      json = cached.json;
      caption = cached.caption;
      author = cached.author;
    } else {
      PostMetadata? meta;
      if (postUrl != null) {
        final uri = Uri.tryParse(postUrl);
        if (uri != null) meta = await _metadataFetcher(uri);
        caption = meta?.caption;
        author = meta?.author;
        if (bareUrl && (caption == null || caption.isEmpty)) {
          throw CaptionUnavailableException(postUrl);
        }
      }
      json = await _gemini.extractJson(_prompt(trimmed, meta));
    }

    final result = await _resolve(
      json,
      fallbackCaption: caption ?? trimmed,
      fallbackAuthor: author,
      postUrl: postUrl,
    );
    if (cacheKey != null && cached == null) {
      await _cache.write(
        cacheKey,
        CachedExtraction(json: json, caption: caption, author: author),
      );
    }
    return result;
  }

  /// Same extraction from a screenshot/photo of a post (Gemini vision) — the
  /// way around Instagram's login wall when the caption can't be fetched.
  /// [imageBytes] should already be downscaled (see image_prep.dart);
  /// [hint] is any text the user typed alongside (a link, a place name).
  Future<ExtractionResult> extractFromImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
    String hint = '',
  }) async {
    final trimmed = hint.trim();
    final json = await _gemini.extractJsonFromImage(
      _prompt(
        trimmed.isEmpty ? '(see the attached screenshot)' : trimmed,
        null,
        fromImage: true,
      ),
      imageBytes,
      mimeType: mimeType,
    );
    return _resolve(
      json,
      fallbackCaption: trimmed,
      fallbackAuthor: null,
      postUrl: extractFirstPostUrl(trimmed),
    );
  }

  /// Geocodes and builds every candidate in Gemini's [json]. Candidates with
  /// neither a usable name nor anything to geocode are dropped (rather than
  /// saved as "Untitled place" at [MockData.tokyoCenter]); if nothing is
  /// left, throws [NoPlaceFoundException].
  Future<ExtractionResult> _resolve(
    Map<String, dynamic> json, {
    required String fallbackCaption,
    required String? fallbackAuthor,
    required String? postUrl,
  }) async {
    final raws = rawCandidates(json);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final out = <ExtractedPlace>[];
    for (var i = 0; i < raws.length; i++) {
      final raw = raws[i];
      final name = _str(raw['name'], fallback: 'Untitled place');
      final address = _str(raw['address']);
      final region = _str(raw['region'], fallback: 'Unknown');

      // Prefer model-provided coords; otherwise geocode the address/name.
      LatLng? loc = _coords(raw['latitude'], raw['longitude']);
      final isPlaceholder = name == 'Untitled place';
      if (isPlaceholder && address.isEmpty && loc == null) {
        // Nothing to geocode either — don't send "Untitled place Unknown"
        // to Nominatim (it can return a false hit) and don't save a
        // placeholder.
        continue;
      }
      final confident = loc != null;
      var geocoded = const <GeocodeCandidate>[];
      if (loc == null) {
        geocoded = await _geocodeCandidates(
          address.isNotEmpty ? address : '$name $region',
        );
        if (geocoded.isNotEmpty) loc = geocoded.first.location;
      }
      if (loc == null && isPlaceholder) {
        // Would otherwise silently save "Untitled place" pinned to
        // MockData.tokyoCenter — drop it instead.
        continue;
      }

      final place = _buildPlace(
        raw,
        id: i == 0 ? 'gx$stamp' : 'gx${stamp}_$i',
        location: loc ?? MockData.tokyoCenter, // last-resort default
        matchConfident: confident || loc != null,
        // The Tokyo stand-in is never a silent wrong pin: flagged so the
        // card/pin/detail sheet ask the user to fix it.
        locationConfirmed: loc != null,
        fallbackCaption: fallbackCaption,
        fallbackAuthor: fallbackAuthor,
        postUrl: postUrl,
      );
      out.add(
        ExtractedPlace(
          place: place,
          confidence: parseConfidence(raw['confidence']),
          alternatives: parseAlternatives(raw['alternatives'], exclude: name),
          geocodeCandidates: geocoded,
          geocodeAmbiguous: GeocodingService.isAmbiguous(geocoded),
          located: loc != null,
        ),
      );
    }
    if (out.isEmpty) throw const NoPlaceFoundException();
    return ExtractionResult(places: out, sourceUrl: postUrl);
  }

  /// [base] moved to one of its own [GeocodeCandidate]s (the picker's "this
  /// branch" choice for an ambiguous name).
  Place placeAt(ExtractedPlace base, GeocodeCandidate candidate) =>
      base.place.copyWith(
        location: candidate.location,
        address: base.place.address.isEmpty ? candidate.displayName : null,
        matchConfident: true,
        locationConfirmed: true,
      );

  /// [base] re-pointed at one of Gemini's [PlaceAlternative]s, geocoded now.
  /// Null when the alternative can't be located (the picker then says so
  /// rather than saving it at a default location).
  Future<Place?> resolveAlternative(
    ExtractedPlace base,
    PlaceAlternative alt,
  ) async {
    final region = alt.region.isNotEmpty ? alt.region : base.place.region;
    final results = await _geocodeCandidates(
      alt.address.isNotEmpty ? alt.address : '${alt.name} $region',
    );
    if (results.isEmpty) return null;
    return base.place.copyWith(
      name: alt.name,
      areaLabel: alt.areaLabel.isNotEmpty ? alt.areaLabel : region,
      region: region,
      address: alt.address,
      location: results.first.location,
      matchConfident: true,
      locationConfirmed: true,
    );
  }

  Future<List<GeocodeCandidate>> _geocodeCandidates(String query) async {
    final last = _lastGeocodeAt;
    if (last != null) {
      final wait = const Duration(seconds: 1) - DateTime.now().difference(last);
      if (wait > Duration.zero) await _delay(wait);
    }
    try {
      return await _geocoder.geocodeCandidates(query);
    } finally {
      _lastGeocodeAt = DateTime.now();
    }
  }

  Place _buildPlace(
    Map<String, dynamic> json, {
    required String id,
    required LatLng location,
    required bool matchConfident,
    bool locationConfirmed = true,
    required String fallbackCaption,
    required String? fallbackAuthor,
    required String? postUrl,
  }) {
    final name = _str(json['name'], fallback: 'Untitled place');
    final areaLabel = _str(json['areaLabel']);
    final region = _str(json['region'], fallback: 'Unknown');
    final category = _category(_str(json['category']));
    return Place(
      id: id,
      name: name,
      areaLabel: areaLabel.isNotEmpty ? areaLabel : region,
      region: region,
      category: category,
      location: location,
      descriptionEn: _str(
        json['descriptionEn'],
        fallback: 'No description extracted.',
      ),
      originalCaption: _str(json['originalCaption'], fallback: fallbackCaption),
      address: _str(json['address']),
      hours: _str(json['hours'], fallback: 'Hours unknown'),
      sourceHandle: _str(
        json['sourceHandle'],
        fallback: fallbackAuthor ?? '@unknown',
      ),
      sourcePlatform: _platform(_str(json['sourcePlatform']), postUrl),
      award: _nullableStr(json['award']),
      matchConfident: matchConfident,
      locationConfirmed: locationConfirmed,
      rating: _nullableDouble(json['rating']),
      reviewCount: _nullableInt(json['reviewCount']),
      priceRange: _nullableStr(json['priceRange']),
      restaurantType: parseRestaurantType(
        _str(json['restaurantType']),
        category,
      ),
    );
  }

  /// The per-place objects in Gemini's reply: `{"places": [...]}` (what the
  /// prompt asks for), or — model drift insurance — the older single bare
  /// object, or a bare list. Non-object entries are ignored.
  @visibleForTesting
  static List<Map<String, dynamic>> rawCandidates(Map<String, dynamic> json) {
    final list = json['places'];
    if (list is List) {
      return [
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    }
    final looksLikePlace =
        json.containsKey('name') ||
        json.containsKey('address') ||
        json.containsKey('latitude');
    return looksLikePlace ? [json] : const [];
  }

  /// Gemini's 0–1 `confidence`, leniently: a percentage (e.g. 85) is scaled
  /// down, out-of-range values clamp. Missing/unparseable → 1.0 — older
  /// replies carried no confidence and single-place posts must behave as
  /// before.
  @visibleForTesting
  static double parseConfidence(Object? v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
    if (d == null || d.isNaN) return 1.0;
    final scaled = d > 1 && d <= 100 ? d / 100 : d;
    return scaled.clamp(0.0, 1.0);
  }

  /// Up to [maxAlternatives] distinct, named alternatives, dropping any
  /// that repeat the primary candidate's name ([exclude]).
  @visibleForTesting
  static List<PlaceAlternative> parseAlternatives(
    Object? v, {
    String exclude = '',
  }) {
    if (v is! List) return const [];
    final seen = <String>{exclude.trim().toLowerCase()};
    final out = <PlaceAlternative>[];
    for (final e in v) {
      if (e is! Map) continue;
      String s(Object? x) {
        final t = '${x ?? ''}'.trim();
        return t.toLowerCase() == 'null' ? '' : t;
      }

      final name = s(e['name']);
      if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
      out.add(
        PlaceAlternative(
          name: name,
          areaLabel: s(e['areaLabel']),
          region: s(e['region']),
          address: s(e['address']),
        ),
      );
      if (out.length == maxAlternatives) break;
    }
    return out;
  }

  String _prompt(String input, PostMetadata? meta, {bool fromImage = false}) =>
      '''
You extract travel places from a social-media post (Instagram/TikTok)${fromImage ? ' — given as the attached screenshot; read every visible caption, overlay text, location tag and handle in it' : ''}.
A post may feature ONE place or list SEVERAL (e.g. "top 5 cafés in Kyoto") —
return every distinct place it recommends, in the order they appear.
Return ONLY a JSON object, no prose: {"places": [ ... ]}, each element with these keys:
- name: place name, keep the original language (e.g. "五感 (Gogo)")
- areaLabel: short neighbourhood/area tag (e.g. "池袋")
- region: "City, Country" (e.g. "Tokyo, Japan")
- category: one of restaurant, cafe, food, sightseeing, shopping, stay, nightlife
- restaurantType: only when category is "restaurant" — cuisine/style, one of:
  sushi, ramen, udonSoba, tempura, tonkatsu, donburi, curry, okonomiyaki,
  yakitori, izakaya, yakiniku, japanese, hotpot, dimsum, chaChaanTeng,
  chinese, korean, thai, vietnamese, indian, western, italian, french,
  burger, seafood, fineDining, bakery, dessert, bar, other. Else null.
- latitude: number or null if unknown
- longitude: number or null if unknown
- descriptionEn: a 1-2 sentence English summary of this place
- originalCaption: the original caption text, language preserved
- address: full street address, original language if applicable
- hours: opening hours if mentioned, else ""
- sourceHandle: the author handle if present (e.g. "@rame.nbon"), else ""
- sourcePlatform: "instagram" or "tiktok"
- award: any award/recognition mentioned (e.g. "Michelin Bib Gourmand"), else null
- rating: average rating out of 5 (e.g. 4.7) if mentioned, else null
- reviewCount: number of reviews backing the rating (e.g. 85) if mentioned, else null
- priceRange: price indicator in the original currency (e.g. "\$600–1,400"), else null
- confidence: 0 to 1 — how sure you are this name identifies the right real
  place (1 = named and located explicitly; below 0.6 = a guess from vague clues)
- alternatives: when ambiguous (confidence below 0.8, a chain, or a name several
  places share), up to 3 other likely candidates as
  [{"name": "", "areaLabel": "", "region": "", "address": ""}], else []

If a value is unknown, use "" (or null for latitude/longitude/award/rating/reviewCount/priceRange).
Do not invent places the post doesn't mention. If it mentions none, return {"places": []}.

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
      'sashimi': RestaurantType.sushi,
      'omakase': RestaurantType.fineDining,
      'udon': RestaurantType.udonSoba,
      'soba': RestaurantType.udonSoba,
      'udon/soba': RestaurantType.udonSoba,
      'unagi': RestaurantType.donburi,
      'takoyaki': RestaurantType.okonomiyaki,
      'kushikatsu': RestaurantType.yakitori,
      'bbq': RestaurantType.yakiniku,
      'barbecue': RestaurantType.yakiniku,
      'washoku': RestaurantType.japanese,
      'kaiseki': RestaurantType.fineDining,
      'fine dining': RestaurantType.fineDining,
      'hot pot': RestaurantType.hotpot,
      'shabu-shabu': RestaurantType.hotpot,
      'sukiyaki': RestaurantType.hotpot,
      'dim sum': RestaurantType.dimsum,
      'cantonese': RestaurantType.dimsum,
      'cha chaan teng': RestaurantType.chaChaanTeng,
      '茶餐廳': RestaurantType.chaChaanTeng,
      'taiwanese': RestaurantType.chinese,
      'sichuan': RestaurantType.chinese,
      'steak': RestaurantType.western,
      'steakhouse': RestaurantType.western,
      'pizza': RestaurantType.italian,
      'pasta': RestaurantType.italian,
      'hamburger': RestaurantType.burger,
      'sweets': RestaurantType.dessert,
      'desserts': RestaurantType.dessert,
      'pub': RestaurantType.bar,
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
/// it (private account, deleted post, rate-limited, or — on web — the proxy
/// not configured/reachable) — sending Gemini just the raw link produces a
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

/// One place pulled out of a post, plus what the add-a-find sheet needs to
/// decide whether to ask "Which one?" before saving it.
class ExtractedPlace {
  const ExtractedPlace({
    required this.place,
    this.confidence = 1.0,
    this.alternatives = const [],
    this.geocodeCandidates = const [],
    this.geocodeAmbiguous = false,
    this.located = true,
  });

  /// Best guess, ready to save.
  final Place place;

  /// Gemini's 0–1 confidence that [place] is the right real place.
  final double confidence;

  /// Other places the post might mean (Gemini, when ambiguous).
  final List<PlaceAlternative> alternatives;

  /// Nominatim matches for [place]'s name/address, best first (empty when
  /// Gemini supplied coordinates itself).
  final List<GeocodeCandidate> geocodeCandidates;

  /// [geocodeCandidates] point at genuinely different places (a chain).
  final bool geocodeAmbiguous;

  /// False when nothing located [place] and it sits at the default location.
  final bool located;

  /// Low confidence or an ambiguous geocode: confirm before saving.
  bool get needsConfirmation =>
      confidence < PlaceExtractor.lowConfidenceThreshold || geocodeAmbiguous;
}

/// An alternative candidate Gemini offered for an ambiguous mention.
class PlaceAlternative {
  const PlaceAlternative({
    required this.name,
    this.areaLabel = '',
    this.region = '',
    this.address = '',
  });

  final String name;
  final String areaLabel;
  final String region;
  final String address;

  /// "Shibuya · Tokyo, Japan" — whatever context is known.
  String get subtitle =>
      [areaLabel, region].where((s) => s.isNotEmpty).toSet().join(' · ');
}

/// Everything one post yielded.
class ExtractionResult {
  const ExtractionResult({required this.places, this.sourceUrl});

  final List<ExtractedPlace> places;

  /// The IG/TikTok link the input contained, if any (merge appends it to an
  /// already-saved duplicate).
  final String? sourceUrl;
}
