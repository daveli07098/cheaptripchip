import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/board_store.dart';
import '../data/map_filter.dart';
import '../data/map_focus.dart';
import '../data/mock_data.dart';
import '../data/place_filter_controller.dart';
import '../data/place_store.dart';
import '../data/shared_board_store.dart';
import '../models/place.dart';
import '../services/ai_search.dart';
import '../theme/app_theme.dart';
import '../widgets/account_button.dart';
import '../widgets/ai_results_chip.dart';
import '../widgets/ask_suggestions.dart';
import '../widgets/delete_find.dart';
import '../widgets/filter_chips.dart';
import '../widgets/filter_drawer.dart';
import '../widgets/map_pin.dart';
import '../widgets/map_tile_banner.dart';
import '../widgets/marker_clustering.dart';
import '../widgets/place_list_sheet.dart';
import '../widgets/place_preview_card.dart';
import '../widgets/place_search_pill.dart';
import '../widgets/show_snack.dart';
import 'place_detail_sheet.dart';

/// Map-first surface (ANALYSIS.md §3): theme-aware CartoDB tiles, coral pins
/// grid-clustered at low zoom, the shared Filters drawer ([FilterDrawer]:
/// favourites, categories, boards, areas; opened from the search pill's
/// leading ☰, with the theme toggle in its Settings footer), a
/// Google-Maps-style search pill (free-text over [placeMatches], submit fits
/// the camera to the matches or says nothing matched), active-filter chips
/// ([ActiveFilterChips]), and a persistent (non-modal) place-list sheet
/// kept in sync with the pins. Tapping a pin selects it and floats a
/// [PlacePreviewCard] just above the sheet (Google Maps style — the card or
/// its Details action opens the full detail sheet); tapping empty map
/// dismisses it. Tapping a list row selects + pans without a card.
/// Filters + search live in a [PlaceFilterController] shared with the Saved
/// tab; only the camera fly on a drawer pick is map-only. [focus] lets the Boards tab show one board here, and any tab one place
/// ([MapFocusController]).
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.onAddFind,
    this.focus,
    this.filters,
  });

  /// Forwarded straight through to [PlaceListSheet] — see its doc comment
  /// for what triggers this (the "+" affordance for adding a new find).
  final VoidCallback onAddFind;

  /// "Show this board on the map" requests: each one replaces every filter
  /// with just that board and flies the camera to fit its places. "Show
  /// this place" requests fly to one place and open its preview card.
  final ValueListenable<MapFocus?>? focus;

  /// Filters + search shared with the Saved tab (owned by the home shell);
  /// null = a private one, e.g. in tests.
  final PlaceFilterController? filters;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final _mapController = MapController();

  /// Drives (and lets us read `.size` from) the persistent list sheet's
  /// current extent — needed to pad map moves so results land above it.
  final _sheetExtentController = DraggableScrollableController();

  final _listSheetController = PlaceListSheetController();

  /// Opens the Filters drawer from the search bar's leading ☰ button.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Our own [PlaceFilterController] when the widget wasn't given one.
  PlaceFilterController? _ownFilters;

  /// The active filters + search text (its `search` backs the search pill).
  PlaceFilterController get _filters =>
      widget.filters ?? (_ownFilters ??= PlaceFilterController());

  final _searchFocusNode = FocusNode();

  /// The place currently highlighted on both the map (max z-order + scale)
  /// and the list (scrolled into view + tinted row). A notifier rather than
  /// `setState` state: a pin tap then rebuilds only the marker layer, the
  /// built list rows and the preview card — not the whole screen.
  final _selectedPlaceId = ValueNotifier<String?>(null);

  /// Whether the floating [PlacePreviewCard] is shown for [_selectedPlaceId].
  /// Only pin taps raise it; list selection and empty-map taps clear it.
  final _previewVisible = ValueNotifier<bool>(false);

  /// Counts tile failures for the "Map unavailable" banner.
  final _tileHealth = TileHealthMonitor();

  /// Whether the camera has been fitted to real places yet. Guest places
  /// load from disk after the first frame, so the map can start empty and
  /// must fit once they arrive.
  bool _fittedToPlaces = false;

  /// Set once FlutterMap has laid out; before that the controller can't move.
  bool _mapReady = false;

  /// Built once: [FlutterMap] pushes a new options object into its
  /// controller whenever `options != oldWidget.options`, and a fresh
  /// [MapOptions] (new closures, new fit) never compares equal — so every
  /// filter change or keystroke used to re-notify every map layer.
  MapOptions? _mapOptions;

  /// Cached per brightness so screen rebuilds hand FlutterMap the identical
  /// widget (no tile-layer update, no throwaway [NetworkTileProvider]).
  Widget? _tileLayer;
  Brightness? _tileLayerBrightness;

  /// A drawer pick waiting for the drawer to close before the camera flies
  /// to its results (true = always fit, e.g. an area).
  bool? _pendingFilterFit;

  /// The "Ask" answer the camera last fitted to — a new one (asked here or
  /// on the Saved tab) fits the map to its places once.
  Object? _fittedAiResult;

  // Camera fly animation (flutter_map 8 has no public animated move): the
  // controller ticks [_onCameraTick], which interpolates from/to below.
  late final AnimationController _cameraAnimation;
  LatLng _flyFromCenter = const LatLng(0, 0);
  LatLng _flyToCenter = const LatLng(0, 0);
  double _flyFromZoom = 0;
  double _flyToZoom = 0;
  double _flyZoomDip = 0;
  Offset _flyOffset = Offset.zero;
  Curve _flyCurve = Curves.easeOutCubic;

  /// Favourites AND category AND area AND boards AND free-text search (via
  /// [placeMatches]) — search terms are matched across name/area/region/
  /// address/description/notes/category labels/source handle, so it also
  /// narrows results within a category.
  MapFilter get _filter => _filters.filter;

  /// Memoizes the filtered list and drawer counts, so rebuilds that don't
  /// change the places or the filter do no per-place work.
  MapFilterCache get _filterCache => _filters.cache;

  /// Place ↔ board membership for the current snapshot (memoized).
  BoardIndex _boardIndexNow() => _filterCache.boardsFor(
    PlaceStore.instance.places.value,
    BoardStore.instance.boards.value,
    SharedBoardStore.instance.boards.value,
  );

  List<Place> _visibleNow() => _filterCache.visibleFor(
    PlaceStore.instance.places.value,
    _filter,
    boards: _boardIndexNow(),
  );

  /// How many logical pixels of screen height the list sheet currently
  /// covers, used to keep map moves from landing a pin underneath it.
  double _sheetPixels(BuildContext context) {
    final fraction = _sheetExtentController.isAttached
        ? _sheetExtentController.size
        : kSheetPeek;
    return MediaQuery.of(context).size.height * fraction;
  }

  /// Pin tapped on the map: highlight it, scroll the matching list row into
  /// view, and show the floating preview card. If the list sheet is above
  /// half height it collapses to peek so the card and the pin stay visible.
  /// Deliberately does NOT move the map — re-centering under an active
  /// pan/tap is a documented anti-pattern that fights the user.
  void _selectFromPin(Place place) {
    HapticFeedback.selectionClick();
    _selectedPlaceId.value = place.id;
    _previewVisible.value = true;
    // Warm the detail sheet's header photo while the card is up, so opening
    // Details doesn't show the photo popping in mid-slide.
    PlaceDetailSheet.precacheHeader(context, place);
    final extent = _sheetExtentController.isAttached
        ? _sheetExtentController.size
        : kSheetPeek;
    final collapsing = extent > kSheetHalf + 0.01;
    if (collapsing) {
      _sheetExtentController.animateTo(
        kSheetPeek,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    // Only scroll the list when its rows are actually on screen: at (or
    // collapsing to) peek the row would land below the fold anyway, and the
    // jump + ensureVisible + row builds would compete with the card, sheet
    // and pin animations this tap already starts. The row is still tinted
    // via [_selectedPlaceId].
    if (!collapsing && extent > kSheetPeek + 0.01) {
      _listSheetController.scrollToPlace(place.id);
    }
  }

  /// The detail sheet over the map — with the current map centre for its
  /// "Use current map center" location fix.
  void _openDetail(BuildContext context, Place place) => PlaceDetailSheet.show(
    context,
    place,
    currentMapCenter: () => _mapController.camera.center,
  );

  /// Empty map tapped: drop search focus (matching Google Maps) and dismiss
  /// the preview card along with the pin highlight.
  void _onMapTap(TapPosition _, LatLng _) {
    _searchFocusNode.unfocus();
    _previewVisible.value = false;
    _selectedPlaceId.value = null;
  }

  /// Row tapped in the list sheet: highlight + fly the map to it,
  /// offsetting the target upward so it lands above the sheet rather than
  /// underneath it.
  void _selectFromList(BuildContext context, Place place) {
    _selectedPlaceId.value = place.id;
    // The list already shows this place — no floating card on top of it.
    _previewVisible.value = false;
    final targetZoom = math.max(_mapController.camera.zoom, 15.0);
    _flyTo(
      place.location,
      targetZoom,
      // MapController.move's `offset` places `center` at
      // (screen-center + offset), so shifting up (negative dy) by half the
      // sheet's height lands the pin in the middle of the space still
      // visible above it.
      offset: Offset(0, -_sheetPixels(context) / 2),
    );
  }

  /// Cluster tapped: zoom the camera to fit every place in that cluster,
  /// padding the bottom by the sheet's current height so the fit result
  /// isn't computed as if that space were still available. A method (not a
  /// per-build closure) so the marker layer's cached markers stay valid.
  void _focusCluster(PlaceCluster cluster) {
    final fit = _fitFor(context, cluster.places);
    if (fit != null) _flyToFit(fit);
  }

  /// Keyboard "search" action: unfocus and, like [_focusCluster], fit the
  /// camera to every currently-matching place ([matches], computed at
  /// submit time from the current filter + query). Zero matches says so in a SnackBar
  /// rather than silently doing nothing; a single match pans/zooms to it
  /// (matching [_selectFromList]) rather than "fitting" to one point.
  void _submitSearch(BuildContext context, List<Place> matches) {
    _searchFocusNode.unfocus();
    if (matches.isEmpty) {
      final query = _filter.query.trim();
      showSnack(
        context,
        query.isEmpty
            ? 'No places match your filters'
            : 'No places match “$query”',
      );
      return;
    }
    if (matches.length == 1) {
      _selectFromList(context, matches.first);
      return;
    }
    final fit = _fitFor(context, matches);
    if (fit != null) _flyToFit(fit);
  }

  /// "Ask your places": [question] goes to Gemini (or the keyword
  /// fallback) with the map's visible centre as "near me"; the answer
  /// shows as AI results and the build fits the camera to them.
  Future<void> _ask(String question) async {
    _searchFocusNode.unfocus();
    if (_mapReady) _filters.mapCenter = _mapController.camera.center;
    await _filters.ask(
      question,
      places: PlaceStore.instance.places.value,
      boards: _boardIndexNow(),
    );
  }

  /// Fits the camera to a new "Ask" answer's places (after the frame that
  /// shows them); a single place pans to it, none leaves the camera alone
  /// — the chip's explanation already says nothing fit.
  void _fitToAiResults() {
    final result = _filters.aiResult;
    if (result == null || identical(result, _fittedAiResult)) return;
    _fittedAiResult = result;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_filters.aiResult, result)) return;
      final visible = _visibleNow();
      if (visible.isEmpty) return;
      if (visible.length == 1) {
        _selectFromList(context, visible.first);
        return;
      }
      final fit = _fitFor(context, visible);
      if (fit != null) _flyToFit(fit);
    });
  }

  /// A drawer pick was applied; as the drawer starts closing (Scaffold's
  /// `onDrawerChanged(false)`), so the flight plays out as the map is
  /// revealed, fly the camera to the new results. [always] for area picks
  /// (the user asked for a place on the map); category/favourites picks
  /// only move when none of their results are on screen, so a filter never
  /// yanks the user away from where they were looking for no reason.
  void _onDrawerPicked({required bool always}) => _pendingFilterFit = always;

  /// Board rows are multi-select, so a toggle keeps the drawer open; the
  /// camera fits the new results once it closes (see [_onDrawerChanged]).
  void _onDrawerBoardsChanged() => _pendingFilterFit = true;

  /// A [MapFocusController] request from the Boards tab: show only that
  /// board — the other filters and the search are cleared so none of its
  /// places stay hidden — then fly to fit its places after the frame.
  void _onFocusRequest() {
    final request = widget.focus?.value;
    if (request == null || !mounted) return;
    switch (request) {
      case MapBoardFocus():
        _showBoardFocus(request);
      case MapPlaceFocus():
        _showPlaceFocus(request);
    }
  }

  /// A place's "Show on map": select its pin and open its preview card, then
  /// fly close to it (zoom ≥ 16) with the pin landing above the card. If the
  /// current filters or search hide it, they are all cleared first (the
  /// user asked for this place; a half-kept filter would be confusing). A
  /// place that isn't one of the user's own (a shared-board copy) has no
  /// pin: the map flies to its coordinates and says so.
  void _showPlaceFocus(MapPlaceFocus request) {
    _searchFocusNode.unfocus();
    _pendingFilterFit = null;
    final place = PlaceStore.instance.byIdOrNull(request.placeId);
    if (place != null && !_visibleNow().any((p) => p.id == place.id)) {
      _filters.showAll();
    }
    _selectedPlaceId.value = place?.id;
    _previewVisible.value = place != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.focus?.value, request)) return;
      final location = place?.location ?? request.location;
      if (!location.latitude.isFinite || !location.longitude.isFinite) {
        showSnack(context, '“${request.name}” has no location on the map');
        return;
      }
      if (place == null) {
        showSnack(
          context,
          '“${request.name}” isn’t in your places — showing where it is',
        );
      } else {
        PlaceDetailSheet.precacheHeader(context, place);
      }
      // Down to peek, so the card and the pin both have room.
      if (_sheetExtentController.isAttached &&
          _sheetExtentController.size > kSheetPeek + 0.01) {
        _sheetExtentController.animateTo(
          kSheetPeek,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      final covered =
          MediaQuery.of(context).size.height * kSheetPeek +
          (place == null ? 0 : kPlacePreviewCardApproxHeight + 12);
      _flyTo(
        location,
        math.max(_mapController.camera.zoom, 16.0),
        // Same offset trick as _selectFromList: centre the pin in the space
        // left above the sheet (and the card).
        offset: Offset(0, -covered / 2),
      );
    });
  }

  void _showBoardFocus(MapBoardFocus request) {
    _searchFocusNode.unfocus();
    _selectedPlaceId.value = null;
    _previewVisible.value = false;
    _pendingFilterFit = null;
    _filters.showOnlyBoard(request.boardKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.focus?.value, request)) return;
      final visible = _visibleNow();
      if (visible.isEmpty) {
        final name = _boardIndexNow().byKey(request.boardKey)?.name;
        showSnack(
          context,
          name == null
              ? 'None of this board’s places are on your map'
              : 'None of “$name”’s places are on your map',
        );
        return;
      }
      // One place gets a small box around it, several their bounds; both
      // skip non-finite points and a NaN result (see _fitFor/_flyToFit).
      final fit = _fitFor(context, visible);
      if (fit != null) _flyToFit(fit);
    });
  }

  void _onDrawerChanged(bool open) {
    final always = _pendingFilterFit;
    if (open || always == null) return;
    _pendingFilterFit = null;
    if (!mounted || !_mapReady) return;
    final visible = _visibleNow();
    if (visible.isEmpty) return;
    if (!always) {
      final bounds = _mapController.camera.visibleBounds;
      if (visible.any((p) => bounds.contains(p.location))) return;
    }
    final fit = _fitFor(context, visible);
    if (fit != null) _flyToFit(fit);
  }

  /// A camera fit for [points], or null when there's nothing valid to fit.
  /// Fitting an empty list yields a NaN camera and a red screen, so callers
  /// must handle null; non-finite coordinates are ignored for the same reason.
  CameraFit? _fitFor(BuildContext context, Iterable<Place> places) {
    final points = [
      for (final p in places)
        if (isFinitePlace(p)) p.location,
    ];
    if (points.isEmpty) return null;
    final padding = EdgeInsets.fromLTRB(48, 96, 48, 48 + _sheetPixels(context));
    if (points.length == 1) {
      // A single point has zero-size bounds; fit a small box around it.
      final c = points.first;
      return CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(c.latitude - 0.005, c.longitude - 0.005),
          LatLng(c.latitude + 0.005, c.longitude + 0.005),
        ),
        padding: padding,
        maxZoom: 17,
      );
    }
    return CameraFit.coordinates(
      coordinates: points,
      padding: padding,
      maxZoom: 17,
    );
  }

  /// Resolves [fit] against the current camera and flies there.
  void _flyToFit(CameraFit fit) {
    if (!_mapReady) {
      _mapController.fitCamera(fit);
      return;
    }
    final target = fit.fit(_mapController.camera);
    if (!target.center.latitude.isFinite || !target.zoom.isFinite) return;
    _flyTo(target.center, target.zoom);
  }

  /// Short eased camera move instead of an instant jump, so the user can
  /// follow where the map went. Far targets (more than a screen away) dip
  /// the zoom mid-flight, Google-Maps style, instead of smearing tiles past
  /// at full zoom. A new call or a finger on the map cancels the flight.
  void _flyTo(LatLng center, double zoom, {Offset offset = Offset.zero}) {
    if (!_mapReady) {
      _mapController.move(center, zoom, offset: offset);
      return;
    }
    final camera = _mapController.camera;
    final lowZoom = math.min(camera.zoom, zoom);
    final distance =
        (camera.projectAtZoom(center, lowZoom) -
                camera.projectAtZoom(camera.center, lowZoom))
            .distance;
    final span = camera.size.longestSide;
    final dip = span > 0 && distance > span
        ? math.min(4.0, math.log(distance / span) / math.ln2)
        : 0.0;

    _flyFromCenter = camera.center;
    _flyFromZoom = camera.zoom;
    _flyToCenter = center;
    _flyToZoom = zoom;
    _flyZoomDip = dip;
    _flyOffset = offset;
    _flyCurve = dip > 0 ? Curves.easeInOutCubic : Curves.easeOutCubic;
    _cameraAnimation.duration = Duration(milliseconds: dip > 0 ? 650 : 350);
    _cameraAnimation.forward(from: 0);
  }

  void _onCameraTick() {
    final t = _flyCurve.transform(_cameraAnimation.value);
    final lat =
        _flyFromCenter.latitude +
        (_flyToCenter.latitude - _flyFromCenter.latitude) * t;
    final lng =
        _flyFromCenter.longitude +
        (_flyToCenter.longitude - _flyFromCenter.longitude) * t;
    final zoom =
        _flyFromZoom +
        (_flyToZoom - _flyFromZoom) * t -
        _flyZoomDip * math.sin(math.pi * t);
    _mapController.move(
      LatLng(lat, lng),
      zoom.clamp(_minZoom, _maxZoom),
      offset: _flyOffset * t,
    );
  }

  void _stopFlight(PointerDownEvent _, LatLng _) => _cameraAnimation.stop();

  static const double _minZoom = 3;
  static const double _maxZoom = 18;

  MapOptions _buildMapOptions(CameraFit? initialFit) => MapOptions(
    // Fit every place on first load rather than a fixed
    // center/zoom: a hardcoded zoom happened to clip the
    // Hoshinoya (Stay) pin, the easternmost place, right at the
    // viewport edge — there was no bounds-fitting logic here at
    // all, unlike `_focusCluster`/`_selectFromList` above, which
    // both already fit-to-content. `CameraFit.coordinates` is
    // resolved against the map's actual layout size, so — like
    // those two — it's computed with the sheet's current height
    // padded out from the bottom so no pin lands underneath it.
    initialCameraFit: initialFit,
    // Used only when there are no places yet (initialFit null).
    initialCenter: MockData.tokyoCenter,
    initialZoom: 11,
    onMapReady: () {
      _mapReady = true;
      _filters.mapCenter = _mapController.camera.center;
    },
    // "Near me" for "Ask" = the visible centre (no location permission).
    onPositionChanged: (camera, _) => _filters.mapCenter = camera.center,
    minZoom: _minZoom,
    // Stop dragging past the poles — beyond ±85° there are no tiles, only
    // background, which read as "the whole map went grey" when zoomed out.
    cameraConstraint: const CameraConstraint.containLatitude(),
    maxZoom: _maxZoom,
    // Tapping the map (not a pin/cluster) drops keyboard focus
    // from the search field and dismisses the preview card,
    // matching Google Maps.
    onTap: _onMapTap,
    // The user grabbing the map wins over an in-flight camera move.
    onPointerDown: _stopFlight,
  );

  Widget _tileLayerFor(Brightness brightness) {
    final cached = _tileLayer;
    if (cached != null && _tileLayerBrightness == brightness) return cached;
    _tileLayerBrightness = brightness;
    final tiles = Stack(
      children: [
        // Tile-coloured backdrop instead of flutter_map's flat grey while
        // tiles load after a big zoom-out. Inside the dark-mode filter, so
        // it inverts to a dark backdrop along with the tiles.
        const Positioned.fill(child: ColoredBox(color: Color(0xFFF2EFE9))),
        TileLayer(
          // OSM raster tiles — see AppTheme.mapTileUrl doc comment
          // re: usage-policy limits and swapping in a keyed provider.
          urlTemplate: AppTheme.mapTileUrl,
          userAgentPackageName: 'com.cheaptripchip.app',
          // A tile that failed (network blip, app just resumed) is dropped
          // once off-screen, so it loads again next time instead of staying
          // blank forever (the default never retries).
          evictErrorTileStrategy:
              EvictErrorTileStrategy.notVisibleRespectMargin,
          errorTileCallback: (tile, error, _) {
            debugPrint('Map tile ${tile.coordinates} failed: $error');
            // Deferred like the success path below: a cached failed
            // stream can report synchronously, mid-build.
            scheduleMicrotask(_tileHealth.recordError);
          },
          // Only watches for a successful load (to hide the "Map
          // unavailable" banner) — the tile itself is returned as is.
          // Runs during build, so the store update is deferred.
          tileBuilder: (context, tileWidget, tile) {
            final loadedAt = tile.loadFinishedAt;
            if (loadedAt != null &&
                !tile.loadError &&
                _tileHealth.awaitingRecovery) {
              scheduleMicrotask(() => _tileHealth.recordSuccess(loadedAt));
            }
            return tileWidget;
          },
        ),
      ],
    );
    // OSM has no dark-tile variant, so dark mode is simulated by
    // inverting/hue-rotating the same tiles — with ONE colour filter over
    // the whole layer (flutter_map's darkModeTilesContainerBuilder), not
    // one per tile (darkModeTileBuilder), which cost a filter pass per
    // visible tile every frame of a pan or animation.
    return _tileLayer = brightness == Brightness.dark
        ? Builder(
            builder: (context) => darkModeTilesContainerBuilder(context, tiles),
          )
        : tiles;
  }

  @override
  void initState() {
    super.initState();
    _cameraAnimation = AnimationController(vsync: this)
      ..addListener(_onCameraTick);
    widget.focus?.addListener(_onFocusRequest);
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus != widget.focus) {
      oldWidget.focus?.removeListener(_onFocusRequest);
      widget.focus?.addListener(_onFocusRequest);
    }
  }

  @override
  void dispose() {
    widget.focus?.removeListener(_onFocusRequest);
    _cameraAnimation.dispose();
    _sheetExtentController.dispose();
    _ownFilters?.dispose();
    _searchFocusNode.dispose();
    _selectedPlaceId.dispose();
    _previewVisible.dispose();
    _tileHealth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sharedBoards = SharedBoardStore.instance.boards;
    return ListenableBuilder(
      listenable: Listenable.merge([
        PlaceStore.instance.places,
        BoardStore.instance.boards,
        sharedBoards,
        _filters,
      ]),
      builder: (context, _) {
        final loaded = PlaceStore.instance.places.value;
        // Memoized: unchanged places + boards + filter → the same
        // instances, no per-place work (see MapFilterCache).
        final index = _filterCache.indexFor(loaded);
        final all = index.all;
        final boardIndex = _filterCache.boardsFor(
          loaded,
          BoardStore.instance.boards.value,
          sharedBoards.value,
        );
        final visible = _filterCache.visibleFor(
          loaded,
          _filter,
          boards: boardIndex,
        );
        // Only needed until the first fit (and for the one-time options).
        final initialFit = !_fittedToPlaces || _mapOptions == null
            ? _fitFor(context, all)
            : null;
        if (!_fittedToPlaces && initialFit != null) {
          // First frame with places: if the map started empty (places were
          // still loading), fit once now that they're here.
          final startedEmpty = !_fittedToPlaces && _mapReady;
          _fittedToPlaces = true;
          if (startedEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _mapController.fitCamera(initialFit);
            });
          }
        }
        final mapOptions = _mapOptions ??= _buildMapOptions(initialFit);
        final brightness = Theme.of(context).brightness;

        // If a search/category change dropped the selected pin out of
        // `visible`, clear it — deferred to a post-frame callback since
        // `all`/`visible` are only known mid-build, and mutating the
        // notifiers here would rebuild listeners during build. Re-checks
        // `_selectedPlaceId` still equals the id that dropped out before
        // clearing, in case more changes landed before the frame runs.
        // A picked board that no longer exists (deleted, left, or "New
        // finds" emptied) would hide every pin with no chip to clear it —
        // drop it after the frame, same deferral as the selection below.
        if (_filter.boards.any((key) => boardIndex.byKey(key) == null)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final boards = _boardIndexNow();
            _filters.retainBoards((key) => boards.byKey(key) != null);
          });
        }

        _fitToAiResults();

        final selectedId = _selectedPlaceId.value;
        if (selectedId != null && !visible.any((p) => p.id == selectedId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedPlaceId.value == selectedId) {
              _selectedPlaceId.value = null;
              _previewVisible.value = false;
            }
          });
        }

        return Scaffold(
          key: _scaffoldKey,
          // Keep the map/sheet full-size while the search field is focused
          // (Google Maps behaviour) — without this, the keyboard shrinks the
          // Stack, and `_submitSearch`'s camera fit (computed right after
          // `unfocus()`, before the keyboard animates away) would be sized
          // against that shrunk viewport and land off once it closes.
          resizeToAvoidBottomInset: false,
          // Edge-swipe would fight map panning and Android's back gesture;
          // the drawer opens from the filter button only.
          drawerEnableOpenDragGesture: false,
          onDrawerChanged: _onDrawerChanged,
          drawer: FilterDrawer(
            filters: _filters,
            index: index,
            boardIndex: boardIndex,
            onPicked: _onDrawerPicked,
            onBoardsChanged: _onDrawerBoardsChanged,
          ),
          body: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: mapOptions,
                children: [
                  _tileLayerFor(brightness),
                  _ClusterMarkerLayer(
                    places: visible,
                    selectedId: _selectedPlaceId,
                    brightness: brightness,
                    onTapPlace: _selectFromPin,
                    onTapCluster: _focusCluster,
                  ),
                  _AttributionBar(
                    sheetExtentController: _sheetExtentController,
                    // Lifted above the preview card while it's shown.
                    previewVisible: _previewVisible,
                  ),
                ],
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: PlaceSearchPill(
                        controller: _filters.search,
                        focusNode: _searchFocusNode,
                        activeFilters: _filter.activeCount,
                        onOpenFilters: () =>
                            _scaffoldKey.currentState?.openDrawer(),
                        // Typing needs no handler: the shared controller
                        // mirrors the text into the filter and notifies.
                        // Cheap per keystroke — only the filter pass re-runs
                        // (the drawer counts are memoized), so no debounce.
                        onSubmitted: (text) => looksLikeQuestion(text)
                            ? _ask(text)
                            : _submitSearch(context, _visibleNow()),
                        onAsk: () => _ask(_filters.search.text),
                        asking: _filters.asking,
                        trailing: const SizedBox.square(
                          dimension: 48,
                          child: Center(child: AccountButton()),
                        ),
                      ),
                    ),
                    AskSuggestions(
                      controller: _filters.search,
                      focusNode: _searchFocusNode,
                      suggestions: _filters.suggestionsFor(loaded),
                      onAsk: _ask,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    ),
                    ActiveFilterChips(
                      filters: _filters,
                      index: index,
                      boardIndex: boardIndex,
                      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    ),
                    AiResultsChip(
                      filters: _filters,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    ),
                    MapTileBanner(
                      monitor: _tileHealth,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    ),
                  ],
                ),
              ),
              PlaceListSheet(
                places: visible,
                total: all.length,
                selectedId: _selectedPlaceId,
                controller: _listSheetController,
                sheetController: _sheetExtentController,
                onSelectPlace: (place) => _selectFromList(context, place),
                onOpenDetail: (place) => _openDetail(context, place),
                onAddFind: widget.onAddFind,
                onDeletePlace: (place) =>
                    deleteFindWithUndo(ScaffoldMessenger.of(context), place),
              ),
              _PreviewCardLayer(
                sheetExtentController: _sheetExtentController,
                places: visible,
                boardIndex: boardIndex,
                selectedId: _selectedPlaceId,
                previewVisible: _previewVisible,
                onOpenDetail: (place) => _openDetail(context, place),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Renders [places] as pins, grid-clustering them per [clusterPlaces].
///
/// Reading `MapCamera.of(context)` here (rather than in `_MapScreenState`)
/// is what keeps clustering in sync with pan/zoom/rotate: this widget is a
/// child of [FlutterMap], so that read registers a dependency on
/// flutter_map's `MapInheritedModel` and triggers a rebuild of just this
/// layer whenever the camera changes. That rebuild runs every frame of a
/// gesture or fly animation, so it does no per-place work when nothing
/// changed: clusters are memoized per zoom bucket ([PlaceClusterCache]) and
/// the [Marker] list per (clusters, selection) — identical child widgets
/// let Flutter skip rebuilding every pin.
class _ClusterMarkerLayer extends StatefulWidget {
  const _ClusterMarkerLayer({
    required this.places,
    required this.selectedId,
    required this.brightness,
    required this.onTapPlace,
    required this.onTapCluster,
  });

  final List<Place> places;
  final ValueListenable<String?> selectedId;
  final Brightness brightness;
  final ValueChanged<Place> onTapPlace;
  final ValueChanged<PlaceCluster> onTapCluster;

  @override
  State<_ClusterMarkerLayer> createState() => _ClusterMarkerLayerState();
}

class _ClusterMarkerLayerState extends State<_ClusterMarkerLayer> {
  final _clusterCache = PlaceClusterCache();

  // Unselected markers, one per cluster, rebuilt only when the clusters or
  // their inputs change.
  List<PlaceCluster>? _baseClusters;
  Brightness? _baseBrightness;
  ValueChanged<Place>? _baseOnTapPlace;
  ValueChanged<PlaceCluster>? _baseOnTapCluster;
  bool? _baseKeyed;
  List<Marker> _baseMarkers = const [];

  // The final z-ordered list for one selection.
  List<Marker>? _orderedFor;
  String? _orderedSelectedId;
  List<Marker> _ordered = const [];

  Marker _pinMarker(
    Place place, {
    required bool selected,
    required bool keyed,
  }) {
    return Marker(
      // Keys let the Stack match pins across frames, so markers culled at
      // the viewport edge or the selected pin moving to the end don't shift
      // (and rebuild/reinflate) every other pin — and AnimatedScale keeps
      // its state, so the selection grow actually animates.
      key: keyed ? ValueKey('pin:${place.id}') : null,
      point: place.location,
      width: 48,
      height: 48,
      alignment: Alignment.topCenter,
      child: MapPin(
        place: place,
        selected: selected,
        brightness: widget.brightness,
        onTap: () => widget.onTapPlace(place),
      ),
    );
  }

  List<Marker> _markersFor(
    List<PlaceCluster> clusters,
    String? selectedId, {
    required bool keyed,
  }) {
    if (!identical(clusters, _baseClusters) ||
        widget.brightness != _baseBrightness ||
        widget.onTapPlace != _baseOnTapPlace ||
        widget.onTapCluster != _baseOnTapCluster ||
        keyed != _baseKeyed) {
      _baseClusters = clusters;
      _baseBrightness = widget.brightness;
      _baseOnTapPlace = widget.onTapPlace;
      _baseOnTapCluster = widget.onTapCluster;
      _baseKeyed = keyed;
      _orderedFor = null;
      _baseMarkers = [
        for (final cluster in clusters)
          if (cluster.isSingle)
            _pinMarker(cluster.places.first, selected: false, keyed: keyed)
          else
            Marker(
              key: keyed ? ValueKey('cluster:${cluster.cellKey}') : null,
              point: cluster.center,
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: ClusterPin(
                cluster: cluster,
                brightness: widget.brightness,
                onTap: () => widget.onTapCluster(cluster),
              ),
            ),
      ];
    }
    if (identical(_orderedFor, _baseMarkers) &&
        selectedId == _orderedSelectedId) {
      return _ordered;
    }
    _orderedFor = _baseMarkers;
    _orderedSelectedId = selectedId;

    // Move the selected (unclustered) pin to the end — MarkerLayer draws
    // later entries on top, giving the selected pin max z-order so
    // neighbours never occlude it.
    final selectedIndex = selectedId == null
        ? -1
        : clusters.indexWhere(
            (c) => c.isSingle && c.places.first.id == selectedId,
          );
    if (selectedIndex < 0) return _ordered = _baseMarkers;
    return _ordered = [
      for (var i = 0; i < _baseMarkers.length; i++)
        if (i != selectedIndex) _baseMarkers[i],
      _pinMarker(
        clusters[selectedIndex].places.first,
        selected: true,
        keyed: keyed,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final clusters = _clusterCache.clustersFor(widget.places, camera);
    // MarkerLayer repeats a marker once per visible world copy; that only
    // happens when the viewport (plus a marker's width) is wider than the
    // world, and those copies would share a key — so fall back to unkeyed
    // markers then. Never the case on phones (minZoom 3 = 2048px world).
    final keyed = camera.size.width + 48 < camera.getWorldWidthAtZoom();
    return ValueListenableBuilder<String?>(
      valueListenable: widget.selectedId,
      builder: (context, selectedId, _) =>
          MarkerLayer(markers: _markersFor(clusters, selectedId, keyed: keyed)),
    );
  }
}

/// Floats [PlacePreviewCard] for the selected place (when [previewVisible])
/// just above the list sheet's current top edge, tracking the sheet
/// continuously like [_AttributionBar]. Full width minus 12dp margins.
/// Slides up out of the sheet edge, and swaps (old down, new up) when
/// another pin is tapped (keyed by place id). Listens to the selection itself, so a pin tap rebuilds just this
/// card rather than the map screen.
class _PreviewCardLayer extends StatelessWidget {
  const _PreviewCardLayer({
    required this.sheetExtentController,
    required this.places,
    required this.boardIndex,
    required this.selectedId,
    required this.previewVisible,
    required this.onOpenDetail,
  });

  final DraggableScrollableController sheetExtentController;

  /// Resolves the card's "which boards" line in O(1).
  final BoardIndex boardIndex;

  /// The currently visible places; the card shows the selected one's
  /// latest data, and hides if it's filtered out.
  final List<Place> places;
  final ValueListenable<String?> selectedId;
  final ValueListenable<bool> previewVisible;
  final ValueChanged<Place> onOpenDetail;

  Place? _previewPlace() {
    final id = selectedId.value;
    if (!previewVisible.value || id == null) return null;
    for (final p in places) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sheetExtentController,
      builder: (context, child) {
        final fraction = sheetExtentController.isAttached
            ? sheetExtentController.size
            : kSheetPeek;
        final sheetPixels = MediaQuery.of(context).size.height * fraction;
        return Positioned(
          left: 12,
          right: 12,
          bottom: sheetPixels + 12,
          child: child!,
        );
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([selectedId, previewVisible]),
        builder: (context, _) {
          final place = _previewPlace();
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            // Rises out of the sheet's top edge (clipped just below the
            // card's 12dp gap) rather than fading: no opacity layer over
            // the card's elevation shadow, which had to be re-composited
            // every frame alongside the sheet and pin animations.
            transitionBuilder: (child, animation) => ClipRect(
              clipper: const _AboveBottomEdgeClipper(12),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1.15),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            // Bottom-anchored so a taller/shorter incoming card grows upward
            // from the sheet edge rather than jumping.
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.bottomCenter,
              children: [...previous, ?current],
            ),
            child: place == null
                ? const SizedBox.shrink(key: ValueKey('no-preview'))
                : PlacePreviewCard(
                    key: ValueKey(place.id),
                    place: place,
                    boards: boardIndex.boardsOf(place.id),
                    onOpenDetails: () => onOpenDetail(place),
                  ),
          );
        },
      ),
    );
  }
}

