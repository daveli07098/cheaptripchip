import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../models/place.dart';

/// Google My Maps import: a shared My Maps link → its KML export → one
/// [MyMapsPlacemark] per point, grouped by layer ([MyMapsFolder]). Pure
/// Dart except [fetchKml]; turning placemarks into saved places and a board
/// is ImportService's job (lib/services/import_service.dart).

/// Thrown by [fetchKml] with a message that can be shown to the user as-is.
class MyMapsImportException implements Exception {
  const MyMapsImportException(this.message);

  final String message;

  static const notShared =
      "This map isn't shared. In My Maps: Share → "
      "'Anyone with the link can view'.";

  @override
  String toString() => message;
}

final _midParam = RegExp(r'[?&#]mid=([A-Za-z0-9_-]{10,})');
final _bareMid = RegExp(r'^[A-Za-z0-9_-]{20,}$');

/// The map id (`mid`) of a Google My Maps link found anywhere in [text] —
/// `…/maps/d/edit?mid=…`, `…/maps/d/viewer?mid=…`, `…/maps/d/u/0/viewer?…`,
/// `…/maps/d/kml?mid=…` — or [text] itself when the whole trimmed text is a
/// bare id. Null otherwise, so ordinary shared links (Instagram, TikTok,
/// Google Maps places) are never mistaken for a My Maps link.
String? parseMyMapsId(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (_bareMid.hasMatch(trimmed)) return trimmed;
  for (final match in RegExp(r'\S+').allMatches(trimmed)) {
    final token = match.group(0)!;
    if (!token.contains('/maps/d/')) continue;
    final mid = _midParam.firstMatch(token)?.group(1);
    if (mid != null) return mid;
  }
  return null;
}

/// KML export of map [mid] (`forcekml=1` asks for plain KML, not KMZ).
Uri kmlUrl(String mid) =>
    Uri.https('www.google.com', '/maps/d/kml', {'mid': mid, 'forcekml': '1'});

/// Downloads the KML of a link-shared map. A private map answers with a
/// non-200 or (after redirects) a Google sign-in HTML page, both reported as
/// [MyMapsImportException.notShared]. On web the request is blocked by CORS,
/// so it fails fast with an explanation instead of a network error.
Future<String> fetchKml(String mid, {http.Client? client}) async {
  if (kIsWeb) {
    throw const MyMapsImportException(
      'Importing from Google My Maps works in the phone app — the browser '
      'preview cannot download the map.',
    );
  }
  final httpClient = client ?? http.Client();
  try {
    final http.Response response;
    try {
      response = await httpClient
          .get(kmlUrl(mid))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('My Maps download failed: $e');
      throw const MyMapsImportException(
        "Couldn't download the map. Check your connection and try again.",
      );
    }
    if (response.statusCode != 200) {
      throw const MyMapsImportException(MyMapsImportException.notShared);
    }
    // Always UTF-8 (the KML prolog says so); `response.body` would guess
    // latin-1 when the content type omits a charset and garble CJK names.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (!body.contains('<kml')) {
      throw const MyMapsImportException(MyMapsImportException.notShared);
    }
    return body;
  } finally {
    if (client == null) httpClient.close();
  }
}

/// A parsed My Maps export.
class MyMapsDocument {
  const MyMapsDocument({required this.title, required this.folders});

  /// The map's title (KML `Document > name`), trimmed; may be empty.
  final String title;

  /// Layers in KML order.
  final List<MyMapsFolder> folders;

  int get placeCount => folders.fold(0, (sum, f) => sum + f.placemarks.length);
}

/// One My Maps layer (KML `Folder`).
class MyMapsFolder {
  const MyMapsFolder({required this.name, required this.placemarks});

  final String name;

  /// Point placemarks in KML order; lines/polygons are skipped.
  final List<MyMapsPlacemark> placemarks;

  int get count => placemarks.length;
}

/// One point from a My Maps layer, already mapped onto the app's model.
class MyMapsPlacemark {
  const MyMapsPlacemark({
    required this.name,
    required this.location,
    required this.category,
    this.iconCode,
    this.colour,
    this.myScore,
    this.notes = '',
    this.photoUrls = const [],
  });

  final String name;
  final LatLng location;

  /// My Maps icon code from the style id (`#icon-1577-BDBDBD-nodesc` →
  /// 1577), null when the placemark has no stock-icon style.
  final int? iconCode;

  /// Icon colour as upper-case hex without `#` (e.g. `0F9D58`), or null.
  final String? colour;

  final PlaceCategory category;

  /// 1–10, see [myMapsScore].
  final int? myScore;

  /// The description as plain text, see [descriptionToNotes].
  final String notes;

  final List<String> photoUrls;

  /// A new [Place] for this placemark. [mapTitle] becomes the source
  /// handle ("By <map> on Google My Maps" on the detail sheet).
  Place toPlace({required String id, required String mapTitle}) => Place(
    id: id,
    name: name,
    areaLabel: '',
    region: '',
    category: category,
    location: location,
    descriptionEn: '',
    originalCaption: '',
    address: '',
    hours: '',
    sourceHandle: mapTitle,
    sourcePlatform: SourcePlatform.googleMyMaps,
    photoUrls: photoUrls,
    myScore: myScore,
    myNotes: notes,
  );
}

