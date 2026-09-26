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
import '../models/place_note.dart';
import '../models/place_rating.dart';
import '../models/shared_board.dart';
import '../theme/app_theme.dart';
import '../widgets/board_picker_sheet.dart';
import '../widgets/place_photo.dart';
import '../widgets/place_photo_actions.dart';
import '../widgets/score_stars.dart';
import '../widgets/user_avatar.dart';

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
  const PlaceDetailSource._({this.board, this.role, this.personalBoardId});

  /// The default: the place is the user's own.
  static const mine = PlaceDetailSource._();

  /// The user's own place, opened from their personal board
  /// [personalBoardId] — same as [mine], plus a "Move to another board"
  /// action.
  factory PlaceDetailSource.personalBoard(String boardId) =>
      PlaceDetailSource._(personalBoardId: boardId);

  /// Opened from [board]'s place list, as [role] (owner/editor/viewer).
  factory PlaceDetailSource.sharedBoard(SharedBoard board, BoardRole? role) =>
      PlaceDetailSource._(board: board, role: role);

  final SharedBoard? board;
  final BoardRole? role;

  /// Set when opened from one of the user's personal boards.
  final String? personalBoardId;

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
    // Start decoding the header photo now, so it's (ideally) cached by the
    // time the sheet's first frame builds instead of popping in mid-slide.
    precacheHeader(context, place, source: source);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaceDetailSheet(place: place, source: source),
    );
  }

  /// Warms the [ImageCache] with exactly the provider (same decode width)
  /// the sheet's photo header will ask for. Callers that know a sheet is
  /// likely next (a pin's preview card) can call it earlier than [show].
  static Future<void> precacheHeader(
    BuildContext context,
    Place place, {
    PlaceDetailSource source = PlaceDetailSource.mine,
  }) {
    final cacheWidth = PlacePhoto.headerCacheWidth(context);
    if (source.isSharedBoard) {
      // Mirrors _PhotoHeader: shared copies never read PhotoStore.
      if (place.photoUrls.isEmpty) return Future.value();
      return PlacePhoto.precacheUrl(
        context,
        place.photoUrls.first,
        cacheWidth: cacheWidth,
      );
    }
    final current = PlaceStore.instance.byIdOrNull(place.id) ?? place;
    return PlacePhoto.precache(context, current, cacheWidth: cacheWidth);
  }

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
            // live — but only the widgets that show store-backed fields
            // listen to PlaceStore (each via _LivePlace, re-reading the
            // current place itself), so an unrelated store flush (e.g. the
            // area backfill) doesn't rebuild the whole sheet. Shared-board copies never read PlaceStore (their
            // id is the owner's own place id — see PlaceDetailSource).
            body: _sheetBody(context, controller),
          ),
        );
      },
    );
  }

  Widget _sheetBody(BuildContext context, ScrollController controller) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        controller: controller,
        padding: EdgeInsets.zero,
        children: [
          _PhotoHeader(place: place, source: source),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AreaBadge(place: place, editable: !source.isSharedBoard),
                const SizedBox(height: 12),
                Text(
                  place.name,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (place.award case final award?) ...[
                  const SizedBox(height: 8),
                  _Pill(
                    color: AppTheme.scoreGold,
                    icon: Icons.emoji_events,
                    label: award,
                  ),
                ],
                const SizedBox(height: 8),
                _CategoryChips(place: place, editable: !source.isSharedBoard),
                const SizedBox(height: 18),
                _ActionRow(
                  place: place,
                  shared: source.isSharedBoard,
                  fromBoardId: source.personalBoardId,
                ),
                const SizedBox(height: 20),
                _SectionLabel('About / 簡介'),
                const SizedBox(height: 6),
                Text(
                  place.descriptionEn,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
                // Everything from here down sits at or below the fold at
                // the sheet's initial size — built one frame later so the
                // opening frame (mid slide-in) only lays out what's seen.
                _AfterFirstFrame(
                  builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 18),
                      if (source.isSharedBoard)
                        _SharedRatingsSection(
                          place: place,
                          board: source.board!,
                        )
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
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
          ),
        ],
      ),
    );
  }
}

