import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../models/place.dart';
import '../models/place_area.dart';
import '../models/shared_board.dart';
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

/// The emoji that marks [place] everywhere it is shown (map pin, list row,
/// preview card, feed card): a restaurant's sub-type (🍜 Ramen, 🍣 Sushi…)
/// when known, otherwise the category emoji. "Other" restaurants keep the
/// generic 🍽️. Uses the memoized [restaurantTypeOf] — pins rebuild on
/// camera moves, and the raw getter re-runs keyword detection every call.
String placeMarkerEmoji(Place place) {
  final type = restaurantTypeOf(place);
  if (type != null && type != RestaurantType.other) return type.emoji;
  return place.category.emoji;
}

/// Accessible name matching [placeMarkerEmoji] (WCAG 1.4.1).
String placeMarkerLabel(Place place) {
  final type = restaurantTypeOf(place);
  if (type != null && type != RestaurantType.other) return type.labelEn;
  return place.category.labelEn;
}

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
    this.boards = const {},
    this.favoritesOnly = false,
    this.aiPlaceIds,
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

  /// [BoardRef.key]s; empty = every place. A place matches when it is on
  /// ANY of them (resolved through a [BoardIndex]); ANDed with the rest.
  final Set<String> boards;

  /// Only places marked [Place.isFavorite].
  final bool favoritesOnly;

  /// "Ask your places" results, ranked best-first; null = not asking. When
  /// set it replaces the free-text [query] match (the query is then the
  /// question, which would match nothing word-by-word) and is ANDed with
  /// the chip filters. Not counted in [activeCount] — it has its own chip.
  final Set<String>? aiPlaceIds;

  bool get hasAiResults => aiPlaceIds != null;

  /// How many chip-style filters are on (search [query] not counted) —
  /// the chip row offers "Clear all" from two up.
  int get activeCount =>
      (favoritesOnly ? 1 : 0) +
      (category != null ? 1 : 0) +
      (city != null ? 1 : 0) +
      boards.length;

  bool get hasActiveFilters => activeCount > 0;

  /// Whether [p] passes every filter. [boardIndex] resolves [boards]; a
  /// board filter with no index matches nothing.
  bool matches(Place p, {BoardIndex? boardIndex}) {
    if (favoritesOnly && !p.isFavorite) return false;
    if (category != null && p.category != category) return false;
    if (category == PlaceCategory.restaurant &&
        restaurantType != null &&
        restaurantTypeOf(p) != restaurantType) {
      return false;
    }
    if (city != null && p.city != city) return false;
    if (district != null && p.district != district) return false;
    if (boards.isNotEmpty) {
      final index = boardIndex;
      if (index == null || !boards.any((key) => index.isOn(key, p.id))) {
        return false;
      }
    }
    if (aiPlaceIds case final ids?) return ids.contains(p.id);
    return placeMatches(p, query);
  }

  @override
  bool operator ==(Object other) =>
      other is MapFilter &&
      other.category == category &&
      other.restaurantType == restaurantType &&
      other.city == city &&
      other.district == district &&
      other.query == query &&
      other.favoritesOnly == favoritesOnly &&
      setEquals(other.boards, boards) &&
      // Ordered: the same ids re-ranked is a different result.
      listEquals(other.aiPlaceIds?.toList(), aiPlaceIds?.toList());

  @override
  int get hashCode => Object.hash(
    category,
    restaurantType,
    city,
    district,
    query,
    favoritesOnly,
    Object.hashAllUnordered(boards),
    aiPlaceIds == null ? null : Object.hashAll(aiPlaceIds!),
  );
}

