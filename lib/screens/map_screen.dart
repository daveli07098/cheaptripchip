import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../data/place_store.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';
import '../theme/theme_toggle_button.dart';
import '../widgets/account_button.dart';
import '../widgets/map_pin.dart';
import '../widgets/marker_clustering.dart';
import '../widgets/place_list_sheet.dart';
import 'place_detail_sheet.dart';

/// Map-first surface (ANALYSIS.md §3): theme-aware CartoDB tiles, coral pins
/// grid-clustered at low zoom, a category filter in a left drawer (the
/// top-left button shows the active filter), and a
/// persistent (non-modal) place-list sheet kept in sync with the pins —
/// tap a pin to preview it in the list, tap a row (or a pin twice) to open
/// the full detail sheet.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.onAddFind});

  /// Forwarded straight through to [PlaceListSheet] — see its doc comment
  /// for what triggers this (the "+" affordance for adding a new find).
  final VoidCallback onAddFind;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();

  /// Drives (and lets us read `.size` from) the persistent list sheet's
  /// current extent — needed to pad map moves so results land above it.
  final _sheetExtentController = DraggableScrollableController();

  final _listSheetController = PlaceListSheetController();

  /// Opens the category drawer from the top-left filter button.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// null = "All". Otherwise filter pins to the selected category.
  PlaceCategory? _selected;

  /// The place currently highlighted on both the map (max z-order + scale)
  /// and the list (scrolled into view + tinted row).
  String? _selectedPlaceId;

  List<Place> _visible(List<Place> all) => _selected == null
      ? all
      : all.where((p) => p.category == _selected).toList();

  Map<PlaceCategory, int> _counts(List<Place> all) {
    final map = <PlaceCategory, int>{};
    for (final p in all) {
      map[p.category] = (map[p.category] ?? 0) + 1;
    }
    return map;
  }

  /// How many logical pixels of screen height the list sheet currently
  /// covers, used to keep map moves from landing a pin underneath it.
  double _sheetPixels(BuildContext context) {
    final fraction = _sheetExtentController.isAttached
        ? _sheetExtentController.size
        : kSheetPeek;
    return MediaQuery.of(context).size.height * fraction;
  }

  /// Pin tapped on the map: highlight + scroll the matching list row into
  /// view. Deliberately does NOT move the map — re-centering under an
  /// active pan/tap is a documented anti-pattern that fights the user.
  void _selectFromPin(Place place) {
    setState(() => _selectedPlaceId = place.id);
    _listSheetController.scrollToPlace(place.id);
  }

  /// Row tapped in the list sheet: highlight + pan/zoom the map to it,
  /// offsetting the target upward so it lands above the sheet rather than
  /// underneath it.
  void _selectFromList(BuildContext context, Place place) {
    setState(() => _selectedPlaceId = place.id);
    final targetZoom = math.max(_mapController.camera.zoom, 15.0);
    _mapController.move(
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
  /// isn't computed as if that space were still available.
  void _focusCluster(BuildContext context, PlaceCluster cluster) {
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: [for (final p in cluster.places) p.location],
        padding: EdgeInsets.fromLTRB(48, 96, 48, 48 + _sheetPixels(context)),
        maxZoom: 17,
      ),
    );
  }

  @override
  void dispose() {
    _sheetExtentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, all, _) {
        final visible = _visible(all);
        final brightness = Theme.of(context).brightness;
        final counts = _counts(all);
        return Scaffold(
          key: _scaffoldKey,
          // Edge-swipe would fight map panning and Android's back gesture;
          // the drawer opens from the filter button only.
          drawerEnableOpenDragGesture: false,
          drawer: _CategoryDrawer(
            counts: counts,
            total: all.length,
            selected: _selected,
            onSelect: (c) {
              setState(() => _selected = c);
              Navigator.of(context).pop();
            },
          ),
          body: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  // Fit every place on first load rather than a fixed
                  // center/zoom: a hardcoded zoom happened to clip the
                  // Hoshinoya (Stay) pin, the easternmost place, right at the
                  // viewport edge — there was no bounds-fitting logic here at
                  // all, unlike `_focusCluster`/`_selectFromList` below, which
                  // both already fit-to-content. `CameraFit.coordinates` is
                  // resolved against the map's actual layout size, so — like
                  // those two — it's computed with the sheet's current height
                  // padded out from the bottom so no pin lands underneath it.
                  initialCameraFit: CameraFit.coordinates(
                    coordinates: [for (final p in all) p.location],
                    padding: EdgeInsets.fromLTRB(
                      48,
                      96,
                      48,
                      48 + _sheetPixels(context),
                    ),
                    maxZoom: 17,
                  ),
                  minZoom: 3,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    // OSM raster tiles — see AppTheme.mapTileUrl doc comment
                    // re: usage-policy limits and swapping in a keyed provider.
                    urlTemplate: AppTheme.mapTileUrl,
                    userAgentPackageName: 'com.cheaptripchip.app',
                    // OSM has no dark-tile variant, so dark mode is simulated
                    // by inverting/hue-rotating the same tiles.
                    tileBuilder: brightness == Brightness.dark
                        ? darkModeTileBuilder
                        : null,
                  ),
                  _ClusterMarkerLayer(
                    places: visible,
                    selectedId: _selectedPlaceId,
                    brightness: brightness,
                    onTapPlace: _selectFromPin,
                    onTapCluster: (cluster) => _focusCluster(context, cluster),
                  ),
                  _AttributionBar(
                    sheetExtentController: _sheetExtentController,
                  ),
                ],
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _TopBar(
                      selected: _selected,
                      count: _selected == null
                          ? all.length
                          : (counts[_selected] ?? 0),
                      onOpenFilter: () =>
                          _scaffoldKey.currentState?.openDrawer(),
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
/// is what makes clustering recompute automatically on every pan/zoom/
/// rotate: this widget is a child of [FlutterMap], so that read registers a
/// dependency on flutter_map's `MapInheritedModel` and triggers a rebuild of
/// just this layer whenever the camera changes.
class _ClusterMarkerLayer extends StatelessWidget {
  const _ClusterMarkerLayer({
    required this.places,
    required this.selectedId,
    required this.brightness,
    required this.onTapPlace,
    required this.onTapCluster,
  });

  final List<Place> places;
  final String? selectedId;
  final Brightness brightness;
  final ValueChanged<Place> onTapPlace;
  final ValueChanged<PlaceCluster> onTapCluster;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final clusters = clusterPlaces(places: places, camera: camera);

    // Split out the selected (unclustered) pin so it can be appended last —
    // MarkerLayer draws later entries on top, giving the selected pin max
    // z-order so neighbours never occlude it.
    final unselected = <PlaceCluster>[];
    PlaceCluster? selectedCluster;
    for (final cluster in clusters) {
      if (cluster.isSingle && cluster.places.first.id == selectedId) {
        selectedCluster = cluster;
      } else {
        unselected.add(cluster);
      }
    }
    final ordered = [...unselected, ?selectedCluster];

    return MarkerLayer(
      markers: [
        for (final cluster in ordered)
          if (cluster.isSingle)
            Marker(
              point: cluster.places.first.location,
              width: 48,
              height: 48,
              alignment: Alignment.topCenter,
              child: MapPin(
                place: cluster.places.first,
                selected: cluster.places.first.id == selectedId,
                brightness: brightness,
                onTap: () => onTapPlace(cluster.places.first),
              ),
            )
          else
            Marker(
              point: cluster.center,
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: ClusterPin(
                cluster: cluster,
                brightness: brightness,
                onTap: () => onTapCluster(cluster),
              ),
            ),
      ],
    );
  }
}

