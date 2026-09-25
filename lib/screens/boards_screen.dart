import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/board_store.dart';
import '../data/place_store.dart';
import '../models/board.dart';
import '../models/place.dart';
import '../services/trip_share.dart';
import '../theme/app_theme.dart';
import '../widgets/add_places_sheet.dart';
import '../widgets/export_sheet.dart';
import '../widgets/new_board_dialog.dart';
import 'place_detail_sheet.dart';

/// Boards (ANALYSIS.md §5): Board → Section → Item hierarchy, expandable.
class BoardsScreen extends StatelessWidget {
  const BoardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, places, _) {
        return ValueListenableBuilder<List<Board>>(
          valueListenable: BoardStore.instance.boards,
          builder: (context, storeBoards, _) {
            final placesById = {for (final p in places) p.id: p};
            final autoBoard = newFindsBoard(places, storeBoards);
            final boards = [?autoBoard, ...storeBoards];
            if (boards.isEmpty) return const _EmptyBoardsState();
            return ListView.separated(
              // Bottom padding keeps the last board clear of the floating
              // "Add a find" button.
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: boards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  _BoardCard(board: boards[i], placesById: placesById),
            );
          },
        );
      },
    );
  }
}

/// Shown when there are no boards (auto or user-created) and no places to
/// auto-group — i.e. nothing at all to show yet.
class _EmptyBoardsState extends StatelessWidget {
  const _EmptyBoardsState();

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      // Matches the list's own bottom padding so this stays clear of the
      // floating "Add a find" button too.
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📌', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            const Text(
              'No boards yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Save a find, then add it to a board.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => NewBoardDialog.showAndContinue(context),
              icon: const Icon(Icons.add),
              label: const Text('Create your first board'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.coral,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Id of the auto-generated "New finds" board (see [newFindsBoard]). It is
/// never backed by [BoardStore] (no repository row), so boards_screen never
/// offers rename/delete/remove-place on it — only share.
const String kNewFindsBoardId = 'new-finds';

/// Auto-generated board (title 'New finds', emoji 📌) for [places] not
/// referenced by any section in [boards], grouped one section per category.
///
/// Returns null when every place is already referenced by a board — i.e.
/// there is nothing new to surface.
Board? newFindsBoard(List<Place> places, List<Board> boards) {
  final referencedIds = <String>{
    for (final board in boards)
      for (final section in board.sections) ...section.placeIds,
  };
  final unreferenced = places.where((p) => !referencedIds.contains(p.id));
  if (unreferenced.isEmpty) return null;

  // Group by category, preserving the order categories are first encountered.
  final byCategory = <PlaceCategory, List<String>>{};
  for (final place in unreferenced) {
    byCategory.putIfAbsent(place.category, () => []).add(place.id);
  }

  return Board(
    id: kNewFindsBoardId,
    name: 'New finds',
    emoji: '📌',
    sections: [
      for (final entry in byCategory.entries)
        BoardSection(title: entry.key.labelEn, placeIds: entry.value),
    ],
  );
}

class _BoardCard extends StatefulWidget {
  const _BoardCard({required this.board, required this.placesById});

  final Board board;
  final Map<String, Place> placesById;

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

enum _BoardMenuAction { share, addPlaces, rename, delete }

class _BoardCardState extends State<_BoardCard> {
  late bool _expanded = widget.board.id == 'b1';

  /// The auto-generated "New finds" board (see [kNewFindsBoardId]) isn't a
  /// stored [Board] — it never offers rename/delete/remove-place.
  bool get _isAuto => widget.board.id == kNewFindsBoardId;

  /// The board's places in section order, skipping ids that no longer
  /// resolve against the live store (same rule as [_SectionBlock]).
  TripBundle _bundle() {
    final seen = <String>{};
    final places = <Place>[
      for (final section in widget.board.sections)
        for (final id in section.placeIds)
          if (seen.add(id) && widget.placesById[id] != null)
            widget.placesById[id]!,
    ];
    return TripBundle(title: widget.board.name, places: places);
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final placesById = widget.placesById;
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (open) => setState(() => _expanded = open),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Text(board.emoji, style: const TextStyle(fontSize: 26)),
          title: Text(
            board.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${board.sections.length} ${board.sections.length == 1 ? 'section' : 'sections'} · ${board.itemCount} ${board.itemCount == 1 ? 'place' : 'places'}',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          // A custom trailing replaces ExpansionTile's chevron. Share (and,
          // for stored boards, Rename/Delete) live in a single ⋮ menu rather
          // than separate icon buttons — three+ icons plus the emoji leading
          // and bold title would overflow a 360dp-wide phone.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<_BoardMenuAction>(
                tooltip: 'Board options',
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (action) => _handleMenuAction(context, action),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _BoardMenuAction.share,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.ios_share),
                      title: Text('Share'),
                    ),
                  ),
                  if (!_isAuto) ...[
                    const PopupMenuItem(
                      value: _BoardMenuAction.addPlaces,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.playlist_add),
                        title: Text('Add places…'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _BoardMenuAction.rename,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Rename'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _BoardMenuAction.delete,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          'Delete',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              ExcludeSemantics(
                child: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ),
            ],
          ),
          children: [
            for (final section in board.sections)
              _SectionBlock(
                boardId: board.id,
                boardName: board.name,
                section: section,
                placesById: placesById,
                isAuto: _isAuto,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    _BoardMenuAction action,
  ) async {
    switch (action) {
      case _BoardMenuAction.share:
        ExportSheet.show(context, _bundle());
      case _BoardMenuAction.addPlaces:
        await AddPlacesSheet.show(context, widget.board);
      case _BoardMenuAction.rename:
        await _renameBoard(context);
      case _BoardMenuAction.delete:
        await _deleteBoard(context);
    }
  }

  Future<void> _renameBoard(BuildContext context) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameBoardDialog(initialName: widget.board.name),
    );
    if (newName == null) return;
    await BoardStore.instance.renameBoard(widget.board.id, newName);
  }

  Future<void> _deleteBoard(BuildContext context) async {
    final board = widget.board;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete “${board.name}”?'),
        content: const Text('Places stay in your Saved list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    // Grabbed before the optimistic delete rebuilds BoardsScreen without
    // this card — `context` would no longer resolve to a mounted ancestor
    // once that happens.
    final messenger = ScaffoldMessenger.of(context);
    final removed = await BoardStore.instance.deleteBoard(board.id);
    if (removed == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted “${board.name}”'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => BoardStore.instance.restoreBoard(removed),
        ),
      ),
    );
  }
}