/// [places] in [MapFilter.aiPlaceIds] rank order when AI results are on
/// (places not in the ranking keep their relative order, last); else
/// [places] itself.
List<Place> rankedForFilter(List<Place> places, MapFilter filter) {
  final ids = filter.aiPlaceIds;
  if (ids == null || places.length < 2) return places;
  final rank = <String, int>{};
  for (final id in ids) {
    rank[id] = rank.length;
  }
  final indexed = [for (var i = 0; i < places.length; i++) (i, places[i])]
    ..sort((a, b) {
      final byRank = (rank[a.$2.id] ?? rank.length).compareTo(
        rank[b.$2.id] ?? rank.length,
      );
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  return [for (final (_, p) in indexed) p].toList(growable: false);
}

/// One board as the map sees it: the drawer's Boards rows, the chips, and
/// the preview card's "which boards" line.
@immutable
class BoardRef {
  const BoardRef({
    required this.key,
    required this.id,
    required this.name,
    required this.emoji,
    this.shared = false,
  });

  /// Unique across personal and shared boards (see [keyFor]) — what
  /// [MapFilter.boards] holds.
  final String key;
  final String id;
  final String name;
  final String emoji;
  final bool shared;

  /// The auto "New finds" board: places no board references.
  bool get isAuto => key == kNewFindsBoardId;

  /// Personal board ids are used as-is; shared ones get a `shared/` prefix
  /// so the two id spaces can never collide.
  static String keyFor(String boardId, {bool shared = false}) =>
      shared ? 'shared/$boardId' : boardId;

  @override
  bool operator ==(Object other) =>
      other is BoardRef &&
      other.key == key &&
      other.name == name &&
      other.emoji == emoji &&
      other.shared == shared;

  @override
  int get hashCode => Object.hash(key, name, emoji, shared);
}

/// Place ↔ board membership for the map, built once per (places, personal
/// boards, shared boards) snapshot in O(places + board entries) — so the
/// board filter, drawer counts and preview card never scan every board.
class BoardIndex {
  const BoardIndex._(this.boards, this._byPlace, this._placeIds, this._counts);

  static const empty = BoardIndex._([], {}, {}, {});

  /// [places] should be the map's drawable places ([MapPlaceIndex.all]):
  /// counts are "pins on the map", and the auto "New finds" board holds
  /// the ones no board references. Shared boards count as referencing
  /// their places, same as the Boards tab.
  factory BoardIndex.from({
    required List<Place> places,
    List<Board> personal = const [],
    List<SharedBoard> shared = const [],
  }) {
    final byPlace = <String, List<BoardRef>>{};
    final placeIds = <String, Set<String>>{};
    final refs = <BoardRef>[];

    void addBoard(BoardRef ref, List<BoardSection> sections) {
      refs.add(ref);
      final ids = placeIds[ref.key] = {
        for (final section in sections) ...section.placeIds,
      };
      for (final id in ids) {
        (byPlace[id] ??= []).add(ref);
      }
    }

    // Boards tab order: shared, then personal ("New finds" goes first once
    // we know whether it has any places).
    for (final board in shared) {
      addBoard(
        BoardRef(
          key: BoardRef.keyFor(board.id, shared: true),
          id: board.id,
          name: board.name,
          emoji: board.emoji,
          shared: true,
        ),
        board.sections,
      );
    }
    for (final board in personal) {
      addBoard(
        BoardRef(
          key: BoardRef.keyFor(board.id),
          id: board.id,
          name: board.name,
          emoji: board.emoji,
        ),
        board.sections,
      );
    }

    const auto = BoardRef(
      key: kNewFindsBoardId,
      id: kNewFindsBoardId,
      name: 'New finds',
      emoji: '📌',
    );
    final counts = <String, int>{};
    final unreferenced = <String>{};
    for (final p in places) {
      final on = byPlace[p.id];
      if (on == null) {
        unreferenced.add(p.id);
        continue;
      }
      for (final ref in on) {
        counts[ref.key] = (counts[ref.key] ?? 0) + 1;
      }
    }
    if (unreferenced.isNotEmpty) {
      refs.insert(0, auto);
      placeIds[auto.key] = unreferenced;
      counts[auto.key] = unreferenced.length;
      const autoOnly = [auto];
      for (final id in unreferenced) {
        byPlace[id] = autoOnly;
      }
    }
    return BoardIndex._(refs, byPlace, placeIds, counts);
  }

  /// Every board, Boards-tab order: "New finds" (when it has places),
  /// shared, personal.
  final List<BoardRef> boards;
  final Map<String, List<BoardRef>> _byPlace;
  final Map<String, Set<String>> _placeIds;
  final Map<String, int> _counts;

  /// The boards [placeId] is on — just "New finds" when none.
  List<BoardRef> boardsOf(String placeId) => _byPlace[placeId] ?? const [];

  bool isOn(String boardKey, String placeId) =>
      _placeIds[boardKey]?.contains(placeId) ?? false;

  /// Places on board [boardKey] that are on the map.
  int countOf(String boardKey) => _counts[boardKey] ?? 0;

  BoardRef? byKey(String key) {
    for (final ref in boards) {
      if (ref.key == key) return ref;
    }
    return null;
  }
}

/// Case-insensitive A–Z, ties broken by the raw string for a stable order.
int _alphabetical(String a, String b) {
  final byName = a.toLowerCase().compareTo(b.toLowerCase());
  return byName != 0 ? byName : a.compareTo(b);
}

/// One city in the drawer's Areas section (see [AreaIndex]).
class CityGroup {
  CityGroup(this.city);

  final String city;
  String countryCode = '';
  int count = 0;
  final Map<String, int> districts = {};

  /// Districts A–Z.
  List<MapEntry<String, int>> get sortedDistricts =>
      districts.entries.toList()..sort((a, b) => _alphabetical(a.key, b.key));
}

/// One country in the drawer's Areas section: its cities A–Z. [code] is
/// empty for cities whose country isn't known yet.
class CountryGroup {
  CountryGroup(this.code, this.cities)
    : name = countryName(code),
      count = cities.fold(0, (sum, c) => sum + c.count);

  final String code;

  /// [countryName] of [code] ("Unknown country" when empty).
  final String name;
  final List<CityGroup> cities;
  final int count;
}

class AreaIndex {
  const AreaIndex({
    required this.cities,
    required this.unknownCount,
    this.countries = const [],
  });

  /// Every city, A–Z.
  final List<CityGroup> cities;

  /// Country → city grouping of [cities]: countries A–Z by display name,
  /// "Unknown country" last. A city sits under the country of the first
  /// place seen in it.
  final List<CountryGroup> countries;

  /// Places with no city yet ("Unknown area", listed after every country).
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
    required this.favoriteCount,
  });

  factory MapPlaceIndex.from(List<Place> loaded) {
    // Drop places with non-finite coordinates: one NaN pin would crash the
    // map's camera and tile layer.
    final all = loaded.where(isFinitePlace).toList(growable: false);

    final counts = <PlaceCategory, int>{};
    final typeCounts = <RestaurantType, int>{};
    final byCity = <String, CityGroup>{};
    var unknown = 0;
    var favorites = 0;
    for (final p in all) {
      if (p.isFavorite) favorites++;
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
      ..sort((a, b) => _alphabetical(a.city, b.city));
    final byCountry = <String, List<CityGroup>>{};
    for (final group in cities) {
      (byCountry[group.countryCode] ??= []).add(group);
    }
    final countries =
        [
          for (final entry in byCountry.entries)
            CountryGroup(entry.key, entry.value),
        ]..sort((a, b) {
          if (a.code.isEmpty != b.code.isEmpty) return a.code.isEmpty ? 1 : -1;
          return _alphabetical(a.name, b.name);
        });

    return MapPlaceIndex._(
      all: all,
      counts: counts,
      restaurantTypeCounts: typeCounts,
      areas: AreaIndex(
        cities: cities,
        countries: countries,
        unknownCount: unknown,
      ),
      favoriteCount: favorites,
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

  /// Country → city → district counts over ALL places, each level A–Z;
  /// places without a city are in [AreaIndex.unknownCount].
  final AreaIndex areas;

  /// Favourite places over ALL places (same choice as [counts]).
  final int favoriteCount;
}

bool isFinitePlace(Place p) =>
    p.location.latitude.isFinite && p.location.longitude.isFinite;

/// Memoizes the map's derived data so a rebuild with unchanged inputs does
/// no per-place work: [indexFor] is keyed on the loaded list's identity,
/// [boardsFor] additionally on the board lists' identities, [visibleFor]
/// on all of those plus the [MapFilter] value. Each returns the *same*
/// instance until an input changes — downstream caches (clusters, markers)
/// rely on that identity.
class MapFilterCache {
  List<Place>? _loaded;
  MapPlaceIndex? _index;
  MapFilter? _filter;
  BoardIndex? _visibleBoards;
  List<Place>? _visible;

  List<Place>? _boardsLoaded;
  List<Board>? _personal;
  List<SharedBoard>? _shared;
  BoardIndex? _boardIndex;

  MapPlaceIndex indexFor(List<Place> loaded) {
    final cached = _index;
    if (cached != null && identical(loaded, _loaded)) return cached;
    _loaded = loaded;
    _visible = null;
    return _index = MapPlaceIndex.from(loaded);
  }

  BoardIndex boardsFor(
    List<Place> loaded,
    List<Board> personal,
    List<SharedBoard> shared,
  ) {
    final all = indexFor(loaded).all;
    final cached = _boardIndex;
    if (cached != null &&
        identical(loaded, _boardsLoaded) &&
        identical(personal, _personal) &&
        identical(shared, _shared)) {
      return cached;
    }
    _boardsLoaded = loaded;
    _personal = personal;
    _shared = shared;
    return _boardIndex = BoardIndex.from(
      places: all,
      personal: personal,
      shared: shared,
    );
  }

  /// [boards] resolves [MapFilter.boards] (see [boardsFor]); a changed
  /// index recomputes even when the filter is equal — the same selection
  /// can match different places after a board edit.
  List<Place> visibleFor(
    List<Place> loaded,
    MapFilter filter, {
    BoardIndex boards = BoardIndex.empty,
  }) {
    final index = indexFor(loaded);
    final cached = _visible;
    if (cached != null &&
        filter == _filter &&
        (filter.boards.isEmpty || identical(boards, _visibleBoards))) {
      return cached;
    }
    _filter = filter;
    _visibleBoards = boards;
    return _visible = rankedForFilter(
      index.all
          .where((p) => filter.matches(p, boardIndex: boards))
          .toList(growable: false),
      filter,
    );
  }
}
