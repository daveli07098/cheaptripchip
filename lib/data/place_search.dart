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
  final terms = _termsFor(query);
  if (terms.isEmpty) return true;
  final haystack = _haystacks[place] ??= _haystackOf(place);
  return terms.every(haystack.contains);
}

/// Callers filter a whole list with the same query, so the parsed terms of
/// the last query are kept rather than re-split once per place.
String? _lastQuery;
List<String> _lastTerms = const [];

List<String> _termsFor(String query) {
  if (query == _lastQuery) return _lastTerms;
  _lastQuery = query;
  return _lastTerms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList(growable: false);
}

/// Memoized per [Place] instance: building it runs restaurant-type keyword
/// detection and joins/lowercases ~11 fields, which per keystroke over a
/// 1,000+ place library was tens of milliseconds. Places are immutable (an
/// edit yields a new instance), so an identity-keyed [Expando] never goes
/// stale.
final Expando<String> _haystacks = Expando('placeSearchHaystack');

String _haystackOf(Place place) {
  // effectiveRestaurantType (stored value, else a keyword guess, else
  // "Other") rather than the raw field — so e.g. searching "ramen" finds a
  // restaurant whose type was only ever auto-detected, not explicitly set.
  final restaurantType = place.effectiveRestaurantType;
  return [
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
}
