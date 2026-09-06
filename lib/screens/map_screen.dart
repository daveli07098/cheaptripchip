import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../data/mock_data.dart';
import '../data/place_store.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';
import '../widgets/map_pin.dart';
import '../widgets/marker_clustering.dart';
import '../widgets/place_list_sheet.dart';
import 'place_detail_sheet.dart';

/// Map-first surface (ANALYSIS.md §3): theme-aware CartoDB tiles, coral pins
/// grid-clustered at low zoom, category filter chips with counts, and a
/// persistent (non-modal) place-list sheet kept in sync with the pins —
/// tap a pin to preview it in the list, tap a row (or a pin twice) to open
/// the full detail sheet.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();

  /// Drives (and lets us read `.size` from) the persistent list sheet's
  /// current extent — needed to pad map moves so results land above it.
  final _sheetExtentController = DraggableScrollableController();

  final _listSheetController = PlaceListSheetController();

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
        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: MockData.tokyoCenter,
                initialZoom: 12,
                minZoom: 3,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  // CartoDB Dark Matter / Positron — free OSM-based tiles
                  // ($0, see ANALYSIS.md), picked per theme brightness.
                  urlTemplate: AppTheme.mapTileUrl(brightness),
                  subdomains: const ['a', 'b', 'c', 'd'],
                  retinaMode: RetinaMode.isHighDensity(context),
                  userAgentPackageName: 'com.cheaptripchip.app',
                ),
                _ClusterMarkerLayer(
                  places: visible,
                  selectedId: _selectedPlaceId,
                  brightness: brightness,
                  onTapPlace: _selectFromPin,
                  onTapCluster: (cluster) => _focusCluster(context, cluster),
                ),
                const _AttributionBar(),
              ],
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _CategoryChips(
                    counts: _counts(all),
                    total: all.length,
                    selected: _selected,
                    onSelect: (c) => setState(() => _selected = c),
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
            ),
          ],
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

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
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
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _Chip(
            label: 'All $total',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final entry in counts.entries)
            _Chip(
              label: '${entry.key.labelEn} ${entry.value}',
              emoji: entry.key.emoji,
              categoryLabel: entry.key.labelEn,
              color: AppTheme.categoryColor(
                entry.key,
                Theme.of(context).brightness,
              ),
              selected: selected == entry.key,
              onTap: () => onSelect(entry.key),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
    this.categoryLabel,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? emoji;

  /// Accessible label for [emoji] (WCAG 1.4.1 — the glyph alone isn't one).
  final String? categoryLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: Material(
          color: selected ? (color ?? AppTheme.coral) : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (emoji != null) ...[
                    Semantics(
                      label: categoryLabel,
                      child: ExcludeSemantics(
                        child: Text(
                          emoji!,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttributionBar extends StatelessWidget {
  const _AttributionBar();

  @override
  Widget build(BuildContext context) {
    // OSM/CartoDB attribution is required by the tile licence.
    return const RichAttributionWidget(
      attributions: [
        TextSourceAttribution('OpenStreetMap contributors'),
        TextSourceAttribution('CARTO'),
      ],
    );
  }
}