/// Builds [builder]'s subtree one frame after it's first inserted (an empty
/// box until then), so an opening sheet's first frame skips below-the-fold
/// content. Rebuilds normally afterwards.
class _AfterFirstFrame extends StatefulWidget {
  const _AfterFirstFrame({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_AfterFirstFrame> createState() => _AfterFirstFrameState();
}

class _AfterFirstFrameState extends State<_AfterFirstFrame> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.builder(context) : const SizedBox.shrink();
}

class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader({required this.place, required this.source});

  final Place place;
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
    return _LivePlace(place: place, builder: _buildHeader);
  }

  Widget _buildHeader(BuildContext context, Place current) {
    // Preference: the user's own photo, then the first source photo, then
    // the category-colour gradient with the emoji.
    final color = AppTheme.categoryColor(
      current.category,
      Theme.of(context).brightness,
    );
    // Same decode width as PlaceDetailSheet.precacheHeader, so a warmed
    // photo is a cache hit and paints in the sheet's first frame.
    final cacheWidth = PlacePhoto.headerCacheWidth(context);
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
              : PlacePhoto.network(
                  current.photoUrls.first,
                  fallback: gradient,
                  cacheWidth: cacheWidth,
                ))
        : PlacePhoto(
            place: current,
            fallback: gradient,
            cacheWidth: cacheWidth,
          );
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
            child: _PhotoButton(place: current),
          ),
      ],
    );
  }
}

/// "Add photo" / "Change photo" over the header's bottom-right corner. Add,
/// change and remove all live in the one [showPlacePhotoActions] sheet it
/// opens — there's deliberately no separate trash button here.
class _PhotoButton extends StatelessWidget {
  const _PhotoButton({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: PhotoStore.instance.photoFor(place.id),
      builder: (context, bytes, _) {
        return FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.55),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: () => showPlacePhotoActions(context, place),
          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
          label: Text(bytes != null ? 'Change photo' : 'Add photo'),
        );
      },
    );
  }
}

/// "Shibuya, Tokyo" location badge (district, city — whichever are known;
/// the raw area label for older places that only have that). Live via
/// [_LivePlace] so the background area backfill or a manual edit shows up
/// immediately. Tap to correct the city/district by hand via [_AreaDialog].
class _AreaBadge extends StatelessWidget {
  const _AreaBadge({required this.place, this.editable = true});

  final Place place;

  /// False for a shared-board place: no edit affordance, and the label
  /// comes straight from the passed [place] rather than re-reading
  /// PlaceStore (whose entry for this id, if any, is the owner's own).
  final bool editable;

  @override
  Widget build(BuildContext context) {
    if (!editable) return _badge(context, place);
    return _LivePlace(
      place: place,
      builder: (context, current) =>
          _badge(context, current, onTap: () => _edit(context, current)),
    );
  }

  String _label(Place current) {
    final display = current.areaDisplay.isNotEmpty
        ? current.areaDisplay
        : current.areaLabel.trim();
    return display.isEmpty ? 'Add area' : display;
  }

  Widget _badge(BuildContext context, Place current, {VoidCallback? onTap}) {
    final label = _label(current);
    return _Pill(
      // Follows the current category, like the header gradient.
      color: AppTheme.categoryColor(
        current.category,
        Theme.of(context).brightness,
      ),
      icon: Icons.place,
      label: label,
      trailingIcon: onTap == null ? null : Icons.edit_outlined,
      semanticsLabel: onTap == null ? null : 'Area: $label. Tap to edit.',
      onTap: onTap,
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
/// its controllers for the same reason as [_TextDialog].
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

/// The rounded, category-tinted chip shared by the area badge, the award,
/// and the category / cuisine chips: an emoji or icon, a label, and an
/// optional trailing icon (▾ / ✎) when it's tappable.
///
/// With [semanticsLabel] the pill is one screen-reader node carrying that
/// label (the raw emoji/text are excluded — emoji aren't accessible
/// labels); with [onTap] it's also a button.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.color,
    required this.label,
    this.emoji,
    this.icon,
    this.trailingIcon,
    this.semanticsLabel,
    this.onTap,
  });

  final Color color;
  final String label;
  final String? emoji;
  final IconData? icon;
  final IconData? trailingIcon;
  final String? semanticsLabel;
  final VoidCallback? onTap;

