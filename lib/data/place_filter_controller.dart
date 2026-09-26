import 'package:flutter/material.dart';

import '../models/place.dart';
import 'map_filter.dart';

/// The active [MapFilter] + search text, shared by the Explore (map) and
/// Saved tabs — owned by the home shell, so a filter or search set on one
/// tab applies on the other. Screens built without one (tests, previews)
/// create their own.
///
/// [search] backs both tabs' search fields; its text is mirrored into
/// [filter]'s `query`, so listeners only need to watch this controller.
class PlaceFilterController extends ChangeNotifier {
  PlaceFilterController() {
    search.addListener(_onSearchChanged);
  }

  /// Shared by both search pills (each keeps its own [FocusNode]).
  final TextEditingController search = TextEditingController();

  /// Memoized indexes over the current snapshot — shared so switching tabs
  /// doesn't rebuild the drawer counts or board membership.
  final MapFilterCache cache = MapFilterCache();

  MapFilter _filter = const MapFilter();
  MapFilter get filter => _filter;

  /// Drawer section open/closed state, kept here so it survives the drawer
  /// being closed and reopened (and matches across tabs).
  bool _boardsExpanded = true;
  bool _areasExpanded = true;
  bool get boardsExpanded => _boardsExpanded;
  bool get areasExpanded => _areasExpanded;

  void toggleBoardsExpanded() {
    _boardsExpanded = !_boardsExpanded;
    notifyListeners();
  }

  void toggleAreasExpanded() {
    _areasExpanded = !_areasExpanded;
    notifyListeners();
  }

  void _onSearchChanged() {
    if (search.text == _filter.query) return;
    _set(_copy(query: search.text));
  }

  void _set(MapFilter next) {
    if (next == _filter) return;
    _filter = next;
    notifyListeners();
  }

  /// [_filter] with the given fields replaced; `null` is a real value for
  /// the nullable ones, so absent arguments use the [_keep] sentinel.
  MapFilter _copy({
    Object? category = _keep,
    Object? restaurantType = _keep,
    Object? city = _keep,
    Object? district = _keep,
    String? query,
    Set<String>? boards,
    bool? favoritesOnly,
  }) {
    final f = _filter;
    return MapFilter(
      category: identical(category, _keep)
          ? f.category
          : category as PlaceCategory?,
      restaurantType: identical(restaurantType, _keep)
          ? f.restaurantType
          : restaurantType as RestaurantType?,
      city: identical(city, _keep) ? f.city : city as String?,
      district: identical(district, _keep) ? f.district : district as String?,
      query: query ?? f.query,
      boards: boards ?? f.boards,
      favoritesOnly: favoritesOnly ?? f.favoritesOnly,
    );
  }

  /// null = "All"; any pick clears the restaurant sub-type.
  void setCategory(PlaceCategory? category) =>
      _set(_copy(category: category, restaurantType: null));

  /// A restaurant sub-type (implies the Restaurant category).
  void setRestaurantType(RestaurantType type) =>
      _set(_copy(category: PlaceCategory.restaurant, restaurantType: type));

  /// (null, null) = every area; ("", null) = Unknown area.
  void setArea(String? city, String? district) =>
      _set(_copy(city: city, district: district));

  void setFavoritesOnly(bool on) => _set(_copy(favoritesOnly: on));

  void toggleBoard(String key) {
    final boards = _filter.boards;
    _set(
      _copy(
        boards: boards.contains(key)
            ? ({...boards}..remove(key))
            : {...boards, key},
      ),
    );
  }

  void removeBoard(String key) {
    if (!_filter.boards.contains(key)) return;
    _set(_copy(boards: {..._filter.boards}..remove(key)));
  }

  void clearBoards() => _set(_copy(boards: const {}));

  /// Drops picked boards [exists] no longer knows (deleted, left, or "New
  /// finds" emptied) — they would hide every place with no chip to clear.
  void retainBoards(bool Function(String key) exists) {
    final kept = {
      for (final key in _filter.boards)
        if (exists(key)) key,
    };
    if (kept.length != _filter.boards.length) _set(_copy(boards: kept));
  }

  /// Clears every chip filter (favourites, category, area, boards) but
  /// keeps the search text — it has its own ✕.
  void clearFilters() => _set(MapFilter(query: _filter.query));

  /// "Show board X": only that board — every other filter and the search
  /// are cleared so none of its places stay hidden.
  void showOnlyBoard(String boardKey) {
    // Set first so the search listener sees an already-matching query.
    _filter = MapFilter(boards: {boardKey});
    search.clear();
    notifyListeners();
  }

  /// Clears every filter and the search — "Show this place on the map"
  /// when the current filters hide it.
  void showAll() {
    _filter = const MapFilter();
    search.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    search.removeListener(_onSearchChanged);
    search.dispose();
    super.dispose();
  }
}

const Object _keep = Object();
