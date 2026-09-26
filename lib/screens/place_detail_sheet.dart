import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/board_store.dart';
import '../data/photo_store.dart';
import '../data/place_store.dart';
import '../data/shared_board_store.dart';
import '../models/board.dart';
import '../models/place.dart';
import '../models/place_area.dart';
import '../models/place_rating.dart';
import '../models/shared_board.dart';
import '../theme/app_theme.dart';
import '../widgets/board_picker_sheet.dart';
import '../widgets/place_photo.dart';
import '../widgets/place_photo_actions.dart';
import '../widgets/score_stars.dart';

/// Where a [PlaceDetailSheet] was opened from. [mine] (the default) is the
/// user's own Saved place (or the auto "New finds" board) — every personal
/// control (favourite, my review, photo, area/type edit, add to board) is
/// available. [sharedBoard] is a place copy on someone else's — or the
/// user's own — shared board: those controls act on the *user's own* Saved
/// store, so they'd either be meaningless (editing a copy nobody else sees)
/// or dangerous (reading/writing the wrong person's `users/{uid}/photos`).
/// Shared-board places are always shown read-only, whatever the [role] —
/// see docs/shared-boards.md's place-detail follow-up — except the
/// member's own rating (`_SharedRatingsSection`), which lives in the
/// board's `ratings` subcollection, not in anyone's Saved store.
class PlaceDetailSource {
  const PlaceDetailSource._({this.board, this.role});

  /// The default: the place is the user's own.
  static const mine = PlaceDetailSource._();

  /// Opened from [board]'s place list, as [role] (owner/editor/viewer).
  factory PlaceDetailSource.sharedBoard(SharedBoard board, BoardRole? role) =>
      PlaceDetailSource._(board: board, role: role);

  final SharedBoard? board;
  final BoardRole? role;

  bool get isSharedBoard => board != null;
}

/// Detail card (ANALYSIS.md §4): photo header, location badge, AI description,
/// original caption, source attribution, address + hours, "Open in Google Maps"
/// deep link, and the social/board action row.
///
/// Presented as a draggable bottom sheet so it works over the map or the feed.
class PlaceDetailSheet extends StatelessWidget {
  const PlaceDetailSheet({
    super.key,
    required this.place,
    this.source = PlaceDetailSource.mine,
  });

  final Place place;

  /// See [PlaceDetailSource]. Governs whether this shows the personal edit
  /// controls or a read-only view with "Save to my places".
  final PlaceDetailSource source;

  static Future<void> show(
    BuildContext context,
    Place place, {
    PlaceDetailSource source = PlaceDetailSource.mine,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaceDetailSheet(place: place, source: source),
    );
  }

  Color _categoryColor(BuildContext context, PlaceCategory category) =>
      AppTheme.categoryColor(category, Theme.of(context).brightness);

  @override
  Widget build(BuildContext context) {
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
            // The accent (header gradient, area badge) follows the place's
            // current category, so a category-chip change recolours it
            // live. Shared-board copies never read PlaceStore (their id is
            // the owner's own place id — see PlaceDetailSource).
            body: source.isSharedBoard
                ? _sheetBody(
                    context,
                    controller,
                    _categoryColor(context, place.category),
                  )
                : ValueListenableBuilder<List<Place>>(
                    valueListenable: PlaceStore.instance.places,
                    builder: (context, _, _) => _sheetBody(
                      context,
                      controller,
                      _categoryColor(
                        context,
                        (PlaceStore.instance.byIdOrNull(place.id) ?? place)
                            .category,
                      ),
                    ),
                  ),
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
          _PhotoHeader(place: place, color: color, source: source),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AreaBadge(
                  place: place,
                  color: color,
                  editable: !source.isSharedBoard,
                ),
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
                const SizedBox(height: 8),
                _CategoryChips(place: place, editable: !source.isSharedBoard),
                const SizedBox(height: 18),
                source.isSharedBoard
                    ? _SharedActionRow(place: place)
                    : _ActionRow(place: place),
                const SizedBox(height: 20),
                _SectionLabel('About / 簡介'),
                const SizedBox(height: 6),
                Text(
                  place.descriptionEn,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 18),
                if (source.isSharedBoard)
                  _SharedRatingsSection(place: place, board: source.board!)
                else
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
  const _PhotoHeader({
    required this.place,
    required this.color,
    required this.source,
  });

  final Place place;
  final Color color;
  final PlaceDetailSource source;

  @override
  Widget build(BuildContext context) {
    // A shared-board copy shares its id with the owner's own Saved place —
    // re-reading PlaceStore/PhotoStore by that id here would leak the
    // owner's personal photo to every other member. Render the static copy
    // (photoUrls only, no photo buttons) instead of re-looking-up "current".
    if (source.isSharedBoard) return _buildHeader(context, place);
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
    final photo = source.isSharedBoard
        ? (current.photoUrls.isEmpty
              ? gradient
              : Image.network(
                  current.photoUrls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => gradient,
                ))
        : PlacePhoto(place: current, fallback: gradient);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SizedBox(height: 180, width: double.infinity, child: photo),
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
        if (!source.isSharedBoard)
          Positioned(
            right: 12,
            bottom: 12,
            child: _PhotoButtons(place: current),
          ),
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

/// "Shibuya, Tokyo" location badge (district, city — whichever are known;
/// the raw area label for older places that only have that). Live like
/// [_RestaurantTypeChip]: re-reads the place from [PlaceStore] so the
/// background area backfill or a manual edit shows up immediately. Tap to
/// correct the city/district by hand via [_AreaDialog].
class _AreaBadge extends StatelessWidget {
  const _AreaBadge({
    required this.place,
    required this.color,
    this.editable = true,
  });

  final Place place;
  final Color color;

  /// False for a shared-board place: no edit affordance, and the label
  /// comes straight from the passed [place] rather than re-reading
  /// PlaceStore (whose entry for this id, if any, is the owner's own).
  final bool editable;

  @override
  Widget build(BuildContext context) {
    if (!editable) return _badge(context, place);
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, _, _) {
        final current = PlaceStore.instance.byIdOrNull(place.id) ?? place;
        return Semantics(
          button: true,
          label: 'Area: ${_label(current)}. Tap to edit.',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _edit(context, current),
            child: ExcludeSemantics(
              child: _badge(context, current, icon: true),
            ),
          ),
        );
      },
    );
  }

