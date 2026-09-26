import 'package:flutter/material.dart';

/// Hint for [PlaceSearchPill] — the search only matches saved places (see
/// [placeMatches]), so it says exactly that.
const String kPlaceSearchHint = 'Search saved places';

/// Full-width search pill shared by the map and the Saved tab: leading ☰
/// opens the Filters drawer (badged with the number of active filters), a
/// free-text field, a clear ✕ once there's text, and an optional [trailing]
/// (the map's account button).
class PlaceSearchPill extends StatelessWidget {
  const PlaceSearchPill({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onOpenFilters,
    this.activeFilters = 0,
    this.onSubmitted,
    this.trailing,
    this.elevation = 2,
  });

  /// Its text is the query (see [PlaceFilterController.search]).
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onOpenFilters;

  /// Chip filters on; > 0 shows a count badge on the ☰ button.
  final int activeFilters;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: elevation,
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            // IconButton/TextField already derive their a11y label from
            // `tooltip`/`hintText` — an outer `Semantics` would just add a
            // second, redundant node for screen readers to announce.
            IconButton(
              icon: Badge(
                isLabelVisible: activeFilters > 0,
                label: Text('$activeFilters'),
                child: const Icon(Icons.menu),
              ),
              tooltip: 'Filters',
              onPressed: onOpenFilters,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: onSubmitted,
                decoration: const InputDecoration(
                  hintText: kPlaceSearchHint,
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Clear search',
                  onPressed: controller.clear,
                );
              },
            ),
            if (trailing case final trailing?) ...[
              const SizedBox(width: 4),
              trailing,
            ],
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