/// Parses a My Maps KML export. Top-level `Folder`s become layers (nested
/// folders are flattened into their top-level layer); placemarks directly
/// under `Document` go into a trailing "Other" layer. Only `Point`
/// placemarks with valid coordinates are kept. Throws [FormatException]
/// when [xml] isn't KML.
MyMapsDocument parseMyMapsKml(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw FormatException('Not a KML file: ${e.message}');
  }
  final root = doc.rootElement;
  if (root.localName != 'kml') {
    throw const FormatException('Not a KML file');
  }
  final document = _child(root, 'Document') ?? root;
  final title = _childText(document, 'name');

  final folders = <MyMapsFolder>[];
  for (final folder in document.childElements) {
    if (folder.localName != 'Folder') continue;
    final name = _childText(folder, 'name');
    folders.add(
      MyMapsFolder(
        name: name.isEmpty ? 'Untitled layer' : name,
        placemarks: [
          for (final pm in folder.descendantElements)
            if (pm.localName == 'Placemark') ?_placemark(pm, name),
        ],
      ),
    );
  }
  final loose = [
    for (final pm in document.childElements)
      if (pm.localName == 'Placemark') ?_placemark(pm, ''),
  ];
  if (loose.isNotEmpty) {
    folders.add(MyMapsFolder(name: 'Other', placemarks: loose));
  }
  return MyMapsDocument(title: title, folders: folders);
}

final _styleUrl = RegExp(r'^#icon-(\d+)(?:-([0-9A-Fa-f]{6}))?');

MyMapsPlacemark? _placemark(XmlElement pm, String layer) {
  final point = _child(pm, 'Point');
  if (point == null) return null;
  final location = _coordinates(_childText(point, 'coordinates'));
  if (location == null) return null;

  final style = _styleUrl.firstMatch(_childText(pm, 'styleUrl'));
  final iconCode = style == null ? null : int.tryParse(style.group(1)!);
  final colour = style?.group(2)?.toUpperCase();
  final category = myMapsCategory(layer, iconCode);

  final html = _childText(pm, 'description');
  final notes = descriptionToNotes(html);
  final photos = <String>{..._imageUrls(html)};
  final extended = _child(pm, 'ExtendedData');
  if (extended != null) {
    for (final data in extended.childElements) {
      if (data.localName != 'Data' ||
          data.getAttribute('name') != 'gx_media_links') {
        continue;
      }
      photos.addAll(
        _childText(data, 'value').split(RegExp(r'\s+')).where(_isHttpUrl),
      );
    }
  }

  final name = _childText(pm, 'name');
  return MyMapsPlacemark(
    name: name.isEmpty ? 'Untitled place' : name,
    location: location,
    category: category,
    iconCode: iconCode,
    colour: colour,
    myScore: myMapsScore(colour: colour, notes: notes),
    notes: notes,
    photoUrls: photos.toList(),
  );
}

/// KML coordinates are `lng,lat[,alt]`.
LatLng? _coordinates(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+')).first.split(',');
  if (parts.length < 2) return null;
  final lng = double.tryParse(parts[0]);
  final lat = double.tryParse(parts[1]);
  if (lat == null || lng == null) return null;
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  // (0,0) is what a broken export looks like; the repositories treat it
  // as "no location" too.
  if (lat == 0 && lng == 0) return null;
  return LatLng(lat, lng);
}

XmlElement? _child(XmlElement parent, String localName) {
  for (final child in parent.childElements) {
    if (child.localName == localName) return child;
  }
  return null;
}

/// Text of the first [localName] child (CDATA included), trimmed; '' if none.
String _childText(XmlElement parent, String localName) =>
    _child(parent, localName)?.innerText.trim() ?? '';

bool _isHttpUrl(String s) =>
    s.startsWith('https://') || s.startsWith('http://');

final _imgSrc = RegExp(
  r'''<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']''',
  caseSensitive: false,
);

/// `<img src>` URLs (http/https only) in a placemark's description HTML.
List<String> _imageUrls(String html) => [
  for (final m in _imgSrc.allMatches(html))
    if (_isHttpUrl(_decodeEntities(m.group(1)!))) _decodeEntities(m.group(1)!),
];

// ---------------------------------------------------------------------------
// Mapping onto the app's model.

/// Layer names (lower-cased, substring match) → category. Checked in order.
const _layerKeywords = <(PlaceCategory, List<String>)>[
  (PlaceCategory.stay, ['hotel', 'stay', 'accommodation', '酒店', '住宿', '飯店']),
  (PlaceCategory.shopping, ['shop', 'store', '購物', '店舖', '商店']),
  (PlaceCategory.restaurant, ['food', 'restaurant', 'dining', '食', '餐']),
  (PlaceCategory.sightseeing, ['景點', '景点', 'sight', 'attraction', 'spot']),
];