  String _label(Place current) {
    final display = current.areaDisplay.isNotEmpty
        ? current.areaDisplay
        : current.areaLabel.trim();
    return display.isEmpty ? 'Add area' : display;
  }

  Widget _badge(BuildContext context, Place current, {bool icon = false}) {
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
          Flexible(
            child: Text(
              _label(current),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          if (icon) ...[
            const SizedBox(width: 2),
            Icon(Icons.edit_outlined, size: 13, color: color),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, Place current) async {
    final result = await showDialog<PlaceArea>(
      context: context,
      builder: (_) => _AreaDialog(
        city: current.city,
        district: current.district.isNotEmpty
            ? current.district
            : (current.city.isEmpty ? current.areaLabel.trim() : ''),
        countryCode: current.countryCode,
      ),
    );
    // The dialog already popped itself — no BuildContext use after this.
    if (result == null) return;
    await PlaceStore.instance.updateAreas({current.id: result});
  }
}

/// City + District editor, opened by [_AreaBadge]. Pops with the new
/// [PlaceArea] on Save (keeping the country code), `null` on Cancel. Owns
/// its controllers for the same reason as [_NotesDialog].
class _AreaDialog extends StatefulWidget {
  const _AreaDialog({
    required this.city,
    required this.district,
    required this.countryCode,
  });

  final String city;
  final String district;
  final String countryCode;

  @override
  State<_AreaDialog> createState() => _AreaDialogState();
}

class _AreaDialogState extends State<_AreaDialog> {
  late final _city = TextEditingController(text: widget.city);
  late final _district = TextEditingController(text: widget.district);

  @override
  void dispose() {
    _city.dispose();
    _district.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Area'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _city,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'City',
              hintText: 'e.g. Tokyo',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _district,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'District',
              hintText: 'e.g. Shibuya',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            PlaceArea(
              city: _city.text.trim(),
              district: _district.text.trim(),
              countryCode: widget.countryCode,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
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

/// The category chip ("🍽️ Restaurant ▾") with the restaurant sub-type chip
/// right next to it when the place is a restaurant. Re-reads the current
/// copy from [PlaceStore] (like [_RestaurantTypeChip]) so a category change
/// shows or hides the sub-type chip immediately; map pins, the feed and
/// filters follow on their own since they read [PlaceStore] too. Not
/// [editable] on a shared-board place: plain chips, no store lookups (see
/// [_AreaBadge.editable]).
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.place, this.editable = true});

  final Place place;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    if (!editable) return _chips(context, place);
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, _, _) =>
          _chips(context, PlaceStore.instance.byIdOrNull(place.id) ?? place),
    );
  }

  Widget _chips(BuildContext context, Place current) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _CategoryChip(place: current, editable: editable),
        if (current.category == PlaceCategory.restaurant)
          _RestaurantTypeChip(place: current, editable: editable),
      ],
    );
  }
}

