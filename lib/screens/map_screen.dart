import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../data/mock_data.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';
import 'place_detail_sheet.dart';

/// Map-first surface (ANALYSIS.md §3): dark CartoDB tiles, coral pins,
/// category filter chips with counts, tap a pin → detail sheet.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _controller = MapController();

  /// null = "All". Otherwise filter pins to the selected category.
  PlaceCategory? _selected;

  List<Place> get _visible => _selected == null
      ? MockData.places
      : MockData.places.where((p) => p.category == _selected).toList();

  Map<PlaceCategory, int> get _counts {
    final map = <PlaceCategory, int>{};
    for (final p in MockData.places) {
      map[p.category] = (map[p.category] ?? 0) + 1;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: const MapOptions(
            initialCenter: MockData.tokyoCenter,
            initialZoom: 12,
            minZoom: 3,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              // CartoDB Dark Matter — free OSM-based dark tiles ($0, see ANALYSIS.md).
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              retinaMode: RetinaMode.isHighDensity(context),
              userAgentPackageName: 'com.cheaptripchip.app',
            ),
            MarkerLayer(
              markers: [
                for (final place in _visible)
                  Marker(
                    point: place.location,
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: _PinMarker(
                      place: place,
                      onTap: () => PlaceDetailSheet.show(context, place),
                    ),
                  ),
              ],
            ),
            const _AttributionBar(),
          ],
        ),
        SafeArea(
          child: Column(
            children: [
              _CategoryChips(
                counts: _counts,
                total: MockData.places.length,
                selected: _selected,
                onSelect: (c) => setState(() => _selected = c),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PinMarker extends StatelessWidget {
  const _PinMarker({required this.place, required this.onTap});

  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.categoryColor(place.category);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              AppTheme.categoryIcon(place.category),
              size: 16,
              color: Colors.white,
            ),
          ),
        ],
      ),
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
              icon: AppTheme.categoryIcon(entry.key),
              color: AppTheme.categoryColor(entry.key),
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
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
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
                  if (icon != null) ...[
                    Icon(icon,
                        size: 15,
                        color: selected ? Colors.white : color ?? Colors.white),
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
