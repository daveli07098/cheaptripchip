import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/mock_data.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';

/// Detail card (ANALYSIS.md §4): photo header, location badge, AI description,
/// original caption, source attribution, address + hours, "Open in Google Maps"
/// deep link, and the social/board action row.
///
/// Presented as a draggable bottom sheet so it works over the map or the feed.
class PlaceDetailSheet extends StatelessWidget {
  const PlaceDetailSheet({super.key, required this.place});

  final Place place;

  static Future<void> show(BuildContext context, Place place) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaceDetailSheet(place: place),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.categoryColor(place.category);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.ink,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.zero,
            children: [
              _PhotoHeader(place: place, color: color),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AreaBadge(label: place.areaLabel, color: color),
                    const SizedBox(height: 12),
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (place.award != null) ...[
                      const SizedBox(height: 8),
                      _AwardChip(label: place.award!),
                    ],
                    const SizedBox(height: 18),
                    _ActionRow(place: place),
                    const SizedBox(height: 20),
                    _SectionLabel('About / 簡介'),
                    const SizedBox(height: 6),
                    Text(
                      place.descriptionEn,
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    _SectionLabel('Original caption / 原文'),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        place.originalCaption,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _InfoRow(icon: Icons.location_on, text: place.address),
                    _InfoRow(icon: Icons.schedule, text: place.hours),
                    _InfoRow(
                      icon: Icons.person_outline,
                      text: 'By ${place.sourceHandle} '
                          'on ${place.sourcePlatform.label}',
                    ),
                    const SizedBox(height: 22),
                    _OpenInMapsButton(place: place),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader({required this.place, required this.color});

  final Place place;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Production: swipeable photo carousel from the source post.
    return Stack(
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.4)],
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Center(
            child: Icon(
              AppTheme.categoryIcon(place.category),
              size: 56,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AreaBadge extends StatelessWidget {
  const _AreaBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _AwardChip extends StatelessWidget {
  const _AwardChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC857).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events, size: 15, color: Color(0xFFFFC857)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFFC857),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _addToBoard(context),
            icon: const Icon(Icons.bookmark_add, size: 18),
            label: const Text('Add to board'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.coral,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _IconAction(icon: Icons.favorite_border, onTap: () {}),
        _IconAction(icon: Icons.ios_share, onTap: () {}),
      ],
    );
  }

  void _addToBoard(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Add to board',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final board in MockData.boards)
              ListTile(
                leading: Text(board.emoji,
                    style: const TextStyle(fontSize: 22)),
                title: Text(board.name),
                subtitle: Text('${board.itemCount} places'),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added to ${board.name}'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton.filledTonal(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.surfaceAlt,
          padding: const EdgeInsets.all(12),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Colors.white.withValues(alpha: 0.5),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.55)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenInMapsButton extends StatelessWidget {
  const _OpenInMapsButton({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        // "Open in Google Maps" is just a URL — no API key, no billing.
        final ok = await launchUrl(
          place.googleMapsUrl,
          mode: LaunchMode.externalApplication,
        );
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google Maps')),
          );
        }
      },
      icon: const Icon(Icons.map_outlined, size: 18),
      label: const Text('Open in Google Maps / 在 Google 地圖中開啟'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size(double.infinity, 0),
      ),
    );
  }
}
