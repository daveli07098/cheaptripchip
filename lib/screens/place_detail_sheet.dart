import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/board_store.dart';
import '../data/photo_store.dart';
import '../data/place_store.dart';
import '../models/board.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';
import '../widgets/board_picker_sheet.dart';
import '../widgets/place_photo.dart';
import '../widgets/place_photo_actions.dart';
import '../widgets/score_stars.dart';

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
        // Own messenger + transparent Scaffold sized to the sheet: SnackBars
        // shown from inside the sheet (photo errors, Maps failures) render
        // on top of it instead of on the root Scaffold, which sits
        // underneath the modal barrier. The board picker (a modal route on
        // top of this one) has its own messenger for the same reason — see
        // board_picker_sheet.dart.
        return ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            // Dialogs/pickers raising the keyboard over this sheet shouldn't
            // shrink it (the pre-Scaffold Container ignored viewInsets too).
            resizeToAvoidBottomInset: false,
            body: _sheetBody(context, controller, color),
          ),
        );
      },
    );
  }

  Widget _sheetBody(
    BuildContext context,
    ScrollController controller,
    Color color,
  ) {
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
                _MyReviewSection(place: place),
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
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
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
  }
}

class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader({required this.place, required this.color});

  final Place place;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Re-read the current copy so PhotoStore sees an up-to-date
    // `myPhotoAt` marker (it gates the Firestore read on it).
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, _, _) {
        final current = PlaceStore.instance.byIdOrNull(place.id) ?? place;
        return _buildHeader(context, current);
      },
    );
  }

  Widget _buildHeader(BuildContext context, Place current) {
    // Preference: the user's own photo, then the first source photo, then
    // the category-colour gradient with the emoji.
    final gradient = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.4)],
        ),
      ),
      // Emoji aren't accessible labels — expose the category via
      // Semantics and hide the raw glyph from the a11y tree (WCAG 1.4.1).
      child: Center(
        child: Semantics(
          label: current.category.labelEn,
          child: ExcludeSemantics(
            child: Text(
              current.category.emoji,
              style: const TextStyle(fontSize: 56, height: 1),
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: PlacePhoto(place: current, fallback: gradient),
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
                // Sits on the category-colour gradient or a photo (not the
                // scaffold), which stays vivid/dark in both themes — a
                // fixed white handle keeps working there, no theme lookup
                // needed.
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Positioned(right: 12, bottom: 12, child: _PhotoButtons(place: current)),
      ],
    );
  }
}

/// Add / Change / Remove for the user's own photo, over the header's
/// bottom-right corner.
class _PhotoButtons extends StatelessWidget {
  const _PhotoButtons({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: 0.55),
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: PhotoStore.instance.photoFor(place.id),
      builder: (context, bytes, _) {
        final hasPhoto = bytes != null;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              style: style,
              onPressed: () => showPlacePhotoActions(context, place),
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(hasPhoto ? 'Change photo' : 'Add photo'),
            ),
            if (hasPhoto) ...[
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.55),
                  foregroundColor: Colors.white,
                ),
                tooltip: 'Remove photo',
                onPressed: () => confirmRemovePlacePhoto(context, place),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ],
        );
      },
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
          child: ValueListenableBuilder<List<Board>>(
            valueListenable: BoardStore.instance.boards,
            builder: (context, boards, _) {
              final containing = BoardStore.instance.boardsContaining(place.id);
              final label = addToBoardLabel(containing);
              return Semantics(
                label: label,
                child: FilledButton.icon(
                  onPressed: () => BoardPickerSheet.show(context, place),
                  icon: Icon(
                    containing.isEmpty ? Icons.bookmark_add : Icons.check,
                    size: 18,
                  ),
                  label: Text(label),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.coral,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              );
            },
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
}

/// "My review" section: a [ScoreStars] picker (saves immediately on every
/// change) plus a notes affordance (opens [_NotesDialog] to edit).
///
/// Reads [PlaceStore.instance.places] the same way [_ActionRow] does for the
/// favourite toggle — the `place` this widget is built with can go stale the
/// moment a review is saved, so every rebuild re-looks-up the current copy
/// by id.
class _MyReviewSection extends StatelessWidget {
  const _MyReviewSection({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, places, _) {
        final current = PlaceStore.instance.byIdOrNull(place.id) ?? place;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('My review / 我的評價'),
            const SizedBox(height: 8),
            ScoreStars(
              value: current.myScore,
              onChanged: (score) => PlaceStore.instance.updateReview(
                current.id,
                score: score,
                notes: current.myNotes,
              ),
            ),
            const SizedBox(height: 10),
            _MyNotes(place: current),
          ],
        );
      },
    );
  }
}

class _MyNotes extends StatelessWidget {
  const _MyNotes({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    if (place.myNotes.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _editNotes(context),
          icon: const Icon(Icons.edit_note, size: 18),
          label: const Text('Add notes'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 44),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => _editNotes(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          place.myNotes,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  Future<void> _editNotes(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _NotesDialog(initialText: place.myNotes),
    );
    // The dialog already popped itself before returning — no BuildContext
    // use after this await, so no `mounted` check is needed here.
    if (result == null) return;
    await PlaceStore.instance.updateReview(
      place.id,
      score: place.myScore,
      notes: result,
    );
  }
}

/// Multiline notes editor, opened by [_MyNotes]. Pops with the trimmed text
/// on Save, or `null` on Cancel/dismiss — the caller decides what to persist.
/// Owns its controller: disposing it as soon as `showDialog` returned crashed,
/// because the exit animation still rebuilds the TextField.
class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.initialText});

  final String initialText;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  late final controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('My notes'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 1000,
        decoration: const InputDecoration(hintText: 'What did you think?'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
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
