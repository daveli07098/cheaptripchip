import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/map_filter.dart';
import '../data/mock_data.dart';
import '../data/place_search.dart';
import '../data/place_store.dart';
import '../models/place.dart';
import '../services/area_resolver.dart';
import '../theme/app_theme.dart';
import '../theme/theme_toggle_button.dart';
import '../widgets/account_button.dart';
import '../widgets/map_pin.dart';
import '../widgets/marker_clustering.dart';
import '../widgets/place_list_sheet.dart';
import '../widgets/place_preview_card.dart';
import 'place_detail_sheet.dart';

/// Map-first surface (ANALYSIS.md §3): theme-aware CartoDB tiles, coral pins
/// grid-clustered at low zoom, a category filter in a left drawer (opened
/// from the search bar's leading ☰, with the theme toggle in its footer), a
/// Google-Maps-style search bar (free-text over [placeMatches], submit fits
/// the camera to the matches), and a persistent (non-modal) place-list sheet
/// kept in sync with the pins. Tapping a pin selects it and floats a
/// [PlacePreviewCard] just above the sheet (Google Maps style — the card or
/// its Details action opens the full detail sheet); tapping empty map
/// dismisses it. Tapping a list row selects + pans without a card.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.onAddFind});

  /// Forwarded straight through to [PlaceListSheet] — see its doc comment
  /// for what triggers this (the "+" affordance for adding a new find).
  final VoidCallback onAddFind;

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

  /// Opens the category drawer from the search bar's leading ☰ button.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Backs the search pill's [TextField]; read directly in [_filter] rather
  /// than mirrored into a separate `_query` field.
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  /// null = "All". Otherwise filter pins to the selected category.
  PlaceCategory? _selected;

  /// null = every restaurant (no sub-filter). Only meaningful alongside
  /// `_selected == PlaceCategory.restaurant` — selecting any other category
  /// (including "All") clears it back to null.
  RestaurantType? _selectedType;

  /// null = every area. Otherwise only places whose [Place.city] equals
  /// it — the empty string selects "Unknown area" (no city yet). ANDed with
  /// the category filter; the drawer's "All" row leaves it alone.
  String? _selectedCity;

  /// null = the whole [_selectedCity]. Otherwise only places whose
  /// [Place.district] equals it (always set together with its city).
  String? _selectedArea;

  /// The place currently highlighted on both the map (max z-order + scale)
  /// and the list (scrolled into view + tinted row). A notifier rather than
  /// `setState` state: a pin tap then rebuilds only the marker layer, the
  /// built list rows and the preview card — not the whole screen.
  final _selectedPlaceId = ValueNotifier<String?>(null);

  /// Whether the floating [PlacePreviewCard] is shown for [_selectedPlaceId].
  /// Only pin taps raise it; list selection and empty-map taps clear it.
  final _previewVisible = ValueNotifier<bool>(false);

  /// Memoizes the filtered list and drawer counts, so rebuilds that don't
  /// change the places or the filter do no per-place work.
  final _filterCache = MapFilterCache();

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
  TileLayer? _tileLayer;
  Brightness? _tileLayerBrightness;

  /// A drawer pick waiting for the drawer to close before the camera flies
  /// to its results (true = always fit, e.g. an area).
  bool? _pendingFilterFit;

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

  /// Category filter AND area filter AND free-text search (via
  /// [placeMatches]) — search terms are matched across name/area/region/
  /// address/description/notes/category labels/source handle, so it also
  /// narrows results within a category.
  MapFilter get _filter => MapFilter(
    category: _selected,
    restaurantType: _selectedType,
    city: _selectedCity,
    district: _selectedArea,
    query: _searchController.text,
  );

  List<Place> _visibleNow() =>
      _filterCache.visibleFor(PlaceStore.instance.places.value, _filter);

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
    _selectedPlaceId.value = place.id;
    _previewVisible.value = true;
    _listSheetController.scrollToPlace(place.id);
    if (_sheetExtentController.isAttached &&
        _sheetExtentController.size > kSheetHalf + 0.01) {
      _sheetExtentController.animateTo(
        kSheetPeek,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

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
  /// camera to every currently-matching place (category filter + query
  /// already applied by the caller). No-op on zero matches; a single match
  /// pans/zooms to it (matching [_selectFromList]) rather than "fitting" to
  /// one point.
  void _submitSearch(BuildContext context, List<Place> matches) {
    _searchFocusNode.unfocus();
    if (matches.isEmpty) return;
    if (matches.length == 1) {
      _selectFromList(context, matches.first);
      return;
    }
    final fit = _fitFor(context, matches);
    if (fit != null) _flyToFit(fit);
  }

  /// Applies a drawer pick, then — as the drawer starts closing (Scaffold's
  /// `onDrawerChanged(false)`), so the flight plays out as the map is
  /// revealed — flies the camera to the new results. [always] for
  /// area picks (the user asked for a place on the map); category picks only
  /// move when none of their results are on screen, so a filter never
  /// yanks the user away from where they were looking for no reason.
  void _applyDrawerFilter(VoidCallback change, {required bool always}) {
    setState(change);
    _pendingFilterFit = always;
    Navigator.of(context).pop();
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
    onMapReady: () => _mapReady = true,
    minZoom: _minZoom,
    maxZoom: _maxZoom,
    // Tapping the map (not a pin/cluster) drops keyboard focus
    // from the search field and dismisses the preview card,
    // matching Google Maps.
    onTap: _onMapTap,
    // The user grabbing the map wins over an in-flight camera move.
    onPointerDown: _stopFlight,
  );

  TileLayer _tileLayerFor(Brightness brightness) {
    final cached = _tileLayer;
    if (cached != null && _tileLayerBrightness == brightness) return cached;
    _tileLayerBrightness = brightness;
    return _tileLayer = TileLayer(
      // OSM raster tiles — see AppTheme.mapTileUrl doc comment
      // re: usage-policy limits and swapping in a keyed provider.
      urlTemplate: AppTheme.mapTileUrl,
      userAgentPackageName: 'com.cheaptripchip.app',
      // OSM has no dark-tile variant, so dark mode is simulated
      // by inverting/hue-rotating the same tiles.
      tileBuilder: brightness == Brightness.dark ? darkModeTileBuilder : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _cameraAnimation = AnimationController(vsync: this)
      ..addListener(_onCameraTick);
  }

  @override
  void dispose() {
    _cameraAnimation.dispose();
    _sheetExtentController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _selectedPlaceId.dispose();
    _previewVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, loaded, _) {
        // Memoized: unchanged places + filter → the same instances, no
        // per-place work (see MapFilterCache).
        final index = _filterCache.indexFor(loaded);
        final all = index.all;
        final visible = _filterCache.visibleFor(loaded, _filter);
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
        final counts = index.counts;
        final typeCounts = index.restaurantTypeCounts;
        final areas = index.areas;

        // If a search/category change dropped the selected pin out of
        // `visible`, clear it — deferred to a post-frame callback since
        // `all`/`visible` are only known mid-build, and mutating the
        // notifiers here would rebuild listeners during build. Re-checks
        // `_selectedPlaceId` still equals the id that dropped out before
        // clearing, in case more changes landed before the frame runs.
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
          drawer: _CategoryDrawer(
            counts: counts,
            total: all.length,
            selected: _selected,
            restaurantTypeCounts: typeCounts,
            selectedType: _selectedType,
            onSelect: (c) => _applyDrawerFilter(() {
              _selected = c;
              _selectedType = null;
            }, always: false),
            onSelectType: (t) => _applyDrawerFilter(() {
              _selected = PlaceCategory.restaurant;
              _selectedType = t;
            }, always: false),
            areas: areas,
            selectedCity: _selectedCity,
            selectedArea: _selectedArea,
            onSelectArea: (city, district) => _applyDrawerFilter(() {
              _selectedCity = city;
              _selectedArea = district;
            }, always: city != null),
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
                    _SearchBar(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onOpenFilter: () =>
                          _scaffoldKey.currentState?.openDrawer(),
                      // The controller already holds the latest text by the
                      // time this fires — just triggers a rebuild so
                      // `_filter`/the clear button re-read it. Cheap per
                      // keystroke: only the filter pass re-runs (the drawer
                      // counts are memoized), so no debounce is needed.
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submitSearch(context, visible),
                      onClear: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
                    if (_selected != null || _selectedCity != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (_selected != null)
                                _CategoryChip(
                                  category: _selected!,
                                  type: _selectedType,
                                  // Same "counts are over ALL places, not
                                  // the search results" choice as the
                                  // drawer (see `MapPlaceIndex.counts`) —
                                  // keeps the number stable while the user
                                  // types.
                                  count: _selectedType != null
                                      ? (typeCounts[_selectedType] ?? 0)
                                      : (counts[_selected] ?? 0),
                                  onClear: () => setState(() {
                                    _selected = null;
                                    _selectedType = null;
                                  }),
                                ),
                              if (_selectedCity != null)
                                _AreaChip(
                                  city: _selectedCity!,
                                  district: _selectedArea,
                                  countryCode: areas.countryCodeOf(
                                    _selectedCity!,
                                  ),
                                  count: areas.countOf(
                                    _selectedCity!,
                                    _selectedArea,
                                  ),
                                  onClear: () => setState(() {
                                    _selectedCity = null;
                                    _selectedArea = null;
                                  }),
                                ),
                            ],
                          ),
                        ),
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
                onOpenDetail: (place) => PlaceDetailSheet.show(context, place),
                onAddFind: widget.onAddFind,
              ),
              _PreviewCardLayer(
                sheetExtentController: _sheetExtentController,
                places: visible,
                selectedId: _selectedPlaceId,
                previewVisible: _previewVisible,
                onOpenDetail: (place) => PlaceDetailSheet.show(context, place),
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

/// Floating full-width search pill: leading ☰ opens [_CategoryDrawer], a
/// free-text field (submit fits the map to the matches — see
/// [_MapScreenState._submitSearch]), a clear ✕ once there's text, and the
/// account button trailing. The theme toggle lives in the drawer's footer
/// instead of out here (see [_CategoryDrawer]).
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onOpenFilter,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onOpenFilter;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: scheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              // IconButton/TextField already derive their a11y label from
              // `tooltip`/`hintText` — an outer `Semantics` would just add a
              // second, redundant node for screen readers to announce.
              IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Categories',
                onPressed: onOpenFilter,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  decoration: const InputDecoration(
                    hintText: 'Search your finds',
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Clear search',
                    onPressed: onClear,
                  );
                },
              ),
              const SizedBox(width: 4),
              const SizedBox.square(
                dimension: 48,
                child: Center(child: AccountButton()),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small chip under the search pill showing the active category + its count
/// (over ALL places, same as the drawer — see `_MapScreenState._counts`),
/// with a ✕ to clear it. Nothing renders for "All" (see the `if (_selected
/// != null)` guard at the call site). When [type] is set (a restaurant
/// sub-type is active) it shows that instead of the bare category, e.g.
/// "🍜 Ramen · 5 ✕".
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.count,
    required this.onClear,
    this.type,
  });

  final PlaceCategory category;
  final RestaurantType? type;
  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emoji = type?.emoji ?? category.emoji;
    final label = type?.labelEn ?? category.labelEn;
    return Material(
      color: scheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: label,
              child: ExcludeSemantics(
                child: Text(emoji, style: const TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$label · $count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'Clear category filter',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Area counterpart to [_CategoryChip], shown next to it: flag + "Shibuya,
/// Tokyo · 12" (or just the city, or "Unknown area") with its own ✕ that
/// clears only the area filter.
class _AreaChip extends StatelessWidget {
  const _AreaChip({
    required this.city,
    required this.district,
    required this.countryCode,
    required this.count,
    required this.onClear,
  });

  final String city;
  final String? district;
  final String countryCode;
  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = city.isEmpty
        ? 'Unknown area'
        : (district == null ? city : '$district, $city');
    return Material(
      color: scheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AreaLeading(countryCode: countryCode, size: 14),
            const SizedBox(width: 6),
            Text(
              '$label · $count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'Clear area filter',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A flag for [countryCode] (wrapped in [Semantics], per the emoji rule),
/// or a pin icon when the country is unknown.
class _AreaLeading extends StatelessWidget {
  const _AreaLeading({required this.countryCode, required this.size});

  final String countryCode;
  final double size;

  @override
  Widget build(BuildContext context) {
    final flag = flagEmoji(countryCode);
    if (flag.isEmpty) return Icon(Icons.place_outlined, size: size + 4);
    return Semantics(
      label: 'Country: $countryCode',
      child: ExcludeSemantics(
        child: Text(flag, style: TextStyle(fontSize: size)),
      ),
    );
  }
}

/// "1,650" — thousands separators without pulling in package:intl.
String _formatCount(int n) {
  final digits = '$n';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Left drawer listing "All" plus every category present, with counts.
/// Tapping a row applies the filter and closes the drawer. The Restaurant
/// row is expandable — see [_RestaurantCategoryTile] — to filter by cuisine
/// sub-type without leaving the Restaurant category.
class _CategoryDrawer extends StatelessWidget {
  const _CategoryDrawer({
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelect,
    required this.restaurantTypeCounts,
    required this.selectedType,
    required this.onSelectType,
    required this.areas,
    required this.selectedCity,
    required this.selectedArea,
    required this.onSelectArea,
  });

  final Map<PlaceCategory, int> counts;
  final int total;
  final PlaceCategory? selected;
  final ValueChanged<PlaceCategory?> onSelect;
  final Map<RestaurantType, int> restaurantTypeCounts;
  final RestaurantType? selectedType;
  final ValueChanged<RestaurantType> onSelectType;
  final AreaIndex areas;
  final String? selectedCity;
  final String? selectedArea;

  /// (city, district): (null, null) = all areas, ("", null) = unknown,
  /// (city, null) = a whole city, (city, district) = one district.
  final void Function(String? city, String? district) onSelectArea;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Text(
                'Categories',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            _CategoryTile(
              leading: const Icon(Icons.apps),
              label: 'All',
              count: total,
              color: AppTheme.coral,
              selected: selected == null,
              onTap: () => onSelect(null),
            ),
            for (final entry in counts.entries)
              if (entry.key == PlaceCategory.restaurant)
                _RestaurantCategoryTile(
                  count: entry.value,
                  typeCounts: restaurantTypeCounts,
                  selected: selected == PlaceCategory.restaurant,
                  selectedType: selectedType,
                  onSelectCategory: () => onSelect(PlaceCategory.restaurant),
                  onSelectType: onSelectType,
                )
              else
                _CategoryTile(
                  leading: Semantics(
                    label: entry.key.labelEn,
                    child: ExcludeSemantics(
                      child: Text(
                        entry.key.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                  label: entry.key.labelEn,
                  count: entry.value,
                  color: AppTheme.categoryColor(entry.key, brightness),
                  selected: selected == entry.key,
                  onTap: () => onSelect(entry.key),
                ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Areas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const _AreaProgressLine(),
            _CategoryTile(
              leading: const Icon(Icons.public),
              label: 'All areas',
              count: total,
              color: AppTheme.coral,
              selected: selectedCity == null,
              onTap: () => onSelectArea(null, null),
            ),
            for (final group in areas.cities)
              _CityTile(
                group: group,
                selected: selectedCity == group.city,
                selectedDistrict: selectedCity == group.city
                    ? selectedArea
                    : null,
                onSelectCity: () => onSelectArea(group.city, null),
                onSelectDistrict: (d) => onSelectArea(group.city, d),
              ),
            if (areas.unknownCount > 0)
              _CategoryTile(
                leading: const Icon(Icons.help_outline),
                label: 'Unknown area',
                count: areas.unknownCount,
                color: AppTheme.coral,
                selected: selectedCity == '',
                onTap: () => onSelectArea('', null),
              ),
            const Divider(height: 24),
            // Moved here from the map's floating row (commit ec3b355) so the
            // search pill can stay a single, uninterrupted control.
            const ListTile(
              leading: Icon(Icons.brightness_6_outlined),
              title: Text('Theme'),
              trailing: ThemeToggleButton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.leading,
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        selected: selected,
        selectedTileColor: color.withValues(alpha: 0.16),
        selectedColor: Theme.of(context).colorScheme.onSurface,
        leading: SizedBox(width: 28, child: Center(child: leading)),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        trailing: Text('$count'),
        onTap: onTap,
      ),
    );
  }
}

/// Restaurant row in [_CategoryDrawer]: same look as [_CategoryTile] plus an
/// expand/collapse chevron when there's at least one sub-type to show (only
/// types with a count > 0, in [RestaurantType] declaration order). Tapping
/// the row itself still filters to all restaurants (via [onSelectCategory]);
/// tapping a sub-type row filters to just that type (via [onSelectType]).
/// Auto-expands whenever a sub-type becomes the active selection, but a
/// manual collapse otherwise sticks — see [_RestaurantCategoryTileState].
class _RestaurantCategoryTile extends StatefulWidget {
  const _RestaurantCategoryTile({
    required this.count,
    required this.typeCounts,
    required this.selected,
    required this.selectedType,
    required this.onSelectCategory,
    required this.onSelectType,
  });

  final int count;
  final Map<RestaurantType, int> typeCounts;
  final bool selected;
  final RestaurantType? selectedType;
  final VoidCallback onSelectCategory;
  final ValueChanged<RestaurantType> onSelectType;

  @override
  State<_RestaurantCategoryTile> createState() =>
      _RestaurantCategoryTileState();
}

class _RestaurantCategoryTileState extends State<_RestaurantCategoryTile> {
  late bool _expanded = widget.selected;

  @override
  void didUpdateWidget(covariant _RestaurantCategoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedType != null &&
        widget.selectedType != oldWidget.selectedType) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = AppTheme.categoryColor(PlaceCategory.restaurant, brightness);
    final orderedTypes = [
      for (final type in RestaurantType.values)
        if ((widget.typeCounts[type] ?? 0) > 0) type,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            selected: widget.selected,
            selectedTileColor: color.withValues(alpha: 0.16),
            selectedColor: Theme.of(context).colorScheme.onSurface,
            leading: SizedBox(
              width: 28,
              child: Center(
                child: Semantics(
                  label: PlaceCategory.restaurant.labelEn,
                  child: ExcludeSemantics(
                    child: Text(
                      PlaceCategory.restaurant.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
              ),
            ),
            title: Text(
              PlaceCategory.restaurant.labelEn,
              style: TextStyle(
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${widget.count}'),
                if (orderedTypes.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    tooltip: _expanded ? 'Hide cuisines' : 'Show cuisines',
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
              ],
            ),
            onTap: widget.onSelectCategory,
          ),
        ),
        if (_expanded)
          for (final type in orderedTypes)
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 12, top: 2),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                selected: widget.selectedType == type,
                selectedTileColor: color.withValues(alpha: 0.12),
                selectedColor: Theme.of(context).colorScheme.onSurface,
                leading: SizedBox(
                  width: 24,
                  child: Center(
                    child: Semantics(
                      label: type.labelEn,
                      child: ExcludeSemantics(
                        child: Text(
                          type.emoji,
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                  ),
                ),
                title: Text(
                  type.labelEn,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: widget.selectedType == type
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                trailing: Text('${widget.typeCounts[type] ?? 0}'),
                onTap: () => widget.onSelectType(type),
              ),
            ),
      ],
    );
  }
}

/// "Finding areas… 320 / 1,650" + a thin bar while [AreaResolver] is
/// backfilling cities/districts; nothing otherwise.
class _AreaProgressLine extends StatelessWidget {
  const _AreaProgressLine();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AreaProgress>(
      valueListenable: AreaResolver.instance.progress,
      builder: (context, progress, _) {
        if (!progress.running || progress.total == 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Finding areas… ${_formatCount(progress.done)} / '
                '${_formatCount(progress.total)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress.done / progress.total,
                minHeight: 3,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// City row in the drawer's Areas section: flag + city + count, expandable
/// (same pattern as [_RestaurantCategoryTile]) to its districts by count.
/// Tapping the row filters to the city; a district row to that district.
class _CityTile extends StatefulWidget {
  const _CityTile({
    required this.group,
    required this.selected,
    required this.selectedDistrict,
    required this.onSelectCity,
    required this.onSelectDistrict,
  });

  final CityGroup group;
  final bool selected;
  final String? selectedDistrict;
  final VoidCallback onSelectCity;
  final ValueChanged<String> onSelectDistrict;

  @override
  State<_CityTile> createState() => _CityTileState();
}

class _CityTileState extends State<_CityTile> {
  late bool _expanded = widget.selectedDistrict != null;

  @override
  void didUpdateWidget(covariant _CityTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDistrict != null &&
        widget.selectedDistrict != oldWidget.selectedDistrict) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.coral;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final districts = widget.group.sortedDistricts;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            selected: widget.selected && widget.selectedDistrict == null,
            selectedTileColor: color.withValues(alpha: 0.16),
            selectedColor: onSurface,
            leading: SizedBox(
              width: 28,
              child: Center(
                child: _AreaLeading(
                  countryCode: widget.group.countryCode,
                  size: 20,
                ),
              ),
            ),
            title: Text(
              widget.group.city,
              style: TextStyle(
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${widget.group.count}'),
                if (districts.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    tooltip: _expanded
                        ? 'Hide ${widget.group.city} districts'
                        : 'Show ${widget.group.city} districts',
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
              ],
            ),
            onTap: widget.onSelectCity,
          ),
        ),
        if (_expanded)
          for (final entry in districts)
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 12, top: 2),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                selected: widget.selectedDistrict == entry.key,
                selectedTileColor: color.withValues(alpha: 0.12),
                selectedColor: onSurface,
                leading: const SizedBox(
                  width: 24,
                  child: Icon(Icons.subdirectory_arrow_right, size: 16),
                ),
                title: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: widget.selectedDistrict == entry.key
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                trailing: Text('${entry.value}'),
                onTap: () => widget.onSelectDistrict(entry.key),
              ),
            ),
      ],
    );
  }
}

/// Floats [PlacePreviewCard] for the selected place (when [previewVisible])
/// just above the list sheet's current top edge, tracking the sheet
/// continuously like [_AttributionBar]. Full width minus 12dp margins. Fades
/// + slides in, and cross-fades when another pin is tapped (keyed by place
/// id). Listens to the selection itself, so a pin tap rebuilds just this
/// card rather than the map screen.
class _PreviewCardLayer extends StatelessWidget {
  const _PreviewCardLayer({
    required this.sheetExtentController,
    required this.places,
    required this.selectedId,
    required this.previewVisible,
    required this.onOpenDetail,
  });

  final DraggableScrollableController sheetExtentController;

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
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
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
                    onOpenDetails: () => onOpenDetail(place),
                  ),
          );
        },
      ),
    );
  }
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
