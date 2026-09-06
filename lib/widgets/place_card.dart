import 'package:flutter/material.dart';

import '../models/place.dart';
import '../theme/app_theme.dart';

/// Feed/sidebar card: category swatch, name, area tag, AI description preview,
/// and the "1match" confidence indicator (Yaay parity, ANALYSIS.md §6).
class PlaceCard extends StatelessWidget {
  const PlaceCard({super.key, required this.place, required this.onTap});

  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppTheme.categoryColor(place.category, theme.brightness);
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo placeholder — production pulls the IG carousel's first frame.
              _Thumb(color: color, category: place.category),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            place.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (place.matchConfident) const _MatchBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Google-Maps-style metadata line: rating · price · category,
                    // each part optional so e.g. an un-rated place still renders
                    // cleanly as just the category label.
                    Text(
                      _metaLine(place),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.place, size: 14, color: color),
                        const SizedBox(width: 3),
                        Text(
                          '${place.areaLabel} · ${place.region}',
                          style: TextStyle(
                            fontSize: 12,
                            color: onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      place.descriptionEn,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: onSurfaceVariant.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Builds the Google-Maps-style metadata line, e.g.
/// "4.7 ★ (85) · $600–1,400 · Restaurant". Rating and price are optional and
/// drop their own separator cleanly when absent; the category label always
/// renders last.
String _metaLine(Place place) {
  final parts = <String>[];
  if (place.hasRating) {
    final rating = place.rating!.toStringAsFixed(1);
    final reviews = place.reviewCount != null ? ' (${place.reviewCount})' : '';
    parts.add('$rating ★$reviews');
  }
  if (place.priceRange != null) parts.add(place.priceRange!);
  parts.add(place.category.labelEn);
  return parts.join(' · ');
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color, required this.category});

  final Color color;
  final PlaceCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.85),
            color.withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      // Emoji aren't accessible labels (screen readers announce the CLDR
      // glyph name, not the category) — expose the real label via Semantics
      // and hide the raw glyph from the a11y tree.
      child: Center(
        child: Semantics(
          label: category.labelEn,
          child: ExcludeSemantics(
            child: Text(
              category.emoji,
              style: const TextStyle(fontSize: 28, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchBadge extends StatelessWidget {
  const _MatchBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.coral.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, size: 12, color: AppTheme.coral),
          const SizedBox(width: 3),
          Text(
            '1 match',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.coral.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}
