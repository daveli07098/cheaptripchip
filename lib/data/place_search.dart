import '../models/place.dart';

/// Shared free-text matcher for [Place]s, used by both the map screen's
/// search bar and the saved feed's search field.
///
/// [query] is split on whitespace into terms; every term must match (AND)
/// somewhere across the searched fields, case-insensitively. Matching is a
/// plain substring check — deliberately NOT split further per-term for CJK
/// text (e.g. "池袋"), since CJK has no whitespace between words and a
/// substring match is what users expect there.
///
/// An empty (or whitespace-only) [query] matches every place.
bool placeMatches(Place place, String query) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty);
  if (terms.isEmpty) return true;

  // effectiveRestaurantType (stored value, else a keyword guess, else
  // "Other") rather than the raw field — so e.g. searching "ramen" finds a
  // restaurant whose type was only ever auto-detected, not explicitly set.
  final restaurantType = place.effectiveRestaurantType;
  final haystack = [
    place.name,
    place.areaLabel,
    place.region,
    place.address,
    place.descriptionEn,
    place.myNotes,
    place.category.labelEn,
    place.category.labelZh,
    if (restaurantType != null) restaurantType.labelEn,
    if (restaurantType != null) restaurantType.labelZh,
    place.sourceHandle,
  ].join('\n').toLowerCase();

  return terms.every(haystack.contains);
}
