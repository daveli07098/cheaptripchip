import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/photo_store.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';
import 'place_photo.dart';
import 'place_photo_actions.dart';
import 'score_stars.dart';

/// Roughly how tall [PlacePreviewCard] renders at the default text scale —
/// used to lift other floating map chrome (the attribution button) clear of
/// it. Not a layout constraint: the card still sizes to its content.
const double kPlacePreviewCardApproxHeight = 136;

/// Google-Maps-style floating card for a tapped map pin: thumbnail, name,
/// category + area, the user's score, and Details / Maps / photo actions.
/// Tapping the card body opens the details too.
class PlacePreviewCard extends StatelessWidget {
  const PlacePreviewCard({
    super.key,
    required this.place,
    required this.onOpenDetails,
  });

  final Place place;
  final VoidCallback onOpenDetails;

  static const double _thumbSize = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = AppTheme.categoryColor(place.category, theme.brightness);
    final area = [
      place.areaLabel,
      place.region,
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    return Material(
      color: scheme.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetails,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox.square(
                      dimension: _thumbSize,
                      child: PlacePhoto(
                        place: place,
                        cacheWidth: (_thumbSize * 3).round(),
                        fallback: _EmojiTile(place: place, color: color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Semantics(
                              label: place.category.labelEn,
                              child: ExcludeSemantics(
                                child: Text(
                                  place.category.emoji,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                area,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (place.myScore != null) ...[
                              const SizedBox(width: 8),
                              ScoreBadge(score: place.myScore!),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _CardAction(
                    icon: Icons.info_outline,
                    label: 'Details',
                    onPressed: onOpenDetails,
                  ),
                  _CardAction(
                    icon: Icons.map_outlined,
                    label: 'Maps',
                    onPressed: () => _openInMaps(context),
                  ),
                  ValueListenableBuilder<Uint8List?>(
                    valueListenable: PhotoStore.instance.photoFor(place.id),
                    builder: (context, bytes, _) => _CardAction(
                      icon: Icons.add_a_photo_outlined,
                      label: bytes == null ? 'Add photo' : 'Change photo',
                      onPressed: () => showPlacePhotoActions(context, place),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInMaps(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // Same deep link as the detail sheet's "Open in Google Maps" — just a
    // URL, no API key.
    final ok = await launchUrl(
      place.googleMapsUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    );
  }
}

/// No-photo thumbnail: the category emoji on a square tinted with the
/// category colour.
class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.place, required this.color});

  final Place place;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color.withValues(alpha: 0.22),
      child: Center(
        child: Semantics(
          label: place.category.labelEn,
          child: ExcludeSemantics(
            child: Text(
              place.category.emoji,
              style: const TextStyle(fontSize: 32, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}