  static const _radius = 20.0;

  @override
  Widget build(BuildContext context) {
    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji case final emoji?)
            Text(emoji, style: const TextStyle(fontSize: 14))
          else if (icon case final icon?)
            Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          if (trailingIcon case final trailing?) ...[
            const SizedBox(width: 2),
            Icon(trailing, size: 15, color: color),
          ],
        ],
      ),
    );
    if (onTap != null) {
      pill = InkWell(
        borderRadius: BorderRadius.circular(_radius),
        onTap: onTap,
        child: pill,
      );
    }
    if (semanticsLabel == null) return pill;
    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      child: ExcludeSemantics(child: pill),
    );
  }
}

/// The category chip ("🍽️ Restaurant ▾") with the restaurant sub-type chip
/// right next to it when the place is a restaurant. Live via [_LivePlace]
/// so a category change shows or hides the sub-type chip immediately — the
/// one store subscription for both chips; map pins, the feed and filters
/// follow on their own since they read [PlaceStore] too. Not [editable] on
/// a shared-board place: plain chips, no store lookups (see
/// [_AreaBadge.editable]).
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.place, this.editable = true});

  final Place place;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    if (!editable) return _chips(context, place);
    return _LivePlace(place: place, builder: _chips);
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

/// "☕ Cafe ▾" chip for [Place.category]. Tapping opens an
/// [_EmojiListPicker] and saves via [PlaceStore.updateCategory]; read-only
/// (no ▾, no tap) when not [editable].
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.place, required this.editable});

  final Place place;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final category = place.category;
    // The emoji alone isn't an accessible label — the Semantics carries the
    // category name instead (same as the cuisine chip).
    return _Pill(
      color: AppTheme.categoryColor(category, Theme.of(context).brightness),
      emoji: category.emoji,
      label: category.labelEn,
      trailingIcon: editable ? Icons.expand_more : null,
      semanticsLabel: editable
          ? 'Category: ${category.labelEn}. Tap to change.'
          : 'Category: ${category.labelEn}',
      onTap: editable ? () => _pickCategory(context) : null,
    );
  }

  Future<void> _pickCategory(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await _pickFromList<PlaceCategory>(
      context,
      title: 'Category / 類別',
      values: PlaceCategory.values,
      selected: place.category,
      emojiOf: (c) => c.emoji,
      labelEnOf: (c) => c.labelEn,
      labelZhOf: (c) => c.labelZh,
    );
    if (picked == null) return;
    await _saveOrWarn(
      messenger,
      () => PlaceStore.instance.updateCategory(place.id, picked),
    );
  }
}

/// "🍜 Ramen ▾" chip for a restaurant's cuisine sub-type
/// ([Place.effectiveRestaurantType] — the user's own pick if set, else a
/// keyword-detected guess, else "Other"). Tapping opens an
/// [_EmojiListPicker] and saves the choice via [PlaceStore.setRestaurantType].
/// Stateless over the [place] it's given: [_CategoryChips] already rebuilds
/// it with the current copy after every store change.
class _RestaurantTypeChip extends StatelessWidget {
  const _RestaurantTypeChip({required this.place, this.editable = true});

  final Place place;

  /// False for a shared-board place: no picker (see [_AreaBadge.editable]).
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final type = place.effectiveRestaurantType ?? RestaurantType.other;
    // The chip's emoji isn't an accessible label (WCAG 1.4.1) — the
    // Semantics label names the cuisine instead.
    return _Pill(
      color: AppTheme.categoryColor(
        PlaceCategory.restaurant,
        Theme.of(context).brightness,
      ),
      emoji: type.emoji,
      label: type.labelEn,
      trailingIcon: editable ? Icons.expand_more : null,
      semanticsLabel: editable
          ? 'Cuisine: ${type.labelEn}. Tap to change.'
          : 'Cuisine: ${type.labelEn}',
      onTap: editable ? () => _pickType(context, type) : null,
    );
  }

  Future<void> _pickType(BuildContext context, RestaurantType current) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await _pickFromList<RestaurantType>(
      context,
      title: 'Cuisine / type',
      values: RestaurantType.values,
      selected: current,
      emojiOf: (t) => t.emoji,
      labelEnOf: (t) => t.labelEn,
      labelZhOf: (t) => t.labelZh,
    );
    if (picked == null) return;
    await _saveOrWarn(
      messenger,
      () => PlaceStore.instance.setRestaurantType(place.id, picked),
    );
  }
}

