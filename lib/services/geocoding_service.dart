import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Free forward geocoding via OSM Nominatim (see ANALYSIS.md → OSM alternative).
///
/// $0, no API key. Nominatim's usage policy requires a descriptive User-Agent
/// and max ~1 request/second — fine for save-time geocoding. At scale, self-host
/// or switch to LocationIQ (the call site stays the same).
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<LatLng?> geocode(String query) async {
    final results = await geocodeCandidates(query, limit: 1);
    return results.isEmpty ? null : results.first.location;
  }

  /// Up to [limit] Nominatim matches for [query], best first — the "Which
  /// one?" picker's geocode options when a name is ambiguous (a chain, or a
  /// name shared by places in different cities). Empty on failure.
  Future<List<GeocodeCandidate>> geocodeCandidates(
    String query, {
    int limit = 3,
  }) async {
    if (query.trim().isEmpty) return const [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '$limit',
    });
    try {
      final res = await _client
          .get(
            uri,
            headers: {
              'User-Agent':
                  'CheapTripChip/0.1 (draft; contact: dev@cheaptripchip.app)',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const [];
      final list = jsonDecode(res.body);
      if (list is! List) return const [];
      final out = <GeocodeCandidate>[];
      for (final item in list) {
        if (item is! Map) continue;
        final lat = double.tryParse('${item['lat']}');
        final lon = double.tryParse('${item['lon']}');
        if (lat == null || lon == null) continue;
        out.add(
          GeocodeCandidate(
            location: LatLng(lat, lon),
            displayName: '${item['display_name'] ?? ''}'.trim(),
          ),
        );
      }
      return out;
    } catch (_) {
      // Network/parse failure — caller falls back to a default location.
    }
    return const [];
  }

  /// Two results further apart than this are different real places, not
  /// one place mapped twice (a node and its building outline).
  static const ambiguityRadiusMeters = 2000.0;

  /// Whether [candidates] point at genuinely different places: at least two
  /// results more than [ambiguityRadiusMeters] from the top one.
  static bool isAmbiguous(List<GeocodeCandidate> candidates) {
    if (candidates.length < 2) return false;
    const distance = Distance();
    final top = candidates.first.location;
    return candidates
        .skip(1)
        .any(
          (c) =>
              distance.as(LengthUnit.Meter, top, c.location) >
              ambiguityRadiusMeters,
        );
  }

  void dispose() => _client.close();
}

/// One Nominatim match: where it is and OSM's full display name
/// (e.g. "Ichiran, 1-22-7, Jinnan, Shibuya, Tokyo, Japan").
class GeocodeCandidate {
  const GeocodeCandidate({required this.location, this.displayName = ''});

  final LatLng location;
  final String displayName;
}
