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

  /// Deep link that opens this location in Google Maps — just a URL, no API key.
  Uri get googleMapsUrl =>
      Uri.parse('https://www.google.com/maps/search/?api=1&query='
          '${location.latitude},${location.longitude}');
}

enum PlaceCategory {
  restaurant('Restaurant', '餐廳'),
  food('Food', '美食'),
  sightseeing('Sightseeing', '景點'),
  shopping('Shopping', '購物'),
  stay('Stay', '住宿'),
  nightlife('Nightlife', '夜生活');

  const PlaceCategory(this.labelEn, this.labelZh);

  final String labelEn;
  final String labelZh;
}

enum SourcePlatform {
  instagram('Instagram'),
  tiktok('TikTok');

  const SourcePlatform(this.label);

  final String label;
}
