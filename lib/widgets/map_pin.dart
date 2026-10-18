import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/map_filter.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';
import 'accessible_emoji.dart';
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
    // A stand-in location (Place.locationConfirmed false): semi-transparent
    // fill + dashed border, so it never reads as a real pin.
    final unconfirmed = !place.locationConfirmed;

    Widget badge = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: unconfirmed ? color.withValues(alpha: 0.5) : color,
        shape: BoxShape.circle,
        // Transparent (not absent) when unconfirmed, so the pin keeps its
        // size; the dashed ring is painted over it.
        border: Border.all(
          color: unconfirmed ? Colors.transparent : borderColor,
          width: 2,
        ),
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
              alpha: unconfirmed ? 0.2 : (selected ? 0.55 : 0.4),
            ),
            blurRadius: selected ? 10 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // Flutter's emoji vertical centering is unreliable
      // (flutter/flutter#119623) — `height: 1` on the style plus
      // this outer `Center` (not `TextAlign.center`) is what
      // actually keeps the glyph centered in the circle.
      child: Center(
        // WCAG 1.4.1: the emoji glyph alone isn't an accessible
        // label, so screen readers get the pin's English name.
        child: AccessibleEmoji(
          emoji: placeMarkerEmoji(place),
          label: unconfirmed
              ? '${placeMarkerLabel(place)}, location unconfirmed'
              : placeMarkerLabel(place),
          fontSize: 20,
          height: 1,
          selected: selected,
        ),
      ),
    );
    if (unconfirmed) {
      badge = CustomPaint(
        foregroundPainter: DashedRingPainter(color: ringColor),
        child: badge,
      );
    }

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
            child: badge,
          ),
        ),
      ),
    );
  }
}

/// Dashed circle just inside the bounds — the unconfirmed [MapPin]'s
/// border.
@visibleForTesting
class DashedRingPainter extends CustomPainter {
  const DashedRingPainter({required this.color});

  final Color color;

  static const _dashes = 10;
  static const _strokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final rect = (Offset.zero & size).deflate(_strokeWidth / 2);
    const sweep = 2 * math.pi / _dashes;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
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
