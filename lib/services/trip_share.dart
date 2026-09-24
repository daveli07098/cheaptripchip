import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:latlong2/latlong.dart';

/// A named set of places to share — a [Board] flattened to its places, or
/// "all saved" places under a synthetic title. Pure data, no board/id ties.
class TripBundle {
  const TripBundle({required this.title, required this.places});

  final String title;
  final List<Place> places;
}

/// Sharing/export for a [TripBundle]: deep-link codec, a portable file
/// format, and Google Maps / KML interop. Pure Dart — no platform channels,
/// so it works on every target including web.
///
/// Callers own UI and deep-link *handling* (routing an incoming
/// `cheaptripchip://import` link into the app); this class only encodes and
/// decodes data.
class TripShare {
  TripShare._();

  // ---------------------------------------------------------------------
  // App link codec
  // ---------------------------------------------------------------------

  /// Custom URL scheme used for shareable import links.
  static const scheme = 'cheaptripchip';

  /// Host component of import links: `cheaptripchip://import?...`.
  static const host = 'import';

  /// Soft cap on encoded link length (messaging apps and QR codes get
  /// unwieldy well before this). See [linkFits].
  static const maxLinkLength = 6000;

  /// Builds a `cheaptripchip://import?v=1&d=<payload>` link for [bundle].
  ///
  /// The payload is base64url (no padding) of the gzip-compressed compact
  /// JSON produced by [_bundleToCompactJson] — only the fields needed to
  /// recreate each [Place] survive the round trip (see class docs on
  /// [_placeToCompactJson] for the exact subset).
  static Uri toAppLink(TripBundle bundle) {
    final jsonBytes = utf8.encode(jsonEncode(_bundleToCompactJson(bundle)));
    final gzipped = const GZipEncoder().encodeBytes(jsonBytes);
    final payload = base64Url.encode(gzipped).replaceAll('=', '');
    return Uri(
      scheme: scheme,
      host: host,
      queryParameters: {'v': '1', 'd': payload},
    );
  }