/// Opens an [_EmojiListPicker] over [values]; resolves to the tapped value,
/// or `null` when dismissed without a pick.
Future<T?> _pickFromList<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T selected,
  required String Function(T value) emojiOf,
  required String Function(T value) labelEnOf,
  required String Function(T value) labelZhOf,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _EmojiListPicker<T>(
      title: title,
      values: values,
      selected: selected,
      emojiOf: emojiOf,
      labelEnOf: labelEnOf,
      labelZhOf: labelZhOf,
    ),
  );
}

/// Bottom sheet list of emoji-tagged choices (every [PlaceCategory] or
/// [RestaurantType]) with English + Chinese labels and a check on the
/// current [selected] one. Pops with the tapped value — a plain
/// [StatelessWidget] since it holds no controller (never dispose a
/// controller right after `await showModalBottomSheet` returns — this
/// widget simply doesn't own one; see [_TextDialog]).
class _EmojiListPicker<T> extends StatelessWidget {
  const _EmojiListPicker({
    required this.title,
    required this.values,
    required this.selected,
    required this.emojiOf,
    required this.labelEnOf,
    required this.labelZhOf,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) emojiOf;
  final String Function(T value) labelEnOf;
  final String Function(T value) labelZhOf;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final value in values)
              ListTile(
                // The title/subtitle name the choice; the emoji is decor.
                leading: ExcludeSemantics(
                  child: Text(
                    emojiOf(value),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                title: Text(labelEnOf(value)),
                subtitle: Text(labelZhOf(value)),
                trailing: value == selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
  }
}

/// Text for the share sheet: the name, "District, City" when either is
/// known ([Place.areaDisplay] — never the extractor's "Unknown"
/// placeholder or a raw "City, Country" region), then the Maps link.
@visibleForTesting
String placeShareText(Place place) {
  final area = place.areaDisplay;
  final title = area.isEmpty ? place.name : '${place.name} — $area';
  return '$title\n${place.googleMapsUrl}';
}

Future<void> _sharePlace(Place place) async {
  try {
    await SharePlus.instance.share(ShareParams(text: placeShareText(place)));
  } catch (e) {
    debugPrint('Share failed: $e');
  }
}

/// Runs a [PlaceStore] write started from this sheet. The store has
/// already reverted its optimistic change when the write fails; this tells
/// the user, on [messenger] (grab it before any `await`, so a dialog that
/// has since closed doesn't matter).
Future<void> _saveOrWarn(
  ScaffoldMessengerState messenger,
  Future<void> Function() write,
) async {
  try {
    await write();
  } catch (error) {
    debugPrint('PlaceDetailSheet: not saved: $error');
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text("Couldn't save — try again")),
      );
  }
}

/// Rebuilds [builder] with the current copy of [place] from [PlaceStore]
/// after every store change (the passed [place] once it's gone) — the
/// `place` a widget was built with goes stale the moment an edit saves.
/// Only for the user's own places: never wrap a shared-board copy, whose id
/// is the owner's own place id (see [PlaceDetailSource]).
class _LivePlace extends StatelessWidget {
  const _LivePlace({required this.place, required this.builder});

  final Place place;
  final Widget Function(BuildContext context, Place current) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, _, _) =>
          builder(context, PlaceStore.instance.byIdOrNull(place.id) ?? place),
    );
  }
}