/// "☕ Cafe ▾" chip for [Place.category]. Tapping opens [_CategoryPicker] and
/// saves via [PlaceStore.updateCategory]; read-only (no ▾, no tap) when not
/// [editable].
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.place, required this.editable});

  final Place place;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final category = place.category;
    final color = AppTheme.categoryColor(
      category,
      Theme.of(context).brightness,
    );
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(category.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            category.labelEn,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          if (editable) Icon(Icons.expand_more, size: 16, color: color),
        ],
      ),
    );
    // The emoji alone isn't an accessible label — the Semantics carries the
    // category name instead (same as the cuisine chip).
    if (!editable) {
      return Semantics(
        label: 'Category: ${category.labelEn}',
        child: ExcludeSemantics(child: chip),
      );
    }
    return Semantics(
      button: true,
      label: 'Category: ${category.labelEn}. Tap to change.',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _pickCategory(context),
        child: ExcludeSemantics(child: chip),
      ),
    );
  }

  Future<void> _pickCategory(BuildContext context) async {
    final picked = await showModalBottomSheet<PlaceCategory>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryPicker(selected: place.category),
    );
    if (picked == null) return;
    await PlaceStore.instance.updateCategory(place.id, picked);
  }
}

/// Bottom sheet list of every [PlaceCategory], opened by [_CategoryChip] —
/// same shape (and same no-controller reasoning) as [_RestaurantTypePicker].
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected});

  final PlaceCategory selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Category / 類別',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final category in PlaceCategory.values)
              ListTile(
                leading: ExcludeSemantics(
                  child: Text(
                    category.emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                title: Text(category.labelEn),
                subtitle: Text(category.labelZh),
                trailing: category == selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tappable "🍜 Ramen ▾" chip for a restaurant's cuisine sub-type
/// ([Place.effectiveRestaurantType] — the user's own pick if set, else a
/// keyword-detected guess, else "Other"). Tapping opens [_RestaurantTypePicker]
/// and saves the choice via [PlaceStore.setRestaurantType]. Re-reads the
/// current copy from the store, same as [_MyReviewSection]/[_ActionRow]'s
/// favourite toggle, so it reflects a save immediately.
class _RestaurantTypeChip extends StatelessWidget {
  const _RestaurantTypeChip({required this.place, this.editable = true});

  final Place place;

  /// False for a shared-board place: no picker, no re-reading PlaceStore
  /// (see [_AreaBadge.editable]).
  final bool editable;

  @override
  Widget build(BuildContext context) {
    if (!editable) {
      final color = AppTheme.categoryColor(
        PlaceCategory.restaurant,
        Theme.of(context).brightness,
      );
      final type = place.effectiveRestaurantType ?? RestaurantType.other;
      // The chip's emoji isn't an accessible label — same WCAG 1.4.1 note
      // as the editable branch below, just without "Tap to change".
      return Semantics(
        label: 'Cuisine: ${type.labelEn}',
        child: ExcludeSemantics(child: _chip(context, place, color)),
      );
    }
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, _, _) {
        final current = PlaceStore.instance.byIdOrNull(place.id) ?? place;
        final color = AppTheme.categoryColor(
          PlaceCategory.restaurant,
          Theme.of(context).brightness,
        );
        final type = current.effectiveRestaurantType ?? RestaurantType.other;
        return Semantics(
          button: true,
          label: 'Cuisine: ${type.labelEn}. Tap to change.',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _pickType(context, current),
            child: ExcludeSemantics(
              child: _chip(context, current, color, expandIcon: true),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(
    BuildContext context,
    Place current,
    Color color, {
    bool expandIcon = false,
  }) {
    final type = current.effectiveRestaurantType ?? RestaurantType.other;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(type.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            type.labelEn,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          if (expandIcon) Icon(Icons.expand_more, size: 16, color: color),
        ],
      ),
    );
  }

  Future<void> _pickType(BuildContext context, Place current) async {
    final picked = await showModalBottomSheet<RestaurantType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RestaurantTypePicker(
        selected: current.effectiveRestaurantType ?? RestaurantType.other,
      ),
    );
    if (picked == null) return;
    await PlaceStore.instance.setRestaurantType(current.id, picked);
  }
}

/// Bottom sheet list of every [RestaurantType], opened by [_RestaurantTypeChip].
/// Pops with the tapped type, or `null` on dismiss without a pick — a plain
/// [StatelessWidget] since it holds no controller (see the git history of
/// this file's `_NotesDialog` for why that distinction matters: never
/// dispose a controller right after `await showModalBottomSheet` returns —
/// this widget simply doesn't own one).
class _RestaurantTypePicker extends StatelessWidget {
  const _RestaurantTypePicker({required this.selected});

  final RestaurantType selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Cuisine / type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final type in RestaurantType.values)
              ListTile(
                leading: ExcludeSemantics(
                  child: Text(type.emoji, style: const TextStyle(fontSize: 20)),
                ),
                title: Text(type.labelEn),
                trailing: type == selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
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

/// [_ActionRow]'s equivalent for a shared-board place: no favourite toggle
/// and no "Add to board" (those act on the user's own Saved store, and this
/// place isn't necessarily theirs) — "Save to my places" instead, which
/// copies it in ([SharedBoardStore.saveToMyPlaces], deduped the same way as
/// the Boards tab's row action). Share stays: it's just the public link.
class _SharedActionRow extends StatelessWidget {
  const _SharedActionRow({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<List<Place>>(
            valueListenable: PlaceStore.instance.places,
            builder: (context, _, _) {
              final saved = SharedBoardStore.instance.isSaved(place);
              return Semantics(
                label: saved ? '✓ In your places' : 'Save to my places',
                child: FilledButton.icon(
                  onPressed: saved ? null : () => _save(context),
                  icon: Icon(
                    saved ? Icons.check : Icons.bookmark_add,
                    size: 18,
                  ),
                  label: Text(saved ? '✓ In your places' : 'Save to my places'),
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
        _IconAction(icon: Icons.ios_share, tooltip: 'Share', onTap: _share),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final added = await SharedBoardStore.instance.saveToMyPlaces(place);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added
              ? 'Saved “${place.name}” to your places'
              : '“${place.name}” is already in your Saved list',
        ),
      ),
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

/// "Ratings / 評分" on a shared-board place: the signed-in member's own
/// editable rating ([ScoreStars] + remark box, saved to
/// `places/{placeId}/ratings/{uid}` via [SharedBoardStore.setMyRating]),
/// then every other current member's rating, read-only, with who rated it.
///
/// The owner's score/notes baked into the shared copy (only there when
/// [SharedBoard.includeOwnerNotes] is on; see `sharedCopyOf`) stand in as
/// the owner's entry until the owner saves a real rating — shown to other
/// members only, never to the owner themself. Never reads [PlaceStore]: a
/// shared copy keeps the owner's place id, so a store lookup by id would
/// leak the owner's private fields to every member.
class _SharedRatingsSection extends StatefulWidget {
  const _SharedRatingsSection({required this.place, required this.board});

  final Place place;
  final SharedBoard board;

  @override
  State<_SharedRatingsSection> createState() => _SharedRatingsSectionState();
}

class _SharedRatingsSectionState extends State<_SharedRatingsSection> {
  // Subscribed once — a StreamBuilder given a fresh stream on every build
  // would re-subscribe (and flash empty) each time.
  late final Stream<List<PlaceRating>> _ratings = SharedBoardStore.instance
      .watchRatings(widget.board.id, widget.place.id);

  Future<void> _save(int? score, String notes) async {
    try {
      await SharedBoardStore.instance.setMyRating(
        widget.board.id,
        widget.place.id,
        score: score,
        notes: notes,
      );
    } catch (error) {
      debugPrint('PlaceDetailSheet: rating not saved: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save your rating")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SharedBoard>>(
      valueListenable: SharedBoardStore.instance.boards,
      builder: (context, _, _) {
        // The source board is a snapshot from when the sheet opened; the
        // store's copy has the current members and names.
        final board =
            SharedBoardStore.instance.byIdOrNull(widget.board.id) ??
            widget.board;
        return StreamBuilder<List<PlaceRating>>(
          stream: _ratings,
          builder: (context, snapshot) =>
              _buildRatings(context, board, snapshot.data ?? const []),
        );
      },
    );
  }

  Widget _buildRatings(
    BuildContext context,
    SharedBoard board,
    List<PlaceRating> ratings,
  ) {
    final me = SharedBoardStore.instance.uid;
    PlaceRating? mine;
    final others = <PlaceRating>[];
    for (final rating in ratings) {
      if (rating.uid == me) {
        mine = rating;
      } else if (board.members.containsKey(rating.uid)) {
        // A removed member's rating lingers (they can't delete it any
        // more) — hide it.
        others.add(rating);
      }
    }
    final ownerRated = ratings.any((r) => r.uid == board.ownerId);
    final baked = widget.place.myScore;
    final bakedNotes = widget.place.myNotes.trim();
    if (!ownerRated &&
        me != board.ownerId &&
        (baked != null || bakedNotes.isNotEmpty)) {
      others.add(
        PlaceRating(
          uid: board.ownerId,
          placeId: widget.place.id,
          displayName: board.ownerName,
          // 0 = notes only, no score (never written — display only).
          score: baked ?? 0,
          notes: bakedNotes,
        ),
      );
    }
    String nameOf(PlaceRating r) {
      final live = board.memberNames[r.uid]?.trim();
      if (live != null && live.isNotEmpty) return live;
      if (r.displayName.trim().isNotEmpty) return r.displayName.trim();
      return r.uid == board.ownerId ? board.ownerName : 'Member';
    }

    others.sort((a, b) {
      if (a.uid == board.ownerId) return -1;
      if (b.uid == board.ownerId) return 1;
      return nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase());
    });

    final scores = [
      ?mine?.score,
      for (final r in others)
        if (r.score > 0) r.score,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Ratings / 評分'),
        if (scores.length >= 2) ...[
          const SizedBox(height: 4),
          Text(
            'Avg ${_formatAverage(scores)} · ${scores.length} ratings',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Your rating',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        ScoreStars(
          value: mine?.score,
          onChanged: (score) => _save(score, mine?.notes ?? ''),
        ),
        const SizedBox(height: 10),
        _RemarkBox(
          text: mine?.notes ?? '',
          // Every rating doc needs a score (firestore.rules validRating).
          enabled: mine != null,
          disabledHint: 'Rate first to add a remark / 先評分再加備註',
          onSave: (notes) => _save(mine?.score, notes),
        ),
        const SizedBox(height: 16),
        if (others.isEmpty)
          Text(
            'No one else has rated this yet',
            style: TextStyle(
              fontSize: 14,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          )
        else
          for (final rating in others)
            _MemberRatingTile(
              rating: rating,
              name: nameOf(rating),
              isOwner: rating.uid == board.ownerId,
            ),
      ],
    );
  }

  static String _formatAverage(List<int> scores) {
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    final rounded = (avg * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }
}

/// One other member's rating, read-only: avatar (photo or initial), name,
/// an "Owner" tag for the board owner, their score and remark.
class _MemberRatingTile extends StatelessWidget {
  const _MemberRatingTile({
    required this.rating,
    required this.name,
    required this.isOwner,
  });

  final PlaceRating rating;
  final String name;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photoUrl = rating.photoUrl;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 16,
              backgroundColor: scheme.primaryContainer,
              foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
              onForegroundImageError: photoUrl == null ? null : (_, _) {},
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isOwner)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Owner',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    if (rating.score > 0)
                      ScoreBadge(
                        score: rating.score,
                        semanticsLabel: '$name rated ${rating.score} out of 10',
                      ),
                  ],
                ),
                if (rating.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    rating.notes,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
    return _RemarkBox(
      text: place.myNotes,
      onSave: (notes) => PlaceStore.instance.updateReview(
        place.id,
        score: place.myScore,
        notes: notes,
      ),
    );
  }
}

/// The remark box under a [ScoreStars] picker — "My review"'s [_MyNotes]
/// and a shared board's "Your rating". Tapping opens [_NotesDialog];
/// [onSave] gets the trimmed text on Save (nothing on Cancel). When not
/// [enabled], shows [disabledHint] and ignores taps.
class _RemarkBox extends StatelessWidget {
  const _RemarkBox({
    required this.text,
    required this.onSave,
    this.enabled = true,
    this.disabledHint,
  });

  final String text;
  final Future<void> Function(String notes) onSave;
  final bool enabled;
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = text.isEmpty;
    // Always a visible box under the stars — the old "Add notes" text button
    // was easy to miss. Tapping opens [_NotesDialog]; the sheet itself
    // ignores keyboard insets, so an inline TextField would sit under it.
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: !enabled
          ? (disabledHint ?? 'Remark')
          : empty
          ? 'Add a remark'
          : 'Edit remark',
      child: InkWell(
        onTap: enabled ? () => _editNotes(context) : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  !enabled
                      ? (disabledHint ?? '')
                      : empty
                      ? 'Add a remark… / 加備註'
                      : text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: empty || !enabled
                        ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                        : scheme.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 8),
                Icon(
                  empty ? Icons.edit_note : Icons.edit_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editNotes(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _NotesDialog(initialText: text),
    );
    // The dialog already popped itself before returning — no BuildContext
    // use after this await, so no `mounted` check is needed here.
    if (result == null) return;
    await onSave(result);
  }
}

/// Multiline notes editor, opened by [_RemarkBox]. Pops with the trimmed text
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
      title: const Text('Remark / 備註'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 1000,
        decoration: const InputDecoration(
          hintText: 'What did you think? Tips, dishes, prices…',
        ),
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
