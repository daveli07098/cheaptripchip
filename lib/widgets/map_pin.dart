import 'package:flutter/material.dart';

import '../data/map_filter.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';
import 'marker_clustering.dart';

/// A single place pin rendered on the map.
///
/// The tap target is a full 48x48 box (Material's minimum recommended touch
/// size) even though the visible coral badge is smaller — the surrounding
/// space is transparent padding so the badge doesn't look oversized while
/// still being easy to tap accurately.
class MapPin extends StatelessWidget {
  const MapPin({
    super.key,
    required this.place,
    required this.selected,
    required this.brightness,
    required this.onTap,
  });

  final Place place;

  /// Selected pins scale up slightly; z-order (drawing them last/on top so
  /// neighbours never occlude them) is the caller's responsibility — see
  /// `_ClusterMarkerLayer` in map_screen.dart.
  final bool selected;

  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.categoryColor(place.category, brightness);
    // Theme-driven instead of hardcoded Colors.white so the pin's border
    // stays visible against BOTH the dark and light map tiles.
    final borderColor = Theme.of(context).colorScheme.surface;
    // Selection ring sits outside the surface-coloured border so it reads as
    // a distinct affordance rather than a thicker version of that border.
    final ringColor = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedScale(
            scale: selected ? 1.25 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 2),
                boxShadow: [
                  if (selected)
                    BoxShadow(
                      // The ring: a wider "border" drawn via a second
                      // spread-out shadow with no blur, outside the
                      // surface-coloured border above.
                      color: ringColor,
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: selected ? 0.55 : 0.4,
                    ),
                    blurRadius: selected ? 10 : 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Semantics(
                // WCAG 1.4.1: the emoji glyph alone isn't an accessible
                // label, so screen readers get the category's English name
                // instead of (or in addition to) the glyph.
                label: _pinLabel(place),
                selected: selected,
                child: ExcludeSemantics(
                  child: Center(
                    // Flutter's emoji vertical centering is unreliable
                    // (flutter/flutter#119623) — `height: 1` on the style
                    // plus this outer `Center` (not `TextAlign.center`) is
                    // what actually keeps the glyph centered in the circle.
                    child: Text(
                      _pinEmoji(place),
                      style: const TextStyle(fontSize: 20, height: 1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge rendered for a grid cell holding two or more places (see
/// [clusterPlaces]). Shows the member count and, if every member shares one
/// category, that category's colour/emoji as a hint of what's inside.
class ClusterPin extends StatelessWidget {
  const ClusterPin({
    super.key,
    required this.cluster,
    required this.brightness,
    required this.onTap,
  });

  final PlaceCluster cluster;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shared = cluster.sharedCategory;
    final color = shared != null
        ? AppTheme.categoryColor(shared, brightness)
        : AppTheme.coral;
    final borderColor = Theme.of(context).colorScheme.surface;
    final count = cluster.places.length;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: shared != null
            ? '$count ${shared.labelEn} places, tap to zoom in'
            : '$count places, tap to zoom in',
        child: ExcludeSemantics(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (shared != null)
                    Text(
                      shared.emoji,
                      style: const TextStyle(fontSize: 14, height: 1),
                    ),
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
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

/// The pin shows the same icon as the place's entry in the ☰ drawer: a
/// restaurant's sub-type (🍜 Ramen, 🍣 Sushi…) when known, otherwise the
/// category emoji. "Other" restaurants keep the generic 🍽️. Uses the
/// memoized [restaurantTypeOf] — pins rebuild on camera moves, and the raw
/// getter re-runs keyword detection on every call.
String _pinEmoji(Place place) {
  final type = restaurantTypeOf(place);
  if (type != null && type != RestaurantType.other) return type.emoji;
  return place.category.emoji;
}

/// Accessible name matching [_pinEmoji] (WCAG 1.4.1).
String _pinLabel(Place place) {
  final type = restaurantTypeOf(place);
  if (type != null && type != RestaurantType.other) return type.labelEn;
  return place.category.labelEn;
}