/// The primary button + icon actions under the title. For the user's own
/// place ([shared] false): "Add to board", the favourite toggle, "Move to
/// another board" (when opened from a personal board it's still on) and
/// Share. For a shared-board place: "Save to my places" instead — no
/// favourite/board/move, since those act on the user's own Saved store and
/// this place isn't necessarily theirs — which copies it in
/// ([SharedBoardStore.saveToMyPlaces], deduped the same way as the Boards
/// tab's row action). Share stays in both: it's just the public link.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.place, this.shared = false, this.fromBoardId})
    : assert(!shared || fromBoardId == null);

  final Place place;
  final bool shared;

  /// Personal board the sheet was opened from (see
  /// [PlaceDetailSource.personalBoard]); enables "Move to another board"
  /// while the place is still on it.
  final String? fromBoardId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: shared ? _saveButton() : _boardButton()),
        const SizedBox(width: 10),
        if (!shared)
          _LivePlace(
            place: place,
            // IconButton.isSelected only drives Semantics(selected: ...),
            // not toggled state — wrap explicitly so screen readers
            // announce this as a toggle button, not a selection.
            builder: (context, current) => Semantics(
              toggled: current.isFavorite,
              child: _IconAction(
                icon: current.isFavorite
                    ? Icons.favorite
                    : Icons.favorite_border,
                tooltip: current.isFavorite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                isSelected: current.isFavorite,
                onTap: () => _saveOrWarn(
                  ScaffoldMessenger.of(context),
                  () => PlaceStore.instance.toggleFavorite(place.id),
                ),
              ),
            ),
          ),
        if (fromBoardId case final boardId?)
          ValueListenableBuilder<List<Board>>(
            valueListenable: BoardStore.instance.boards,
            builder: (context, _, _) =>
                BoardStore.instance.containsPlace(boardId, place.id)
                ? _IconAction(
                    icon: Icons.drive_file_move_outline,
                    tooltip: 'Move to another board',
                    onTap: () => _move(context, boardId),
                  )
                : const SizedBox.shrink(),
          ),
        _IconAction(
          icon: Icons.ios_share,
          tooltip: 'Share',
          onTap: () => _sharePlace(place),
        ),
      ],
    );
  }

  Widget _boardButton() {
    return ValueListenableBuilder<List<Board>>(
      valueListenable: BoardStore.instance.boards,
      builder: (context, _, _) {
        final containing = BoardStore.instance.boardsContaining(place.id);
        return _PrimaryAction(
          label: addToBoardLabel(containing),
          icon: containing.isEmpty ? Icons.bookmark_add : Icons.check,
          onPressed: () => BoardPickerSheet.show(context, place),
        );
      },
    );
  }

  Widget _saveButton() {
    // Listens to the whole list, not a by-id lookup — isSaved dedupes by
    // content, and a shared copy's id is the owner's (see _LivePlace).
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, _, _) {
        final saved = SharedBoardStore.instance.isSaved(place);
        return _PrimaryAction(
          // The check icon already says "done" — no "✓" in the text too.
          label: saved ? 'In your places' : 'Save to my places',
          icon: saved ? Icons.check : Icons.bookmark_add,
          onPressed: saved ? null : () => _save(context),
        );
      },
    );
  }

  /// Move picker over this sheet; once it closes, the move lands and
  /// "Moved to …" shows on this sheet's own messenger (topmost again).
  Future<void> _move(BuildContext context, String boardId) async {
    final messenger = ScaffoldMessenger.of(context);
    final target = await BoardPickerSheet.pickMoveTarget(
      context,
      place,
      fromBoardId: boardId,
    );
    if (target == null) return;
    final move = await BoardStore.instance.movePlace(
      placeId: place.id,
      fromBoardId: boardId,
      toBoardId: target.id,
    );
    if (move != null) showMovedSnackBar(messenger, move);
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
}