class _SectionBlock extends StatefulWidget {
  const _SectionBlock({
    required this.boardId,
    required this.boardName,
    required this.section,
    required this.placesById,
    required this.isAuto,
  });

  /// Board and board name the section belongs to — used to call
  /// [BoardStore.removePlaceFromBoard] and to word the "Removed from"
  /// SnackBar. Unused (and rows aren't swipeable) when [isAuto] is true.
  final String boardId;
  final String boardName;
  final BoardSection section;
  final Map<String, Place> placesById;

  /// True for the auto-generated "New finds" board ([kNewFindsBoardId]),
  /// which isn't a stored [Board] — its rows can't be removed.
  final bool isAuto;

  @override
  State<_SectionBlock> createState() => _SectionBlockState();
}

class _SectionBlockState extends State<_SectionBlock> {
  /// Rows shown per step. The rows sit in a Column inside the board card,
  /// so they are built eagerly — a My Maps import can put 500+ places in
  /// one section, which would stall the first expand if built at once.
  static const _pageSize = 100;
  int _shown = _pageSize;

  String get boardId => widget.boardId;
  String get boardName => widget.boardName;
  BoardSection get section => widget.section;
  Map<String, Place> get placesById => widget.placesById;
  bool get isAuto => widget.isAuto;

  @override
  Widget build(BuildContext context) {
    // A section place id that no longer resolves against the live store
    // (e.g. removed) is skipped rather than crashing the tile.
    final ids = section.placeIds.where(placesById.containsKey).toList();
    final hidden = ids.length - _shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '${section.title.toUpperCase()} · ${ids.length}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        for (final id in ids.take(_shown)) _itemTile(context, placesById[id]!),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              onPressed: () => setState(() => _shown += _pageSize),
              child: Text(
                'Show ${hidden > _pageSize ? _pageSize : hidden} more '
                '($hidden hidden)',
              ),
            ),
          ),
      ],
    );
  }

  Widget _itemTile(BuildContext context, Place place) {
    final color = AppTheme.categoryColor(
      place.category,
      Theme.of(context).brightness,
    );
    final tile = ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.2),
        // Emoji aren't accessible labels — expose the category via Semantics
        // and hide the raw glyph from the a11y tree (WCAG 1.4.1).
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
      subtitle: Text(
        place.areaLabel,
        style: TextStyle(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => PlaceDetailSheet.show(context, place),
    );
    if (isAuto) return tile;

    return Dismissible(
      key: ValueKey('$boardId/${section.title}/${place.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onError,
            ),
            const SizedBox(width: 8),
            Text(
              'Remove',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onError,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => _removePlace(context, place),
      // A Dismissible's swipe gesture alone isn't exposed to assistive tech
      // — pair it with an explicit custom action.
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: 'Remove from board'): () =>
              _removePlace(context, place),
        },
        child: tile,
      ),
    );
  }

  Future<void> _removePlace(BuildContext context, Place place) async {
    // Grabbed before the store mutation optimistically rebuilds this row's
    // ancestors without it.
    final messenger = ScaffoldMessenger.of(context);
    final removedFrom = await BoardStore.instance.removePlaceFromBoard(
      boardId: boardId,
      placeId: place.id,
    );
    if (removedFrom.isEmpty) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed from $boardName'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            for (final title in removedFrom) {
              BoardStore.instance.addPlaceToBoard(
                boardId: boardId,
                placeId: place.id,
                sectionTitle: title,
              );
            }
          },
        ),
      ),
    );
  }
}

/// Owns its [TextEditingController] so it is disposed only when the dialog
/// route is gone. Disposing it right after `showDialog` returned crashed: the
/// dialog's exit animation still rebuilds the TextField with it.
class _RenameBoardDialog extends StatefulWidget {
  const _RenameBoardDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameBoardDialog> createState() => _RenameBoardDialogState();
}

class _RenameBoardDialogState extends State<_RenameBoardDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename board'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
