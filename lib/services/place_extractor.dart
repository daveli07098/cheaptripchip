import 'package:latlong2/latlong.dart';

import '../data/mock_data.dart';
import '../models/place.dart';
import 'gemini_service.dart';
import 'geocoding_service.dart';

/// Turns a shared caption / link into a structured [Place] (ANALYSIS.md §2).
///
/// Pipeline: Gemini extracts the fields from text → Nominatim resolves the
/// address to coordinates. The AI-extraction half mirrors event-calendar's
/// JSON-mode prompt + lenient parse.
///
/// NOTE: a bare IG/TikTok URL can't be read client-side (CORS/auth). For best
/// results paste the caption text too; full URL ingestion belongs on the
/// backend (fetch page → feed text to this same prompt).
class PlaceExtractor {
  PlaceExtractor({GeminiService? gemini, GeocodingService? geocoder})
      : _gemini = gemini ?? GeminiService(),
        _geocoder = geocoder ?? GeocodingService();

  final GeminiService _gemini;
  final GeocodingService _geocoder;

  bool get isConfigured => _gemini.isConfigured;

  Future<Place> extract(String input) async {
    final json = await _gemini.extractJson(_prompt(input));

    final name = _str(json['name'], fallback: 'Untitled place');
    final address = _str(json['address']);
    final areaLabel = _str(json['areaLabel']);
    final region = _str(json['region'], fallback: 'Unknown');

    // Prefer model-provided coords; otherwise geocode the address/name.
    LatLng? loc = _coords(json['latitude'], json['longitude']);
    var confident = loc != null;
    loc ??= await _geocoder.geocode(
      address.isNotEmpty ? address : '$name $region',
    );
    final resolved = loc ?? MockData.tokyoCenter; // last-resort default

    return Place(
      id: 'gx${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      areaLabel: areaLabel.isNotEmpty ? areaLabel : region,
      region: region,
      category: _category(_str(json['category'])),
      location: resolved,
      descriptionEn: _str(json['descriptionEn'],
          fallback: 'No description extracted.'),
      originalCaption: _str(json['originalCaption'], fallback: input),
      address: address,
      hours: _str(json['hours'], fallback: 'Hours unknown'),
      sourceHandle: _str(json['sourceHandle'], fallback: '@unknown'),
      sourcePlatform: _platform(_str(json['sourcePlatform'])),
      award: _nullableStr(json['award']),
      matchConfident: confident || loc != null,
    );
  }

  String _prompt(String input) => '''
You extract a single travel place from a social-media post (Instagram/TikTok).
Return ONLY a JSON object, no prose, with these keys:
- name: place name, keep the original language (e.g. "五感 (Gogo)")
- areaLabel: short neighbourhood/area tag (e.g. "池袋")
- region: "City, Country" (e.g. "Tokyo, Japan")
- category: one of restaurant, food, sightseeing, shopping, stay, nightlife
- latitude: number or null if unknown
- longitude: number or null if unknown
- descriptionEn: a 1-2 sentence English summary
- originalCaption: the original caption text, language preserved
- address: full street address, original language if applicable
- hours: opening hours if mentioned, else ""
- sourceHandle: the author handle if present (e.g. "@rame.nbon"), else ""
- sourcePlatform: "instagram" or "tiktok"
- award: any award/recognition mentioned (e.g. "Michelin Bib Gourmand"), else null

If a value is unknown, use "" (or null for latitude/longitude/award).

POST CONTENT:
$input
''';

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

  SourcePlatform _platform(String raw) {
    return raw.toLowerCase().contains('tik')
        ? SourcePlatform.tiktok
        : SourcePlatform.instagram;
  }

  void dispose() {
    _gemini.dispose();
    _geocoder.dispose();
  }
}