  /// Parses a link produced by [toAppLink]. Returns `null` — never
  /// throws — for the wrong scheme/host, an unsupported version, or any
  /// corrupt/foreign payload.
  static TripBundle? fromAppLink(Uri uri) {
    try {
      if (uri.scheme != scheme || uri.host != host) return null;
      if (uri.queryParameters['v'] != '1') return null;
      final payload = uri.queryParameters['d'];
      if (payload == null || payload.isEmpty) return null;

      final bytes = base64Url.decode(base64Url.normalize(payload));
      final jsonBytes = const GZipDecoder().decodeBytes(bytes);
      final decoded = jsonDecode(utf8.decode(jsonBytes));
      if (decoded is! Map) return null;
      return _bundleFromCompactJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Finds the first `cheaptripchip://import?...` link inside arbitrary
  /// text (e.g. a pasted chat message) and parses it via [fromAppLink].
  /// Returns `null` if no link is found or it fails to parse.
  static TripBundle? fromText(String text) {
    final match = _linkPattern.firstMatch(text);
    if (match == null) return null;
    try {
      return fromAppLink(Uri.parse(match.group(0)!));
    } catch (_) {
      return null;
    }
  }

  static final RegExp _linkPattern = RegExp(
    r'cheaptripchip://import\?[^\s<>"\047]+',
  );

  /// Whether [bundle]'s encoded [toAppLink] stays within [maxLinkLength].
  static bool linkFits(TripBundle bundle) =>
      toAppLink(bundle).toString().length <= maxLinkLength;

  // ---------------------------------------------------------------------
  // File format (.cheaptrip.json)
  // ---------------------------------------------------------------------

  static const _fileFormat = 'cheaptripchip.trip';
  static const _fileVersion = 1;

  /// Pretty-printed JSON file: `{format, version, title, places}`, using
  /// readable keys over the same field subset as the link payload.
  static String toFileJson(TripBundle bundle) {
    final map = {
      'format': _fileFormat,
      'version': _fileVersion,
      'title': bundle.title,
      'places': bundle.places.map(_placeToReadableJson).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Lenient parse counterpart to [toFileJson]. Returns `null` — never
  /// throws — for malformed JSON, wrong `format`/`version`, or any other
  /// unexpected shape.
  static TripBundle? fromFileJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      if (decoded['format'] != _fileFormat) return null;
      if (decoded['version'] != _fileVersion) return null;
      final placesJson = decoded['places'];
      if (placesJson is! List) return null;
      final places = placesJson
          .whereType<Map>()
          .map((m) => _placeFromReadableJson(Map<String, dynamic>.from(m)))
          .toList();
      return TripBundle(
        title: decoded['title'] as String? ?? '',
        places: places,
      );
    } catch (_) {
      return null;
    }
  }

  /// Slugified `<title>.cheaptrip.json` suitable for a downloaded/shared file.
  static String fileName(TripBundle bundle) =>
      '${_slugify(bundle.title)}.cheaptrip.json';

  // ---------------------------------------------------------------------
  // Google Maps
  // ---------------------------------------------------------------------

  /// A single place pinned in Google Maps by coordinates. Matches
  /// [Place.googleMapsUrl] — coordinates only (no name) is the form Google's
  /// URL API documents unambiguously for pinning an exact spot; see
  /// https://developers.google.com/maps/documentation/urls/get-started.
  static Uri googleMapsPlaceUrl(Place place) => Uri.parse(
    'https://www.google.com/maps/search/?api=1&query='
    '${place.location.latitude},${place.location.longitude}',
  );

  /// Google's directions URL API caps waypoints at 9 (11 points total with
  /// origin + destination). Extra places beyond that are dropped.
  static const maxRouteWaypoints = 9;
  static const _maxRoutePoints = maxRouteWaypoints + 2;

  /// A walking-directions link through [places] in order. `null` for an
  /// empty list; a single place returns [googleMapsPlaceUrl] instead of a
  /// route. Places beyond [_maxRoutePoints] are dropped (see
  /// [maxRouteWaypoints]).
  static Uri? googleMapsRouteUrl(List<Place> places) {
    if (places.isEmpty) return null;
    if (places.length == 1) return googleMapsPlaceUrl(places.first);

    final capped = places.length > _maxRoutePoints
        ? places.sublist(0, _maxRoutePoints)
        : places;
    final origin = capped.first;
    final destination = capped.last;
    final waypoints = capped.sublist(1, capped.length - 1);

    final params = <String, String>{
      'api': '1',
      'origin': _coords(origin),
      'destination': _coords(destination),
      'travelmode': 'walking',
    };
    if (waypoints.isNotEmpty) {
      params['waypoints'] = waypoints.map(_coords).join('|');
    }
    return Uri.https('www.google.com', '/maps/dir/', params);
  }

  static String _coords(Place p) =>
      '${p.location.latitude},${p.location.longitude}';

  // ---------------------------------------------------------------------
  // KML (imports into Google My Maps)
  // ---------------------------------------------------------------------

  /// Valid KML 2.2 document: `Document` named [TripBundle.title], one
  /// `Placemark` per place with an emoji-prefixed name, a description
  /// combining the note/address/source, and `Point` coordinates in KML's
  /// `lng,lat,0` order. All text content is XML-escaped.
  static String toKml(TripBundle bundle) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
      ..writeln('  <Document>')
      ..writeln('    <name>${_xmlEscape(bundle.title)}</name>');

    for (final place in bundle.places) {
      final name = '${place.category.emoji} ${place.name}'.trim();
      final source = _sourceString(place);
      final descriptionParts = [
        if (place.descriptionEn.isNotEmpty) place.descriptionEn,
        if (place.address.isNotEmpty) place.address,
        if (source != null) 'Source: $source',
      ];

      buffer
        ..writeln('    <Placemark>')
        ..writeln('      <name>${_xmlEscape(name)}</name>');
      if (descriptionParts.isNotEmpty) {
        buffer.writeln(
          '      <description>'
          '${_xmlEscape(descriptionParts.join(' — '))}'
          '</description>',
        );
      }
      buffer
        ..writeln('      <Point>')
        ..writeln(
          '        <coordinates>'
          '${place.location.longitude},${place.location.latitude},0'
          '</coordinates>',
        )
        ..writeln('      </Point>')
        ..writeln('    </Placemark>');
    }

    buffer
      ..writeln('  </Document>')
      ..writeln('</kml>');
    return buffer.toString();
  }

  /// Slugified `<title>.kml`.
  static String kmlFileName(TripBundle bundle) =>
      '${_slugify(bundle.title)}.kml';

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  // ---------------------------------------------------------------------
  // Compact JSON (link payload) — short keys, empty optionals omitted.
  // ---------------------------------------------------------------------

  static Map<String, dynamic> _bundleToCompactJson(TripBundle bundle) => {
    't': bundle.title,
    'p': bundle.places.map(_placeToCompactJson).toList(),
  };

  static TripBundle _bundleFromCompactJson(Map decoded) {
    final placesJson = decoded['p'];
    final places = placesJson is List
        ? placesJson
              .whereType<Map>()
              .map((m) => _placeFromCompactJson(Map<String, dynamic>.from(m)))
              .toList()
        : <Place>[];
    return TripBundle(title: decoded['t'] as String? ?? '', places: places);
  }

  /// Fields kept: name (`n`), coordinates (`lat`/`lng`), category (`c`,
  /// [PlaceCategory.name] — the emoji is derived from it on decode), and,
  /// only when non-empty, address (`addr`), area label (`area`), region
  /// (`reg`), source attribution (`src`, see [_sourceString]) and the
  /// English description (`note`). Dropped: id, photos, favourite flag,
  /// rating/reviewCount/priceRange/award, hours, original caption —
  /// nothing a recipient needs to see the place on a map.
  static Map<String, dynamic> _placeToCompactJson(Place p) {
    final source = _sourceString(p);
    return {
      'n': p.name,
      'lat': p.location.latitude,
      'lng': p.location.longitude,
      'c': p.category.name,
      if (p.address.isNotEmpty) 'addr': p.address,
      if (p.areaLabel.isNotEmpty) 'area': p.areaLabel,
      if (p.region.isNotEmpty) 'reg': p.region,
      'src': ?source,
      if (p.descriptionEn.isNotEmpty) 'note': p.descriptionEn,
    };
  }

  static Place _placeFromCompactJson(Map<String, dynamic> json) {
    final source = _parseSource(json['src'] as String?);
    return Place(
      id: _newId(),
      name: json['n'] as String? ?? '',
      areaLabel: json['area'] as String? ?? '',
      region: json['reg'] as String? ?? '',
      category: PlaceCategory.values.firstWhere(
        (e) => e.name == json['c'],
        orElse: () => PlaceCategory.sightseeing,
      ),
      location: LatLng(
        (json['lat'] as num?)?.toDouble() ?? 0,
        (json['lng'] as num?)?.toDouble() ?? 0,
      ),
      descriptionEn: json['note'] as String? ?? '',
      originalCaption: '',
      address: json['addr'] as String? ?? '',
      hours: '',
      sourceHandle: source.handle,
      sourcePlatform: source.platform,
    );
  }

  // ---------------------------------------------------------------------
  // Readable JSON (file format) — same field subset, long keys.
  // ---------------------------------------------------------------------

  static Map<String, dynamic> _placeToReadableJson(Place p) {
    final source = _sourceString(p);
    return {
      'name': p.name,
      'lat': p.location.latitude,
      'lng': p.location.longitude,
      'category': p.category.name,
      if (p.address.isNotEmpty) 'address': p.address,
      if (p.areaLabel.isNotEmpty) 'area': p.areaLabel,
      if (p.region.isNotEmpty) 'region': p.region,
      'source': ?source,
      if (p.descriptionEn.isNotEmpty) 'note': p.descriptionEn,
    };
  }

  static Place _placeFromReadableJson(Map<String, dynamic> json) {
    final source = _parseSource(json['source'] as String?);
    return Place(
      id: _newId(),
      name: json['name'] as String? ?? '',
      areaLabel: json['area'] as String? ?? '',
      region: json['region'] as String? ?? '',
      category: PlaceCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => PlaceCategory.sightseeing,
      ),
      location: LatLng(
        (json['lat'] as num?)?.toDouble() ?? 0,
        (json['lng'] as num?)?.toDouble() ?? 0,
      ),
      descriptionEn: json['note'] as String? ?? '',
      originalCaption: '',
      address: json['address'] as String? ?? '',
      hours: '',
      sourceHandle: source.handle,
      sourcePlatform: source.platform,
    );
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  /// [Place] has no source-URL field (only [Place.sourcePlatform] +
  /// [Place.sourceHandle], e.g. `@rame.nbon` on TikTok) — that pair, joined
  /// as `platform:handle`, stands in for the "source URL" field the export
  /// spec asks for. `null` when there's no handle to attribute.
  static String? _sourceString(Place p) => p.sourceHandle.isEmpty
      ? null
      : '${p.sourcePlatform.name}:${p.sourceHandle}';

  static ({SourcePlatform platform, String handle}) _parseSource(String? raw) {
    if (raw == null || raw.isEmpty) {
      return (platform: SourcePlatform.instagram, handle: '');
    }
    final i = raw.indexOf(':');
    if (i < 0) return (platform: SourcePlatform.instagram, handle: raw);
    final platformName = raw.substring(0, i);
    final handle = raw.substring(i + 1);
    final platform = SourcePlatform.values.firstWhere(
      (e) => e.name == platformName,
      orElse: () => SourcePlatform.instagram,
    );
    return (platform: platform, handle: handle);
  }

  static String _slugify(String title) {
    final slug = title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'trip' : slug;
  }

  /// Fresh, sender-independent ids for imported places — a counter folded
  /// into the current microsecond timestamp so ids stay unique even when
  /// many places import within the same microsecond.
  static int _idCounter = 0;

  static String _newId() {
    _idCounter++;
    return 'imported-${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }
}
