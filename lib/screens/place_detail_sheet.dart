import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/board_store.dart';
import '../data/place_store.dart';
import '../models/board.dart';
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
    final color = AppTheme.categoryColor(
      place.category,
      Theme.of(context).brightness,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        place.originalCaption,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Theme.of(context).colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _InfoRow(icon: Icons.location_on, text: place.address),
                    _InfoRow(icon: Icons.schedule, text: place.hours),
                    _InfoRow(
                      icon: Icons.person_outline,
                      text:
                          'By ${place.sourceHandle} '
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
              colors: [
                color.withValues(alpha: 0.9),
                color.withValues(alpha: 0.4),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          // Emoji aren't accessible labels — expose the category via
          // Semantics and hide the raw glyph from the a11y tree (WCAG 1.4.1).
          child: Center(
            child: Semantics(
              label: place.category.labelEn,
              child: ExcludeSemantics(
                child: Text(
                  place.category.emoji,
                  style: const TextStyle(fontSize: 56, height: 1),
                ),
              ),
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
                // Sits on the category-colour gradient (not the scaffold),
                // which stays vivid/dark in both themes — a fixed white
                // handle keeps working there, no theme lookup needed.
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
        ValueListenableBuilder<List<Place>>(
          valueListenable: PlaceStore.instance.places,
          builder: (context, places, _) {
            final current = places.firstWhere(
              (p) => p.id == place.id,
              orElse: () => place,
            );
            // IconButton.isSelected only drives Semantics(selected: ...),
            // not toggled state — wrap explicitly so screen readers announce
            // this as a toggle button, not a selection.
            return Semantics(
              toggled: current.isFavorite,
              child: _IconAction(
                icon: current.isFavorite
                    ? Icons.favorite
                    : Icons.favorite_border,
                tooltip: current.isFavorite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                isSelected: current.isFavorite,
                onTap: () => PlaceStore.instance.toggleFavorite(place.id),
              ),
            );
          },
        ),
        _IconAction(icon: Icons.ios_share, tooltip: 'Share', onTap: _share),
      ],
    );
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${place.name} — ${place.areaLabel}, ${place.region}\n'
              '${place.googleMapsUrl}',
        ),
      );
    } catch (e) {
      debugPrint('Share failed: $e');
    }
  }

  void _addToBoard(BuildContext context) {
    // Captured before the sheet opens so the "Added to <board>" SnackBar
    // still has a valid ScaffoldMessenger once the picker sheet has closed.
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _BoardPickerSheet(place: place, messenger: messenger),
      ),
    );
  }
}

/// "Add to board" picker: lists [BoardStore.instance.boards] plus a
/// "New board…" row that reveals a name field to create one on the fly.
class _BoardPickerSheet extends StatefulWidget {
  const _BoardPickerSheet({required this.place, required this.messenger});

  final Place place;
  final ScaffoldMessengerState messenger;

  @override
  State<_BoardPickerSheet> createState() => _BoardPickerSheetState();
}

class _BoardPickerSheetState extends State<_BoardPickerSheet> {
  final _nameController = TextEditingController();
  bool _creatingNew = false;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _notifyAdded(String boardName) {
    widget.messenger.showSnackBar(
      SnackBar(
        content: Text('Added to $boardName'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addToExisting(Board board) async {
    setState(() => _busy = true);
    try {
      await BoardStore.instance.addPlaceToBoard(
        boardId: board.id,
        placeId: widget.place.id,
      );
      if (!mounted) return;
      Navigator.pop(context);
      _notifyAdded(board.name);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndAdd() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final board = await BoardStore.instance.createBoard(name);
      await BoardStore.instance.addPlaceToBoard(
        boardId: board.id,
        placeId: widget.place.id,
      );
      if (!mounted) return;
      Navigator.pop(context);
      _notifyAdded(board.name);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Add to board',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          ValueListenableBuilder<List<Board>>(
            valueListenable: BoardStore.instance.boards,
            builder: (context, boards, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final board in boards)
                    ListTile(
                      leading: Text(
                        board.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                      title: Text(board.name),
                      subtitle: Text(
                        '${board.itemCount} ${board.itemCount == 1 ? 'place' : 'places'}',
                      ),
                      trailing: const Icon(Icons.add_circle_outline),
                      enabled: !_busy,
                      onTap: () => _addToExisting(board),
                    ),
                ],
              );
            },
          ),
          if (!_creatingNew)
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New board…'),
              enabled: !_busy,
              onTap: () => setState(() => _creatingNew = true),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      autofocus: true,
                      enabled: !_busy,
                      decoration: const InputDecoration(hintText: 'Board name'),
                      onSubmitted: (_) => _createAndAdd(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _busy ? null : _createAndAdd,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.coral,
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.isSelected = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton.filledTonal(
        onPressed: onTap,
        tooltip: tooltip,
        isSelected: isSelected,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
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
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
          Icon(
            icon,
            size: 18,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
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
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size(double.infinity, 0),
      ),
    );
  }
}