/// The coral full-width button leading [_ActionRow].
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.coral,
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
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
        _SubLabel('Your rating'),
        const SizedBox(height: 4),
        _ScoreRow(
          value: mine?.score,
          onChanged: (score) => _save(score, mine?.notes ?? ''),
        ),
        const SizedBox(height: 10),
        _RemarkBox(
          text: mine?.notes ?? '',
          title: 'Remark / 備註',
          placeholder: 'Add a remark… / 加備註',
          noun: 'remark',
          hint: 'What did you think? Tips, dishes, prices…',
          // Every rating doc needs a score (firestore.rules validRating).
          enabled: mine != null,
          disabledHint: 'Rate first / 先評分',
          disabledSemantics: 'Rate with the stars above to add a remark',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(photoUrl: rating.photoUrl, name: name, radius: 16),
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

/// "My review" section: a [_ScoreRow] (saves immediately on every change),
/// then two labelled note areas — "Summary", the single remark box
/// ([_RemarkBox]), and "Visit notes", the dated log ([_VisitNotes]).
///
/// Live via [_LivePlace] — the `place` this widget is built with goes stale
/// the moment a review is saved.
class _MyReviewSection extends StatelessWidget {
  const _MyReviewSection({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return _LivePlace(
      place: place,
      builder: (context, current) {
        final messenger = ScaffoldMessenger.of(context);
        Future<void> saveReview({int? score, required String notes}) =>
            _saveOrWarn(
              messenger,
              () => PlaceStore.instance.updateReview(
                current.id,
                score: score,
                notes: notes,
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('My review / 我的評價'),
            const SizedBox(height: 8),
            _ScoreRow(
              value: current.myScore,
              onChanged: (score) =>
                  saveReview(score: score, notes: current.myNotes),
            ),
            const SizedBox(height: 12),
            _SubLabel('Summary / 總結'),
            const SizedBox(height: 6),
            _RemarkBox(
              text: current.myNotes,
              title: 'Summary / 總結',
              placeholder: 'Add a summary… / 加總結',
              noun: 'summary',
              hint: 'Overall: what did you think? Tips, dishes, prices…',
              onSave: (notes) =>
                  saveReview(score: current.myScore, notes: notes),
            ),
            const SizedBox(height: 16),
            _SubLabel('Visit notes / 到訪筆記'),
            _VisitNotes(place: current),
          ],
        );
      },
    );
  }
}

/// [ScoreStars] plus, once a score is set, a small "Clear" button — tapping
/// the current half-star also clears it, but that's not discoverable.
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    // A Wrap, not a Row: five 48dp stars + the "n/10" label already fill a
    // narrow phone, so "Clear" drops below rather than overflowing.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ScoreStars(value: value, onChanged: onChanged),
        if (value != null)
          TextButton(
            onPressed: () => onChanged(null),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Clear', semanticsLabel: 'Clear score'),
          ),
      ],
    );
  }
}

/// Dated "visit notes" under the Summary box — a running log the user can
/// keep adding to (e.g. "2nd visit: …"), newest first. Only ever built by
/// [_MyReviewSection], which itself is never built in shared-board mode
/// (see `_sheetBody`) — so this needs no `editable` flag of its own.
class _VisitNotes extends StatelessWidget {
  const _VisitNotes({required this.place});

  final Place place;

  static const _addLabel = 'Add a visit note / 加到訪筆記';

  @override
  Widget build(BuildContext context) {
    final notes = [...place.extraNotes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final note in notes) ...[
          const SizedBox(height: 8),
          _VisitNoteTile(place: place, note: note),
        ],
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => _add(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(48, 48),
            alignment: Alignment.centerLeft,
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(_addLabel),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_TextResult>(
      context: context,
      builder: (_) => const _TextDialog(
        title: _addLabel,
        hint: 'e.g. "2nd visit: tried the…"',
      ),
    );
    // The dialog already popped itself — no BuildContext use after this.
    if (result == null) return;
    await _saveOrWarn(
      messenger,
      () => PlaceStore.instance.addNote(place.id, result.text),
    );
  }
}

/// One entry in [_VisitNotes]: date + text, tap to edit (or delete, via
/// [_TextDialog]'s Delete action), swipe to delete directly — both paths
/// raise an UNDO snackbar on this sheet's own messenger.
class _VisitNoteTile extends StatelessWidget {
  const _VisitNoteTile({required this.place, required this.note});