/// Floating top row: the filter button (opens [_CategoryDrawer] and shows
/// the active category + count) on the left, account + theme on the right.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selected,
    required this.count,
    required this.onOpenFilter,
  });

  final PlaceCategory? selected;
  final int count;
  final VoidCallback onOpenFilter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = selected == null ? 'All' : selected!.labelEn;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Material(
            color: scheme.surface,
            elevation: 2,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onOpenFilter,
              child: Semantics(
                button: true,
                label: 'Filter by category, showing $label, $count places',
                child: ExcludeSemantics(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.menu, size: 20),
                          const SizedBox(width: 8),
                          if (selected != null) ...[
                            Text(
                              selected!.emoji,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '$label · $count',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Material(
            color: scheme.surface,
            shape: const CircleBorder(),
            elevation: 2,
            // AccountButton's own tap target is 40x40 (per spec); padded out
            // to 48x48 here so its disc matches ThemeToggleButton's — that
            // one's an IconButton, whose default 48dp footprint drives its
            // own Material's size.
            child: const SizedBox.square(
              dimension: 48,
              child: Center(child: AccountButton()),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: scheme.surface,
            shape: const CircleBorder(),
            elevation: 2,
            child: const ThemeToggleButton(),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// Left drawer listing "All" plus every category present, with counts.
/// Tapping a row applies the filter and closes the drawer.
class _CategoryDrawer extends StatelessWidget {
  const _CategoryDrawer({
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelect,
  });

  final Map<PlaceCategory, int> counts;
  final int total;
  final PlaceCategory? selected;
  final ValueChanged<PlaceCategory?> onSelect;

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

class _AttributionBar extends StatelessWidget {
  const _AttributionBar({required this.sheetExtentController});

  /// Tracked so the bar can float just above the persistent list sheet's
  /// current top edge instead of sitting permanently underneath it.
  final DraggableScrollableController sheetExtentController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // Rebuilds on every drag of the sheet, not just on settle, so the bar
      // tracks it continuously rather than jumping at the end.
      animation: sheetExtentController,
      builder: (context, _) {
        final fraction = sheetExtentController.isAttached
            ? sheetExtentController.size
            : kSheetPeek;
        final sheetPixels = MediaQuery.of(context).size.height * fraction;
        return Positioned(
          right: 8,
          bottom: sheetPixels + 8,
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