/// Clips only below [bottomOverflow] past the child's bottom edge — the
/// sides and top stay unclipped so the card's shadow isn't cut off.
class _AboveBottomEdgeClipper extends CustomClipper<Rect> {
  const _AboveBottomEdgeClipper(this.bottomOverflow);

  final double bottomOverflow;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -size.width,
    -size.height,
    size.width * 2,
    size.height + bottomOverflow,
  );

  @override
  bool shouldReclip(_AboveBottomEdgeClipper oldClipper) =>
      oldClipper.bottomOverflow != bottomOverflow;
}

class _AttributionBar extends StatelessWidget {
  const _AttributionBar({
    required this.sheetExtentController,
    required this.previewVisible,
  });

  /// Tracked so the bar can float just above the persistent list sheet's
  /// current top edge instead of sitting permanently underneath it.
  final DraggableScrollableController sheetExtentController;

  /// While true the bar lifts to clear the floating preview card.
  final ValueListenable<bool> previewVisible;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // Rebuilds on every drag of the sheet, not just on settle, so the bar
      // tracks it continuously rather than jumping at the end.
      animation: Listenable.merge([sheetExtentController, previewVisible]),
      builder: (context, _) {
        final fraction = sheetExtentController.isAttached
            ? sheetExtentController.size
            : kSheetPeek;
        final sheetPixels = MediaQuery.of(context).size.height * fraction;
        final extraBottom = previewVisible.value
            ? kPlacePreviewCardApproxHeight + 12
            : 0.0;
        return Positioned(
          right: 8,
          bottom: sheetPixels + 8 + extraBottom,
          // OSM attribution is required by the tile licence; the widget's
          // own popup/link already points at openstreetmap.org/copyright.
          child: const RichAttributionWidget(
            attributions: [TextSourceAttribution(AppTheme.mapAttribution)],
          ),
        );
      },
    );
  }
}
