import 'package:flutter/material.dart';

import '../data/board_store.dart';
import '../data/place_search.dart';
import '../data/place_store.dart';
import '../models/board.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';

/// "Add places" sheet: every saved place with a checkbox, pre-checked for
/// ones already on [board]. Applies the diff to [BoardStore] in a single
/// write (see [BoardStore.updateBoardPlaces]) rather than one repository
/// write per toggled place — this list can hold ~1,700 saved places.
class AddPlacesSheet extends StatefulWidget {
  const AddPlacesSheet({super.key, required this.board});

  final Board board;

  static Future<void> show(BuildContext context, Board board) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddPlacesSheet(board: board),
    );
  }

  @override
  State<AddPlacesSheet> createState() => _AddPlacesSheetState();
}

class _AddPlacesSheetState extends State<AddPlacesSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _busy = false;

  /// The board's membership as of the last write (initial open, or after
  /// applying a batch) — [_selected] is diffed against this baseline to
  /// compute what changed. Computed once (not per build) so toggling a
  /// checkbox among ~1,700 rows doesn't redo the scan.
  late Set<String> _baseline = _membershipOf(widget.board);
  late final Set<String> _selected = Set.of(_baseline);

  static Set<String> _membershipOf(Board board) => {
    for (final section in board.sections) ...section.placeIds,
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final added = _selected.difference(_baseline);
    final removed = _baseline.difference(_selected);
    if (added.isEmpty && removed.isEmpty) return;
    setState(() => _busy = true);
    await BoardStore.instance.updateBoardPlaces(
      boardId: widget.board.id,
      add: added,
      remove: removed,
    );
    if (!mounted) return;
    setState(() {
      _baseline = Set.of(_selected);
      _busy = false;
    });
    // Own messenger (see build below) — shows above this modal sheet, which
    // stays open so more places can be picked.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${added.length} places to “${widget.board.name}”'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        // Own messenger + transparent Scaffold, same shape as
        // BoardPickerSheet: this sheet is itself the topmost modal route, so
        // a SnackBar raised on an outer messenger would render beneath this
        // sheet's modal barrier and never be seen.
        return ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Add places to “${widget.board.name}”',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search saved places',
                          isDense: true,
                        ),
                        onChanged: (q) => setState(() => _query = q),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ValueListenableBuilder<List<Place>>(
                        valueListenable: PlaceStore.instance.places,
                        builder: (context, places, _) {
                          final filtered = _query.trim().isEmpty
                              ? places
                              : places
                                    .where((p) => placeMatches(p, _query))
                                    .toList();
                          if (filtered.isEmpty) {
                            return const Center(child: Text('No places match'));
                          }
                          return ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.only(bottom: 8),
                            itemCount: filtered.length,
                            itemBuilder: (context, i) =>
                                _placeRow(context, filtered[i]),
                          );
                        },
                      ),
                    ),
                    _bottomBar(context),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placeRow(BuildContext context, Place place) {
    final color = AppTheme.categoryColor(
      place.category,
      Theme.of(context).brightness,
    );
    return CheckboxListTile(
      value: _selected.contains(place.id),
      onChanged: _busy
          ? null
          : (value) => setState(() {
              if (value == true) {
                _selected.add(place.id);
              } else {
                _selected.remove(place.id);
              }
            }),
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.2),
        // Emoji aren't accessible labels — expose the category via
        // Semantics and hide the raw glyph from the a11y tree (WCAG 1.4.1).
        child: Semantics(
          label: place.category.labelEn,
          child: ExcludeSemantics(
            child: Text(
              place.category.emoji,
              style: const TextStyle(fontSize: 15, height: 1),
            ),
          ),
        ),
      ),
      title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: place.areaLabel.isEmpty
          ? null
          : Text(place.areaLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final added = _selected.difference(_baseline);
    final removed = _baseline.difference(_selected);
    final hasChanges = added.isNotEmpty || removed.isNotEmpty;
    // Unchecking an already-saved place is a removal too — once any is
    // pending, the button covers the whole batch rather than only additions.
    final label = removed.isNotEmpty
        ? 'Save changes'
        : 'Add ${added.length} ${added.length == 1 ? 'place' : 'places'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: FilledButton(
        onPressed: hasChanges && !_busy ? _apply : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.coral,
          minimumSize: const Size(double.infinity, 48),
        ),
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}
