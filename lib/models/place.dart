import 'package:latlong2/latlong.dart';

/// A saved travel find — extracted from a shared IG/TikTok post.
///
/// In the draft this is populated from mock data; in production the same shape
/// is filled by the backend AI-extraction + geocoding pipeline (see ANALYSIS.md).
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.areaLabel,
    required this.region,
    required this.category,
    required this.location,
    required this.descriptionEn,
    required this.originalCaption,
    required this.address,
    required this.hours,
    required this.sourceHandle,
    required this.sourcePlatform,
    this.award,
    this.matchConfident = true,
    this.rating,
    this.reviewCount,
    this.priceRange,
    this.photoUrls = const [],
    this.isFavorite = false,
    this.myScore,
    this.myNotes = '',
  });

  final String id;

  /// Place name, original language preserved (e.g. "五感 (Gogo)").
  final String name;

  /// Short area tag shown as a badge (e.g. "池袋").
  final String areaLabel;

  /// Human region label (e.g. "Tokyo, Japan").
  final String region;

  final PlaceCategory category;

  final LatLng location;

  /// AI-generated English summary of the place.
  final String descriptionEn;

  /// Original caption from the source post, language preserved.
  final String originalCaption;

  /// Full address, original language preserved.
  final String address;

  /// Opening hours, free-form.
  final String hours;

  /// Source attribution handle, e.g. "@rame.nbon".
  final String sourceHandle;

  final SourcePlatform sourcePlatform;

  /// Optional award/recognition (e.g. "Michelin Bib Gourmand").
  final String? award;

  /// Mirrors Yaay's "1match" badge — whether the AI geocode resolved confidently.
  final bool matchConfident;

  /// Average rating out of 5, e.g. 4.7. Null if not extracted/known.
  final double? rating;

  /// Number of reviews backing [rating], e.g. 85.
  final int? reviewCount;

  /// Free-form price indicator in the original currency, e.g. "$600–1,400" or "$200–400".
  final String? priceRange;

  /// Photo URLs for the place. Empty until a real photo source is wired up.
  final List<String> photoUrls;

  /// Whether the user has favourited this place. In-memory via PlaceStore
  /// until the Firebase layer lands.
  final bool isFavorite;

  /// The user's own rating out of 10 (1–10), distinct from [rating] (the
  /// source's rating out of 5, e.g. scraped from the post). Null means not
  /// rated yet — see [copyWith]'s `clearMyScore` for how to reset it.
  final int? myScore;

  /// The user's own free-form notes about the place, distinct from
  /// [descriptionEn] (AI-generated) and [originalCaption] (from the source
  /// post). Empty string when the user hasn't written any.
  final String myNotes;

  /// Whether a rating is available to render (e.g. in the map-style info card).
  bool get hasRating => rating != null;

  /// Deep link that opens this location in Google Maps — just a URL, no API key.
  /// What Google Maps searches for: name plus address (or area/region) so it
  /// opens the place card — name, reviews, hours — instead of a bare
  /// coordinate pin. Falls back to coordinates when there is no name.
  String get googleMapsQuery {
    if (name.trim().isEmpty) {
      return '${location.latitude},${location.longitude}';
    }
    final context = address.trim().isNotEmpty
        ? address.trim()
        : [
            areaLabel.trim(),
            region.trim(),
          ].where((s) => s.isNotEmpty).join(', ');
    return context.isEmpty ? name.trim() : '${name.trim()}, $context';
  }

  Uri get googleMapsUrl => Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': googleMapsQuery,
  });

  Place copyWith({
    String? id,
    String? name,
    String? areaLabel,
    String? region,
    PlaceCategory? category,
    LatLng? location,
    String? descriptionEn,
    String? originalCaption,
    String? address,
    String? hours,
    String? sourceHandle,
    SourcePlatform? sourcePlatform,
    String? award,
    bool? matchConfident,
    double? rating,
    int? reviewCount,
    String? priceRange,
    List<String>? photoUrls,
    bool? isFavorite,
    int? myScore,

    /// When true, clears [Place.myScore] to null regardless of [myScore]
    /// (the `foo ?? this.foo` idiom used elsewhere can't express "set to
    /// null" — plain field nullability is ambiguous with "unchanged").
    bool clearMyScore = false,
    String? myNotes,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      areaLabel: areaLabel ?? this.areaLabel,
      region: region ?? this.region,
      category: category ?? this.category,
      location: location ?? this.location,
      descriptionEn: descriptionEn ?? this.descriptionEn,
      originalCaption: originalCaption ?? this.originalCaption,
      address: address ?? this.address,
      hours: hours ?? this.hours,
      sourceHandle: sourceHandle ?? this.sourceHandle,
      sourcePlatform: sourcePlatform ?? this.sourcePlatform,
      award: award ?? this.award,
      matchConfident: matchConfident ?? this.matchConfident,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      priceRange: priceRange ?? this.priceRange,
      photoUrls: photoUrls ?? this.photoUrls,
      isFavorite: isFavorite ?? this.isFavorite,
      myScore: clearMyScore ? null : (myScore ?? this.myScore),
      myNotes: myNotes ?? this.myNotes,
    );
  }

  /// Serializes to plain JSON types only (no [LatLng]/enum objects) so this
  /// can be written directly to Firestore. [location] becomes `{'lat', 'lng'}`
  /// and enums are stored by their [Enum.name].
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'areaLabel': areaLabel,
      'region': region,
      'category': category.name,
      'location': {'lat': location.latitude, 'lng': location.longitude},
      'descriptionEn': descriptionEn,
      'originalCaption': originalCaption,
      'address': address,
      'hours': hours,
      'sourceHandle': sourceHandle,
      'sourcePlatform': sourcePlatform.name,
      'award': award,
      'matchConfident': matchConfident,
      'rating': rating,
      'reviewCount': reviewCount,
      'priceRange': priceRange,
      'photoUrls': photoUrls,
      'isFavorite': isFavorite,
      'myScore': myScore,
      'myNotes': myNotes,
    };
  }

  /// Lenient parse counterpart to [toJson]. Missing/null optional fields fall
  /// back to the same defaults as the constructor; unrecognized enum names
  /// fall back to [PlaceCategory.sightseeing] / [SourcePlatform.instagram]
  /// (the most common defaults seen in mock data) rather than throwing;
  /// numeric fields accept either `int` or `double` from JSON.
  factory Place.fromJson(Map<String, dynamic> json) {
    final locationJson = json['location'] as Map?;
    return Place(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      areaLabel: json['areaLabel'] as String? ?? '',
      region: json['region'] as String? ?? '',
      category: PlaceCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => PlaceCategory.sightseeing,
      ),
      location: LatLng(
        (locationJson?['lat'] as num?)?.toDouble() ?? 0,
        (locationJson?['lng'] as num?)?.toDouble() ?? 0,
      ),
      descriptionEn: json['descriptionEn'] as String? ?? '',
      originalCaption: json['originalCaption'] as String? ?? '',
      address: json['address'] as String? ?? '',
      hours: json['hours'] as String? ?? '',
      sourceHandle: json['sourceHandle'] as String? ?? '',
      sourcePlatform: SourcePlatform.values.firstWhere(
        (e) => e.name == json['sourcePlatform'],
        orElse: () => SourcePlatform.instagram,
      ),
      award: json['award'] as String?,
      matchConfident: json['matchConfident'] as bool? ?? true,
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: (json['reviewCount'] as num?)?.toInt(),
      priceRange: json['priceRange'] as String?,
      photoUrls:
          (json['photoUrls'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      isFavorite: json['isFavorite'] as bool? ?? false,
      myScore: _parseMyScore(json['myScore']),
      myNotes: json['myNotes'] is String ? json['myNotes'] as String : '',
    );
  }

  /// Lenient parse for [myScore]: accepts any numeric type (Firestore hands
  /// back `int`, `jsonDecode` may hand back a whole `double`), clamps into
  /// 1..10, and falls back to `null` (not rated) for anything else —
  /// non-numeric garbage, missing, or explicit null.
  static int? _parseMyScore(dynamic raw) {
    if (raw is! num || !raw.isFinite) return null;
    return raw.round().clamp(1, 10).toInt();
  }
}

enum PlaceCategory {
  restaurant('Restaurant', '餐廳', '🍽️'),
  cafe('Cafe', '咖啡店', '☕'),
  food('Food', '美食', '🍜'),
  sightseeing('Sightseeing', '景點', '⛩️'),
  shopping('Shopping', '購物', '🛍️'),
  stay('Stay', '住宿', '🏨'),
  nightlife('Nightlife', '夜生活', '🍸');

  const PlaceCategory(this.labelEn, this.labelZh, this.emoji);

  final String labelEn;
  final String labelZh;
  final String emoji;
}

enum SourcePlatform {
  instagram('Instagram'),
  tiktok('TikTok');

  const SourcePlatform(this.label);

  final String label;
}