  final Place place;
  final PlaceNote note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => _delete(ScaffoldMessenger.of(context)),
      child: Semantics(
        button: true,
        label:
            'Visit note from ${_formatDate(note.createdAt)}: ${note.text}. '
            'Tap to edit.',
        child: InkWell(
          onTap: () => _edit(context),
          borderRadius: BorderRadius.circular(14),
          child: ExcludeSemantics(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(note.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    note.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
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

  Future<void> _edit(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_TextResult>(
      context: context,
      builder: (_) => _TextDialog(
        title: 'Edit visit note / 編輯到訪筆記',
        hint: 'e.g. "2nd visit: tried the…"',
        initialText: note.text,
        showDelete: true,
      ),
    );
    // The dialog already popped itself — no BuildContext use after this,
    // only the messenger grabbed before the await (same as _ActionRow._move).
    if (result == null) return;
    if (result.delete) {
      await _delete(messenger);
      return;
    }
    await _saveOrWarn(
      messenger,
      () => PlaceStore.instance.editNote(place.id, note.id, result.text),
    );
  }

  Future<void> _delete(ScaffoldMessengerState messenger) async {
    var deleted = false;
    await _saveOrWarn(messenger, () async {
      deleted = await PlaceStore.instance.deleteNote(place.id, note.id) != null;
    });
    if (!deleted) return;
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Note deleted'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => _saveOrWarn(
            messenger,
            () => PlaceStore.instance.restoreNote(place.id, note),
          ),
        ),
      ),
    );
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatDate(DateTime createdAt) {
    final local = createdAt.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }
}

/// The note box under a score picker — "My review"'s Summary and a shared
/// board's "Your rating" remark. Tapping opens a [_TextDialog] titled
/// [title]; [onSave] gets the trimmed text on Save (nothing on Cancel).
/// When not [enabled], shows [disabledHint] (pointing up at the stars) and
/// ignores taps.
class _RemarkBox extends StatelessWidget {
  const _RemarkBox({
    required this.text,
    required this.onSave,
    required this.title,
    required this.placeholder,
    required this.noun,
    required this.hint,
    this.enabled = true,
    this.disabledHint,
    this.disabledSemantics,
  });

  final String text;
  final Future<void> Function(String notes) onSave;

  /// Dialog title, e.g. "Summary / 總結".
  final String title;

  /// Shown in the box while [text] is empty.
  final String placeholder;

  /// Screen-reader noun: "Add a [noun]" / "Edit [noun]".
  final String noun;

  /// The dialog's text-field hint.
  final String hint;
  final bool enabled;
  final String? disabledHint;
  final String? disabledSemantics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = text.isEmpty;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.6);
    // Always a visible box under the stars — the old "Add notes" text button
    // was easy to miss. Tapping opens [_TextDialog]; the sheet itself
    // ignores keyboard insets, so an inline TextField would sit under it.
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: !enabled
          ? (disabledSemantics ?? disabledHint ?? noun)
          : empty
          ? 'Add a $noun'
          : 'Edit $noun',
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
              if (!enabled) ...[
                // Nudge: the stars right above are what unlocks this box.
                Icon(Icons.arrow_upward, size: 18, color: muted),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  !enabled
                      ? (disabledHint ?? '')
                      : empty
                      ? placeholder
                      : text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: empty || !enabled
                        ? muted
                        : scheme.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 8),
                Icon(
                  empty ? Icons.edit_note : Icons.edit_outlined,
                  size: 18,
                  color: muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editNotes(BuildContext context) async {
    final result = await showDialog<_TextResult>(
      context: context,
      builder: (_) => _TextDialog(title: title, hint: hint, initialText: text),
    );
    // The dialog already popped itself before returning — no BuildContext
    // use after this await, so no `mounted` check is needed here.
    if (result == null) return;
    await onSave(result.text);
  }
}

/// Pop value for [_TextDialog]: [text] (trimmed) on Save, or [delete] when
/// the Delete action was tapped. Cancel/dismiss pops `null` instead.
class _TextResult {
  const _TextResult.save(this.text) : delete = false;
  const _TextResult.delete() : text = '', delete = true;

  final String text;
  final bool delete;
}

/// Multiline text editor dialog — the Summary / remark box and the visit
/// notes. Pops a [_TextResult] on Save (or Delete, when [showDelete]), or
/// `null` on Cancel/dismiss; the caller decides what to persist.
///
/// Owns its controller: disposing it as soon as `showDialog` returned
/// crashed, because the exit animation still rebuilds the TextField.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.hint,
    this.initialText = '',
    this.showDelete = false,
  });

  final String title;
  final String hint;
  final String initialText;
  final bool showDelete;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 1000,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        if (widget.showDelete)
          TextButton(
            onPressed: () => Navigator.pop(context, const _TextResult.delete()),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _TextResult.save(controller.text.trim())),
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

/// Small heading inside a section ("Summary", "Visit notes", "Your
/// rating") — sentence case, unlike [_SectionLabel]'s all caps.
class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
