import 'package:flutter/material.dart';

import '../models/place.dart';
import '../theme/app_theme.dart';

/// Snap fractions for [PlaceListSheet]. `kSheetHalf` matches Material 3's
/// documented default `halfExpandedRatio` (0.5); peek/full are custom to
/// this map screen.
const double kSheetPeek = 0.18;
const double kSheetHalf = 0.5;
const double kSheetFull = 0.92;

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
    this.controller,
    this.sheetController,
  });

  final List<Place> places;
  final int total;
  final String? selectedId;
  final ValueChanged<Place> onSelectPlace;
  final ValueChanged<Place> onOpenDetail;
  final PlaceListSheetController? controller;

  /// Exposed so [MapScreen] can read the sheet's current extent (via
  /// `.size`) to compute how much of the map it's covering — needed to pad
  /// pin-centering/cluster-fit calculations so results land above the sheet.
  final DraggableScrollableController? sheetController;

  @override
  State<PlaceListSheet> createState() => _PlaceListSheetState();
}

class _PlaceListSheetState extends State<PlaceListSheet> {
  // A plain (non-lazy) list of rows, so every row's GlobalKey/context exists
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
      snapSizes: const [kSheetPeek, kSheetHalf, kSheetFull],
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
          child: Column(
            children: [
              const _DragHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${widget.places.length} of ${widget.total} places',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: widget.places.isEmpty
                    ? const _EmptyState()
                    : ListView(
                        controller: scrollController,
                        padding: EdgeInsets.only(
                          bottom: 24 + MediaQuery.of(context).padding.bottom,
                        ),
                        children: [
                          for (final place in widget.places)
                            _PlaceRow(
                              key: _keyFor(place.id),
                              place: place,
                              selected: place.id == widget.selectedId,
                              onTap: () => widget.onSelectPlace(place),
                              onOpenDetail: () => widget.onOpenDetail(place),
                            ),
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
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No places in this category yet',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