/// My Maps stock icon codes whose meaning is clear from the icon itself and
/// from how they are used in real maps (cafés under the coffee cup, etc.).
/// Codes not listed fall back to the layer's category.
const _iconCategories = <int, PlaceCategory>{
  // Food & drink.
  1577: PlaceCategory.restaurant, // fork & knife
  1640: PlaceCategory.restaurant, // noodle bowl
  1835: PlaceCategory.restaurant, // sushi
  1530: PlaceCategory.restaurant, // burger / fast food
  1573: PlaceCategory.restaurant,
  1534: PlaceCategory.cafe, // coffee cup
  1517: PlaceCategory.cafe, // café
  1762: PlaceCategory.cafe, // café / bakery
  1607: PlaceCategory.cafe, // dessert / ice cream
  // Stay.
  1602: PlaceCategory.stay, // bed
  // Shopping.
  1684: PlaceCategory.shopping, // shopping bag
  1685: PlaceCategory.shopping, // shopping cart
  1549: PlaceCategory.shopping, // clothing
  // Sightseeing.
  1535: PlaceCategory.sightseeing, // camera
  1677: PlaceCategory.sightseeing, // temple / shrine
  1720: PlaceCategory.sightseeing, // park / tree
  1834: PlaceCategory.sightseeing, // museum
  1568: PlaceCategory.sightseeing, // amusement park
  1743: PlaceCategory.sightseeing, // zoo
  1596: PlaceCategory.sightseeing, // hiking
};

const _foodCategories = {
  PlaceCategory.restaurant,
  PlaceCategory.cafe,
  PlaceCategory.food,
  PlaceCategory.nightlife,
};

/// Category for a placemark in layer [layer] with icon [iconCode]. A layer
/// whose name says what it holds wins (a food layer only refines to a café
/// by icon); other layers (e.g. "temp") go by icon, else sightseeing.
PlaceCategory myMapsCategory(String layer, int? iconCode) {
  final byIcon = iconCode == null ? null : _iconCategories[iconCode];
  final name = layer.trim().toLowerCase();
  for (final (category, keywords) in _layerKeywords) {
    if (!keywords.any(name.contains)) continue;
    if (category == PlaceCategory.restaurant) {
      return byIcon != null && _foodCategories.contains(byIcon)
          ? byIcon
          : PlaceCategory.restaurant;
    }
    return category;
  }
  return byIcon ?? PlaceCategory.sightseeing;
}

/// My Maps' standard palette as the map legend uses it (for food icons):
/// green "good, would go again", yellow "mixed", red "don't go". Grey means
/// "not tried yet" and every other colour carries no score.
const _colourScores = {'0F9D58': 9, 'FFEA00': 5, 'FF5252': 2};

final _ratingInNotes = RegExp(
  r'(?:評分|评分|rating|score)\s*[:：]\s*(\d+(?:\.\d+)?)\s*/\s*(5|10)\b',
  caseSensitive: false,
);

/// The user's own 1–10 score: a written rating in the notes (`評分: 4/5`,
/// `Rating: 7/10`) wins; otherwise the icon colour (applied to every
/// category, though the map legend describes it for food). Null when
/// neither says anything.
int? myMapsScore({required String? colour, required String notes}) {
  final match = _ratingInNotes.firstMatch(notes);
  if (match != null) {
    final value = double.parse(match.group(1)!);
    final outOf = int.parse(match.group(2)!);
    if (value <= outOf) {
      final score = outOf == 5 ? value * 2 : value;
      return score.round().clamp(1, 10);
    }
  }
  if (colour == null) return null;
  return _colourScores[colour.toUpperCase()];
}

/// Longest notes kept per place.
const maxNotesLength = 1000;

final _br = RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false);
final _tag = RegExp(r'<[^>]*>');
final _blankLines = RegExp(r'\n{3,}');

/// A template line with nothing filled in: `備註:`, `評分: ?/5`.
final _emptyField = RegExp(r'^[^:：\n]{1,24}[:：]\s*(?:[?？]\s*/\s*\d+)?\s*$');

/// Placemark description HTML → plain notes: line breaks kept, images and
/// other tags dropped, entities decoded, unfilled template lines
/// (`備註:`, `評分: ?/5`) removed, capped at [maxNotesLength].
String descriptionToNotes(String html) {
  if (html.trim().isEmpty) return '';
  final text = _decodeEntities(
    html.replaceAll(_br, '\n').replaceAll(_tag, ''),
  ).replaceAll('\r', '');
  final lines = [
    for (final line in text.split('\n'))
      if (!_emptyField.hasMatch(line.trim())) line.trimRight(),
  ];
  final notes = lines.join('\n').replaceAll(_blankLines, '\n\n').trim();
  if (notes.length <= maxNotesLength) return notes;
  return '${notes.substring(0, maxNotesLength - 1).trimRight()}…';
}

final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);');
const _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

String _decodeEntities(String s) => s.replaceAllMapped(_entity, (m) {
  final body = m.group(1)!;
  int? code;
  if (body.startsWith('#x')) {
    code = int.tryParse(body.substring(2), radix: 16);
  } else if (body.startsWith('#')) {
    code = int.tryParse(body.substring(1));
  } else {
    return _namedEntities[body] ?? m.group(0)!;
  }
  if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
  return String.fromCharCode(code);
});
