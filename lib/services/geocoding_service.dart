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
    if (query.trim().isEmpty) return null;
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '1',
    });
    try {
      final res = await _client.get(uri, headers: {
        'User-Agent': 'CheapTripChip/0.1 (draft; contact: dev@cheaptripchip.app)',
      }).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body);
      if (list is List && list.isNotEmpty) {
        final first = list.first as Map<String, dynamic>;
        final lat = double.tryParse('${first['lat']}');
        final lon = double.tryParse('${first['lon']}');
        if (lat != null && lon != null) return LatLng(lat, lon);
      }
    } catch (_) {
      // Network/parse failure — caller falls back to a default location.
    }
    return null;
  }

  void dispose() => _client.close();
}
