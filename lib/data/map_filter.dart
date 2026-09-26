import 'package:flutter/foundation.dart';

import '../models/place.dart';
import 'place_search.dart';

/// [Place.effectiveRestaurantType], memoized per [Place] instance.
///
/// The getter re-runs keyword detection (join + lowercase five text fields,
/// then scan ~60 keywords) on every access, and the map hits it per place
/// per filter pass and per pin build. Places are immutable and an edit
/// yields a new instance, so an identity-keyed [Expando] is always fresh.
RestaurantType? restaurantTypeOf(Place place) {
  if (place.category != PlaceCategory.restaurant) return null;
  final cached = _restaurantTypes[place];
  if (cached != null) return cached;
  // Non-null for restaurants (detected, else RestaurantType.other).
  return _restaurantTypes[place] = place.effectiveRestaurantType!;
}

final Expando<RestaurantType> _restaurantTypes = Expando('restaurantType');

/// The map screen's active filters. Value-equal, so [MapFilterCache] can
/// tell "nothing changed" from "the user picked something".
@immutable
class MapFilter {
  const MapFilter({
    this.category,
    this.restaurantType,
    this.city,
    this.district,
    this.query = '',
  });

  /// null = "All".
  final PlaceCategory? category;

  /// null = every restaurant; only applies alongside
  /// `category == PlaceCategory.restaurant`.
  final RestaurantType? restaurantType;

  /// null = every area; "" = "Unknown area" (no city yet).
  final String? city;

  /// null = the whole [city].
  final String? district;

  /// Free-text search, matched via [placeMatches].
  final String query;

  bool matches(Place p) {
    if (category != null && p.category != category) return false;
    if (category == PlaceCategory.restaurant &&
        restaurantType != null &&
        restaurantTypeOf(p) != restaurantType) {
      return false;
    }
    if (city != null && p.city != city) return false;
    if (district != null && p.district != district) return false;
    return placeMatches(p, query);
  }

  @override
  bool operator ==(Object other) =>
      other is MapFilter &&
      other.category == category &&
      other.restaurantType == restaurantType &&
      other.city == city &&
      other.district == district &&
      other.query == query;

  @override
  int get hashCode =>
      Object.hash(category, restaurantType, city, district, query);
}

/// One city in the drawer's Areas section (see [AreaIndex]).
class CityGroup {
  CityGroup(this.city);

  final String city;
  String countryCode = '';
  int count = 0;
  final Map<String, int> districts = {};

  /// Districts by count desc, then name.
  List<MapEntry<String, int>> get sortedDistricts =>
      districts.entries.toList()..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
}

class AreaIndex {
  const AreaIndex({required this.cities, required this.unknownCount});

  final List<CityGroup> cities;
  final int unknownCount;

  CityGroup? _group(String city) {
    for (final group in cities) {
      if (group.city == city) return group;
    }
    return null;
  }

  String countryCodeOf(String city) => _group(city)?.countryCode ?? '';

  /// Places in [city] (and [district], when given); "" = Unknown area.
  int countOf(String city, String? district) {
    if (city.isEmpty) return unknownCount;
    final group = _group(city);
    if (group == null) return 0;
    return district == null ? group.count : (group.districts[district] ?? 0);
  }
}

/// Everything the map derives from one loaded snapshot, independent of the
/// active filters: the places safe to draw plus the drawer's counts.
class MapPlaceIndex {
  MapPlaceIndex._({
    required this.all,
    required this.counts,
    required this.restaurantTypeCounts,
    required this.areas,
  });

  factory MapPlaceIndex.from(List<Place> loaded) {
    // Drop places with non-finite coordinates: one NaN pin would crash the
    // map's camera and tile layer.
    final all = loaded.where(isFinitePlace).toList(growable: false);

    final counts = <PlaceCategory, int>{};
    final typeCounts = <RestaurantType, int>{};
    final byCity = <String, CityGroup>{};
    var unknown = 0;
    for (final p in all) {
      counts[p.category] = (counts[p.category] ?? 0) + 1;

      final type = restaurantTypeOf(p);
      if (type != null) typeCounts[type] = (typeCounts[type] ?? 0) + 1;

      final city = p.city;
      if (city.isEmpty) {
        unknown++;
        continue;
      }
      final group = byCity.putIfAbsent(city, () => CityGroup(city));
      group.count++;
      if (group.countryCode.isEmpty) group.countryCode = p.countryCode;
      final district = p.district;
      if (district.isNotEmpty) {
        group.districts[district] = (group.districts[district] ?? 0) + 1;
      }
    }
    final cities = byCity.values.toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.city.compareTo(b.city);
      });

    return MapPlaceIndex._(
      all: all,
      counts: counts,
      restaurantTypeCounts: typeCounts,
      areas: AreaIndex(cities: cities, unknownCount: unknown),
    );
  }

  /// Every loaded place with finite coordinates.
  final List<Place> all;

  /// Category counts over ALL places — deliberately not narrowed by search,
  /// so the drawer's numbers stay stable while the user types.
  final Map<PlaceCategory, int> counts;

  /// Restaurant sub-type counts over ALL places (same choice as [counts]),
  /// by [restaurantTypeOf] so an unset type counts under its detected guess.
  final Map<RestaurantType, int> restaurantTypeCounts;

  /// City → district counts over ALL places, cities by count desc then
  /// name; places without a city are in [AreaIndex.unknownCount].
  final AreaIndex areas;
}

bool isFinitePlace(Place p) =>
    p.location.latitude.isFinite && p.location.longitude.isFinite;

/// Memoizes the map's derived data so a rebuild with unchanged inputs does
/// no per-place work: [indexFor] is keyed on the loaded list's identity,
/// [visibleFor] additionally on the [MapFilter] value. Both return the
/// *same* instance until an input changes — downstream caches (clusters,
/// markers) rely on that identity.
class MapFilterCache {
  List<Place>? _loaded;
  MapPlaceIndex? _index;
  MapFilter? _filter;
  List<Place>? _visible;

  MapPlaceIndex indexFor(List<Place> loaded) {
    final cached = _index;
    if (cached != null && identical(loaded, _loaded)) return cached;
    _loaded = loaded;
    _visible = null;
    return _index = MapPlaceIndex.from(loaded);
  }

  List<Place> visibleFor(List<Place> loaded, MapFilter filter) {
    final index = indexFor(loaded);
    final cached = _visible;
    if (cached != null && filter == _filter) return cached;
    _filter = filter;
    return _visible = index.all.where(filter.matches).toList(growable: false);
  }
}
