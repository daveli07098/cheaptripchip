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

  /// Whether a rating is available to render (e.g. in the map-style info card).
  bool get hasRating => rating != null;

  /// Deep link that opens this location in Google Maps — just a URL, no API key.
  Uri get googleMapsUrl => Uri.parse(
    'https://www.google.com/maps/search/?api=1&query='
    '${location.latitude},${location.longitude}',
  );

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
    );
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
