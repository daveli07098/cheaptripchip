import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/board_store.dart';
import '../data/place_store.dart';
import '../data/shared_board_store.dart';
import '../models/board.dart';
import '../models/place.dart';
import '../models/shared_board.dart';
import '../services/auth_service.dart';
import '../services/trip_share.dart';
import '../theme/app_theme.dart';
import '../widgets/add_places_sheet.dart';
import '../widgets/export_sheet.dart';
import '../widgets/new_board_dialog.dart';
import '../widgets/sharing_sheet.dart';
import 'account_sheet.dart';
import 'place_detail_sheet.dart';

/// Boards (ANALYSIS.md §5): Board → Section → Item hierarchy, expandable.
class BoardsScreen extends StatelessWidget {
  const BoardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shared = SharedBoardStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        PlaceStore.instance.places,
        BoardStore.instance.boards,
        shared.boards,
        shared.places,
      ]),
      builder: (context, _) {
        final places = PlaceStore.instance.places.value;
        final storeBoards = BoardStore.instance.boards.value;
        final sharedBoards = shared.boards.value;
        final placesById = {for (final p in places) p.id: p};
        // Shared boards count as "referenced" too — otherwise sharing a
        // board would drop the owner's places back into "New finds".
        final autoBoard = newFindsBoard(places, [
          ...storeBoards,
          for (final board in sharedBoards) board.board,
        ]);
        final cards = <Widget>[
          if (autoBoard != null)
            _BoardCard(
              key: const ValueKey('auto'),
              board: autoBoard,
              placesById: placesById,
              permissions: BoardPermissions.auto,
            ),
          for (final board in sharedBoards)
            _BoardCard(
              key: ValueKey('shared/${board.id}'),
              board: board.board,
              placesById: shared.placesOf(board.id),
              shared: board,
              permissions: BoardPermissions.forRole(board.roleOf(shared.uid)),
            ),
          for (final board in storeBoards)
            _BoardCard(
              key: ValueKey('personal/${board.id}'),
              board: board,
              placesById: placesById,
              permissions: BoardPermissions.personal,
            ),
        ];
        if (cards.isEmpty) return const _EmptyBoardsState();
        return ListView.separated(
          // Bottom padding keeps the last board clear of the floating
          // "Add a find" button.
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => cards[i],
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
  const _BoardCard({
    super.key,
    required this.board,
    required this.placesById,
    required this.permissions,
    this.shared,
  });

  final Board board;

  /// Resolves the board's place ids: the user's Saved places for personal
  /// boards, the board's own place copies for shared ones.
  final Map<String, Place> placesById;

  /// What the user may do here — gates every edit affordance.
  final BoardPermissions permissions;

  /// Set for collaborative boards (see SharedBoardStore).
  final SharedBoard? shared;

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

enum _BoardMenuAction {
  sendCopy,
  shareBoard,
  sharing,
  addPlaces,
  rename,
  delete,
  leave,
}

class _BoardCardState extends State<_BoardCard> {
  late bool _expanded = widget.board.id == 'b1';

  /// The auto-generated "New finds" board (see [kNewFindsBoardId]) isn't a
  /// stored [Board] — it never offers rename/delete/remove-place.
  bool get _isAuto => widget.board.id == kNewFindsBoardId;

  SharedBoard? get _shared => widget.shared;
  BoardPermissions get _can => widget.permissions;

  /// "Shared · 3 people" for the owner; "Shared by Ann · View only" for
  /// everyone else.
  String? get _sharedBadge {
    final shared = _shared;
    if (shared == null) return null;
    final role = shared.roleOf(SharedBoardStore.instance.uid);
    if (role == BoardRole.owner) {
      final n = shared.memberCount;
      return 'Shared · $n ${n == 1 ? 'person' : 'people'}';
    }
    return 'Shared by ${shared.ownerName} · ${role?.label ?? ''}';
  }

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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${board.sections.length} ${board.sections.length == 1 ? 'section' : 'sections'} · ${board.itemCount} ${board.itemCount == 1 ? 'place' : 'places'}',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              if (_sharedBadge case final badge?)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.group_outlined,
                        size: 14,
                        color: AppTheme.coral,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.coral,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
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
                itemBuilder: (context) => _menuItems(context),
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
                canRemove: _can.canEditPlaces,
                canSaveCopies: _can.canSaveCopies,
                sharedBoard: _shared,
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
      case _BoardMenuAction.sendCopy:
        ExportSheet.show(context, _bundle());
      case _BoardMenuAction.shareBoard:
        await _shareBoard(context);
      case _BoardMenuAction.sharing:
        await SharingSheet.show(context, widget.board.id);
      case _BoardMenuAction.addPlaces:
        final shared = _shared;
        await AddPlacesSheet.show(
          context,
          widget.board,
          onApply: shared == null
              ? null
              : (add, remove) => SharedBoardStore.instance.updateFromSaved(
                  shared.id,
                  add: add,
                  remove: remove,
                ),
        );
      case _BoardMenuAction.rename:
        await _renameBoard(context);
      case _BoardMenuAction.delete:
        if (_shared == null) {
          await _deleteBoard(context);
        } else {
          await _deleteSharedBoard(context);
        }
      case _BoardMenuAction.leave:
        await SharingSheet.confirmLeave(context, _shared!);
    }
  }

  /// ⋮ entries by role: personal boards get Share board…, shared boards
  /// Sharing settings…/info; edit entries only where [_can] allows.
  List<PopupMenuEntry<_BoardMenuAction>> _menuItems(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    PopupMenuItem<_BoardMenuAction> item(
      _BoardMenuAction value,
      IconData icon,
      String label, {
      Color? color,
    }) {
      return PopupMenuItem(
        value: value,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color)),
        ),
      );
    }

    final shared = _shared;
    return [
      if (shared != null)
        item(
          _BoardMenuAction.sharing,
          Icons.group_outlined,
          _can.canManage ? 'Sharing settings…' : 'Sharing info',
        )
      else if (!_isAuto)
        item(_BoardMenuAction.shareBoard, Icons.person_add_alt, 'Share board…'),
      item(_BoardMenuAction.sendCopy, Icons.ios_share, 'Send a copy'),
      if (!_isAuto && _can.canEditPlaces)
        item(_BoardMenuAction.addPlaces, Icons.playlist_add, 'Add places…'),
      if (!_isAuto && _can.canManage) ...[
        item(_BoardMenuAction.rename, Icons.edit_outlined, 'Rename'),
        item(
          _BoardMenuAction.delete,
          Icons.delete_outline,
          'Delete',
          color: error,
        ),
      ],
      if (_can.canLeave)
        item(_BoardMenuAction.leave, Icons.logout, 'Leave board', color: error),
    ];
  }

  /// Personal → shared: guests are asked to sign in first; otherwise the
  /// board moves to a shared board and the sharing sheet opens.
  Future<void> _shareBoard(BuildContext context) async {
    final board = widget.board;
    if (AuthService.instance.user.value == null ||
        SharedBoardStore.instance.uid == null) {
      final signIn = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sign in to share'),
          content: const Text(
            'Shared boards live in your account, so friends can view or '
            'edit them with you.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
      if (signIn == true && context.mounted) await showAccountSheet(context);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Share “${board.name}”?'),
        content: const Text(
          'It becomes a shared board you can invite people to. Your scores '
          '& notes stay private unless you choose to include them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // This card is replaced by the shared one once the move lands — keep
    // handles that outlive it.
    final navigatorContext = Navigator.of(context).context;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final shared = await SharedBoardStore.instance.shareBoard(board);
      if (shared == null || !navigatorContext.mounted) return;
      await SharingSheet.show(navigatorContext, shared.id);
    } catch (e) {
      debugPrint('share board failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't share the board. Try again.")),
      );
    }
  }

  /// Owner deleting a shared board: gone for everyone, no undo.
  Future<void> _deleteSharedBoard(BuildContext context) async {
    final board = widget.board;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete “${board.name}” for everyone?'),
        content: const Text(
          'Everyone loses access. Your own places stay in your Saved list.',
        ),
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
    await SharedBoardStore.instance.delete(board.id);
  }

  Future<void> _renameBoard(BuildContext context) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameBoardDialog(initialName: widget.board.name),
    );
    if (newName == null) return;
    if (_shared != null) {
      await SharedBoardStore.instance.rename(widget.board.id, newName);
    } else {
      await BoardStore.instance.renameBoard(widget.board.id, newName);
    }
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
    required this.canRemove,
    required this.canSaveCopies,
    required this.sharedBoard,
  });

  /// Board and board name the section belongs to — used to call
  /// [BoardStore.removePlaceFromBoard] and to word the "Removed from"
  /// SnackBar. Unused (and rows aren't swipeable) unless [canRemove].
  final String boardId;
  final String boardName;
  final BoardSection section;
  final Map<String, Place> placesById;

  /// Rows are swipe-to-remove. False for the auto-generated "New finds"
  /// board ([kNewFindsBoardId]) — not a stored [Board] — and for viewers of
  /// a shared board.
  final bool canRemove;

  /// Rows offer "Save to my places" (shared boards, non-owners).
  final bool canSaveCopies;

  /// Set for a shared board (removals go through SharedBoardStore, and rows
  /// open [PlaceDetailSheet] in [PlaceDetailSource.sharedBoard] mode); null
  /// for a personal board.
  final SharedBoard? sharedBoard;

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
      trailing: widget.canSaveCopies
          ? IconButton(
              tooltip: 'Save to my places',
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              onPressed: () => _saveToMyPlaces(context, place),
            )
          : const Icon(Icons.chevron_right, size: 20),
      onTap: () => PlaceDetailSheet.show(
        context,
        place,
        source: widget.sharedBoard == null
            ? PlaceDetailSource.mine
            : PlaceDetailSource.sharedBoard(
                widget.sharedBoard!,
                widget.sharedBoard!.roleOf(SharedBoardStore.instance.uid),
              ),
      ),
    );
    if (!widget.canRemove) return tile;

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

  Future<void> _saveToMyPlaces(BuildContext context, Place place) async {
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

  Future<void> _removePlace(BuildContext context, Place place) async {
    // Grabbed before the store mutation optimistically rebuilds this row's
    // ancestors without it.
    final messenger = ScaffoldMessenger.of(context);
    if (widget.sharedBoard != null) {
      final removed = await SharedBoardStore.instance.removePlace(
        boardId,
        place.id,
      );
      if (removed == null) return;
      final (copy, titles) = removed;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Removed from $boardName'),
          action: SnackBarAction(
            label: 'UNDO',
            // Re-adding puts the place in one section — the first it was
            // in (it may have sat in several).
            onPressed: () => SharedBoardStore.instance.updatePlaces(
              boardId,
              newPlaces: [copy],
              sectionTitle: titles.isEmpty ? null : titles.first,
            ),
          ),
        ),
      );
      return;
    }
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
