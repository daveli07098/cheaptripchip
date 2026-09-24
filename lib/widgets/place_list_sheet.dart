import 'package:flutter/material.dart';

import '../models/place.dart';
import '../theme/app_theme.dart';
import 'score_stars.dart';

/// Snap fractions for [PlaceListSheet]. `kSheetHalf` matches Material 3's
/// documented default `halfExpandedRatio` (0.5); peek/full are custom to
/// this map screen.
const double kSheetPeek = 0.22;
const double kSheetHalf = 0.5;
const double kSheetFull = 0.92;

/// Every snap stop, including two in-between detents. With only
/// peek/half/full, any release between them animated the sheet a long way
/// from where the finger let go — smooth, but it felt like the sheet
/// "leapt". Closer stops keep it near the release point.
const List<double> kSheetSnapSizes = [
  kSheetPeek,
  0.36,
  kSheetHalf,
  0.72,
  kSheetFull,
];

/// Lets [MapScreen] drive [PlaceListSheet]'s internal list — specifically,
/// scroll a given place's row into view when its map pin is tapped — without
/// the sheet needing to expose its `State` publicly.
class PlaceListSheetController {
  _PlaceListSheetState? _state;

  void _attach(_PlaceListSheetState state) => _state = state;
  void _detach(_PlaceListSheetState state) {
    if (_state == state) _state = null;
  }

  /// Scrolls the row for [placeId] into view, if currently rendered. Only
  /// moves the list — never the map — matching "pin tap syncs list, list
  /// tap syncs map" (never both ways at once, which would fight the user's
  /// own panning).
  void scrollToPlace(String placeId) => _state?._scrollToPlace(placeId);
}

/// Persistent (non-modal) bottom sheet listing the visible/filtered places,
/// with peek/half/full drag-snap states over the map.
///
/// Tapping a row calls [onSelectPlace] (the map pans/zooms to that place);
/// tapping a row's chevron calls [onOpenDetail] (opens the full
/// [PlaceDetailSheet]). Selection highlighting is driven by [selectedId],
/// which [MapScreen] also sets when a map pin is tapped.
class PlaceListSheet extends StatefulWidget {
  const PlaceListSheet({
    super.key,
    required this.places,
    required this.total,
    required this.selectedId,
    required this.onSelectPlace,
    required this.onOpenDetail,
    required this.onAddFind,
    this.controller,
    this.sheetController,
  });

  final List<Place> places;
  final int total;
  final String? selectedId;
  final ValueChanged<Place> onSelectPlace;
  final ValueChanged<Place> onOpenDetail;

  /// Invoked by the header's "Add a find" button (moved here from the map's
  /// FAB so it stays reachable regardless of the sheet's drag extent).
  final VoidCallback onAddFind;
  final PlaceListSheetController? controller;

  /// Exposed so [MapScreen] can read the sheet's current extent (via
  /// `.size`) to compute how much of the map it's covering — needed to pad
  /// pin-centering/cluster-fit calculations so results land above the sheet.
  final DraggableScrollableController? sheetController;

  @override
  State<PlaceListSheet> createState() => _PlaceListSheetState();
}

class _PlaceListSheetState extends State<PlaceListSheet> {
  // A plain (non-lazy) list of rows — built eagerly into a
  // `SliverChildListDelegate`, so every row's GlobalKey/context exists
  // regardless of the sheet's current extent — the mock dataset is small
  // enough that this is cheap, and it's what makes `Scrollable.ensureVisible`
  // reliable even while the sheet is collapsed to its "peek" state.
  final Map<String, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant PlaceListSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _rowKeys.putIfAbsent(id, () => GlobalKey());

  void _scrollToPlace(String placeId) {
    final rowContext = _rowKeys[placeId]?.currentContext;
    if (rowContext == null) return;
    Scrollable.ensureVisible(
      rowContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      controller: widget.sheetController,
      initialChildSize: kSheetPeek,
      minChildSize: kSheetPeek,
      maxChildSize: kSheetFull,
      snap: true,
      snapSizes: kSheetSnapSizes,
      // Fixed, short settle time; the default is derived from fling
      // velocity, so slow releases crept to the snap point.
      snapAnimationDuration: const Duration(milliseconds: 220),
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          // A single `CustomScrollView` (rather than a Column of a static
          // header + an inner ListView) so dragging anywhere — handle,
          // header, or rows — moves the same scroll controller the sheet is
          // watching for its snap gestures. A header-only inner Column left
          // the handle/header undraggable (only the inner ListView was
          // attached to `scrollController`).
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const _DragHandle(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${widget.places.length} of ${widget.total} places',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: widget.onAddFind,
                            icon: const Icon(Icons.add_link, size: 18),
                            label: const Text('Add a find'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.places.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(filtered: widget.total > 0),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: 24 + MediaQuery.of(context).padding.bottom,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      for (final place in widget.places)
                        _PlaceRow(
                          key: _keyFor(place.id),
                          place: place,
                          selected: place.id == widget.selectedId,
                          onTap: () => widget.onSelectPlace(place),
                          onOpenDetail: () => widget.onOpenDetail(place),
                        ),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    // >=48dp touch target around a slim visual pill, matching Material's
    // minimum recommended tap-target size.
    return SizedBox(
      height: 48,
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});

  /// True when the store has places but the active category filter hides
  /// them all — the copy must not claim the user has "no finds".
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final title = filtered ? 'Nothing in this category' : 'No finds yet';
    final body = filtered
        ? 'Pick another category, or All.'
        : 'Tap Add a find to save your first place.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact local row — intentionally NOT `PlaceCard` (owned by a concurrent
/// task); this is a smaller, list-tuned rendering of a [Place].
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    super.key,
    required this.place,
    required this.selected,
    required this.onTap,
    required this.onOpenDetail,
  });

  final Place place;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = AppTheme.categoryColor(place.category, brightness);
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Semantics(
                label: place.category.labelEn,
                child: ExcludeSemantics(
                  child: Text(
                    place.category.emoji,
                    style: const TextStyle(fontSize: 18, height: 1),
                  ),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    place.hasRating
                        ? '${place.areaLabel} · ★ ${place.rating!.toStringAsFixed(1)}'
                        : place.areaLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (place.myScore != null) ...[
              ScoreBadge(score: place.myScore!),
              const SizedBox(width: 4),
            ],
            IconButton(
              onPressed: onOpenDetail,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'View details',
            ),
          ],
        ),
      ),
    );
  }
}
