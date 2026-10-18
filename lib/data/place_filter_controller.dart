import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../services/ai_search.dart';
import 'map_filter.dart';

/// The active [MapFilter] + search text, shared by the Explore (map) and
/// Saved tabs — owned by the home shell, so a filter or search set on one
/// tab applies on the other. Screens built without one (tests, previews)
/// create their own.
///
/// [search] backs both tabs' search fields; its text is mirrored into
/// [filter]'s `query`, so listeners only need to watch this controller.
///
/// It also runs "Ask your places" ([ask]): the answer's ranked ids become
/// [MapFilter.aiPlaceIds] (the "AI results" chip on both tabs) and its
/// explanation [aiResult]. Editing the question, its ✕, [clearAiResults],
/// [showAll] and [showOnlyBoard] all drop them.
class PlaceFilterController extends ChangeNotifier {
  /// [aiSearch] replaces the Gemini-backed default (tests).
  PlaceFilterController({AiSearch? aiSearch}) : _aiSearch = aiSearch {
    search.addListener(_onSearchChanged);
  }

  AiSearch? _aiSearch;
  bool _ownsAiSearch = false;
  AiSearch get aiSearch {
    if (_aiSearch case final given?) return given;
    _ownsAiSearch = true;
    return _aiSearch = AiSearch();
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

  /// The last "Ask" answer while its results are shown; null otherwise.
  AskResult? _aiResult;
  AskResult? get aiResult => _aiResult;

  /// Whether an [ask] is in flight (the pill shows a spinner).
  bool _asking = false;
  bool get asking => _asking;

  /// Bumped per [ask] and whenever its answer must be discarded (the user
  /// edited the question, cleared, or asked again).
  int _askTicket = 0;
  bool _disposed = false;

  /// The map's visible centre, kept up to date by the map screen — what
  /// "near me" means without a location permission (also when asking from
  /// the Saved tab). Not a notifying field.
  LatLng? mapCenter;

  /// Grounded suggestion chips ([askSuggestionsFor]), memoized per loaded
  /// list.
  List<Place>? _suggestionsFor;
  List<String> _suggestions = const [];
  List<String> suggestionsFor(List<Place> loaded) {
    if (identical(loaded, _suggestionsFor)) return _suggestions;
    _suggestionsFor = loaded;
    return _suggestions = askSuggestionsFor(loaded);
  }

  void _onSearchChanged() {
    if (search.text == _filter.query) return;
    if (_filter.hasAiResults || _asking) {
      // Editing the question makes the shown answer (or the pending one)
      // stale — back to plain search.
      _dropAi();
      _filter = _copy(query: search.text, aiPlaceIds: null);
      notifyListeners();
      return;
    }
    _set(_copy(query: search.text));
  }

  /// Asks [question] over [places] ("near" = [near], else [mapCenter]) and
  /// shows the answer as AI results; the question stays in the search
  /// field. Returns null when superseded (edited, cleared, asked again).
  Future<AskResult?> ask(
    String question, {
    required List<Place> places,
    BoardIndex? boards,
    LatLng? near,
  }) async {
    final q = question.trim();
    if (q.isEmpty) return null;
    final ticket = ++_askTicket;
    _asking = true;
    // Show the question as typed; set the query first so the search
    // listener sees it as already applied.
    if (search.text != q) {
      _filter = _copy(query: q, aiPlaceIds: null);
      _aiResult = null;
      search.text = q;
    }
    notifyListeners();
    final result = await aiSearch.ask(
      q,
      places: places,
      boards: boards,
      near: near ?? mapCenter,
    );
    if (_disposed || ticket != _askTicket) return null;
    _asking = false;
    _aiResult = result;
    _filter = _copy(query: q, aiPlaceIds: {...result.placeIds});
    notifyListeners();
    return result;
  }

  /// The AI chip's ✕: drops the results and the question.
  void clearAiResults() {
    _askTicket++;
    _asking = false;
    _aiResult = null;
    _filter = _copy(query: '', aiPlaceIds: null);
    search.clear();
    notifyListeners();
  }

  /// Forgets any shown or pending answer (no notify — callers do).
  void _dropAi() {
    _askTicket++;
    _asking = false;
    _aiResult = null;
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
    Object? aiPlaceIds = _keep,
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
      aiPlaceIds: identical(aiPlaceIds, _keep)
          ? f.aiPlaceIds
          : aiPlaceIds as Set<String>?,
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
  /// keeps the search text and any AI results — each has its own ✕.
  void clearFilters() =>
      _set(MapFilter(query: _filter.query, aiPlaceIds: _filter.aiPlaceIds));

  /// "Show board X": only that board — every other filter and the search
  /// are cleared so none of its places stay hidden.
  void showOnlyBoard(String boardKey) {
    // Set first so the search listener sees an already-matching query.
    _dropAi();
    _filter = MapFilter(boards: {boardKey});
    search.clear();
    notifyListeners();
  }

  /// Clears every filter and the search — "Show this place on the map"
  /// when the current filters hide it.
  void showAll() {
    _dropAi();
    _filter = const MapFilter();
    search.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsAiSearch) _aiSearch?.dispose();
    search.removeListener(_onSearchChanged);
    search.dispose();
    super.dispose();
  }
}

const Object _keep = Object();
