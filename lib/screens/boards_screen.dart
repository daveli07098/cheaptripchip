import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/board_store.dart';
import '../data/map_filter.dart';
import '../data/place_store.dart';
import '../data/shared_board_store.dart';
import '../models/board.dart';
import '../models/place.dart';
import '../models/shared_board.dart';
import '../services/trip_share.dart';
import '../theme/app_theme.dart';
import '../utils/plural.dart';
import '../widgets/add_places_sheet.dart';
import '../widgets/board_picker_sheet.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/delete_find.dart';
import '../widgets/export_sheet.dart';
import '../widgets/new_board_dialog.dart';
import '../widgets/sharing_sheet.dart';
import '../widgets/show_place_on_map.dart';
import '../widgets/sign_in_gate.dart';
import 'place_detail_sheet.dart';

export '../models/board.dart' show kNewFindsBoardId;

/// Boards (ANALYSIS.md §5): Board → Section → Item hierarchy, expandable.
class BoardsScreen extends StatelessWidget {
  const BoardsScreen({
    super.key,
    this.onShowOnMap,
    this.onImportTripLink,
    this.onImportMyMaps,
  });

  /// "Show on map" on a board card, with the board's [BoardRef.key]. The
  /// action is hidden when null.
  final ValueChanged<String>? onShowOnMap;

  /// The empty state's "Import a trip" entries — the same imports as the
  /// app bar's Import menu (owned by the shell). The button is hidden when
  /// both are null.
  final VoidCallback? onImportTripLink;
  final VoidCallback? onImportMyMaps;

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
        // A lone board starts expanded — nothing else to scan past; with
        // several, all start collapsed so the list reads as an overview.
        final cardCount =
            (autoBoard == null ? 0 : 1) +
            sharedBoards.length +
            storeBoards.length;
        final expandLone = cardCount == 1;
        final cards = <Widget>[
          if (autoBoard != null)
            _BoardCard(
              key: const ValueKey('auto'),
              board: autoBoard,
              placesById: placesById,
              permissions: BoardPermissions.auto,
              initiallyExpanded: expandLone,
              onShowOnMap: onShowOnMap,
            ),
          for (final board in sharedBoards)
            _BoardCard(
              key: ValueKey('shared/${board.id}'),
              board: board.board,
              placesById: shared.placesOf(board.id),
              shared: board,
              permissions: BoardPermissions.forRole(board.roleOf(shared.uid)),
              initiallyExpanded: expandLone,
              onShowOnMap: onShowOnMap,
            ),
          for (final board in storeBoards)
            _BoardCard(
              key: ValueKey('personal/${board.id}'),
              board: board,
              placesById: placesById,
              permissions: BoardPermissions.personal,
              initiallyExpanded: expandLone,
              onShowOnMap: onShowOnMap,
            ),
        ];
        if (cards.isEmpty) {
          return _EmptyBoardsState(
            onImportTripLink: onImportTripLink,
            onImportMyMaps: onImportMyMaps,
          );
        }
        return ListView.separated(
          // Bottom padding keeps the last board clear of the floating
          // "Add a find" button.
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: cards.length,
          // Match cards to their old elements by key: without this a sliver
          // list reuses state by index, so whenever the list shifts (the
          // "New finds" card appearing/disappearing after a remove, move or
          // undo, a board deleted/restored) every card below would get a
          // fresh State — collapsing it and resetting its sections.
          findItemIndexCallback: (key) {
            final index = cards.indexWhere((card) => card.key == key);
            return index < 0 ? null : index;
          },
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
  const _EmptyBoardsState({this.onImportTripLink, this.onImportMyMaps});

  /// See [BoardsScreen.onImportTripLink] / [BoardsScreen.onImportMyMaps].
  final VoidCallback? onImportTripLink;
  final VoidCallback? onImportMyMaps;

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
            // Wraps onto two lines on a narrow phone.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => NewBoardDialog.showAndContinue(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Create your first board'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.coral,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                if (onImportTripLink != null || onImportMyMaps != null)
                  _importButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "Import a trip": straight to the one source when only one is wired,
  /// else a menu of both (same entries as the app bar's Import menu).
  Widget _importButton() {
    final sources = [
      if (onImportTripLink case final onTap?)
        (Icons.link, 'From a shared trip link', onTap),
      if (onImportMyMaps case final onTap?)
        (Icons.map_outlined, 'From Google My Maps', onTap),
    ];
    Widget button(VoidCallback onPressed) => OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.download_outlined),
      label: const Text('Import a trip'),
    );
    if (sources.length == 1) return button(sources.single.$3);
    return MenuAnchor(
      menuChildren: [
        for (final (icon, label, onTap) in sources)
          MenuItemButton(
            leadingIcon: Icon(icon),
            onPressed: onTap,
            child: Text(label),
          ),
      ],
      builder: (context, controller, _) => button(
        () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

// [kNewFindsBoardId] (in models/board.dart) is the auto-generated "New
// finds" board's id (see [newFindsBoard]). It is never backed by
// [BoardStore] (no repository row), so boards_screen never offers
// rename/delete/remove-place on it — only share and show on map.

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
    this.initiallyExpanded = false,
    this.onShowOnMap,
  });

  final Board board;

  /// Open on first build (see [BoardsScreen]: a lone board starts open).
  final bool initiallyExpanded;

  /// Resolves the board's place ids: the user's Saved places for personal
  /// boards, the board's own place copies for shared ones.
  final Map<String, Place> placesById;

  /// What the user may do here — gates every edit affordance.
  final BoardPermissions permissions;

  /// Set for collaborative boards (see SharedBoardStore).
  final SharedBoard? shared;

  /// See [BoardsScreen.onShowOnMap].
  final ValueChanged<String>? onShowOnMap;

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

enum _BoardMenuAction {
  showOnMap,
  sendCopy,
  shareBoard,
  sharing,
  addPlaces,
  rename,
  delete,
  leave,
}

class _BoardCardState extends State<_BoardCard> {
  late bool _expanded = widget.initiallyExpanded;

  /// The auto-generated "New finds" board (see [kNewFindsBoardId]) isn't a
  /// stored [Board] — it never offers rename/delete/remove-place.
  bool get _isAuto => widget.board.id == kNewFindsBoardId;

  SharedBoard? get _shared => widget.shared;

  /// This board's key in the map's board filter (see [BoardRef.keyFor]).
  String get _mapKey =>
      BoardRef.keyFor(widget.board.id, shared: widget.shared != null);

  void _showOnMap() => widget.onShowOnMap?.call(_mapKey);
  BoardPermissions get _can => widget.permissions;

  /// "Shared · 3 people" for the owner; "Shared by Ann · View only" for
  /// everyone else.
  String? get _sharedBadge {
    final shared = _shared;
    if (shared == null) return null;
    final role = shared.roleOf(SharedBoardStore.instance.uid);
    if (role == BoardRole.owner) {
      final n = shared.memberCount;
      return 'Shared · ${plural(n, 'person', 'people')}';
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
                '${plural(board.sections.length, 'section')} · '
                '${plural(board.itemCount, 'place')}',
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
          // and bold title would overflow a 360dp-wide phone. "Show on map"
          // is the one extra icon (also in the ⋮ menu); the title ellipsizes.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onShowOnMap != null)
                IconButton(
                  tooltip: 'Show on map',
                  icon: const Icon(Icons.map_outlined, size: 20),
                  onPressed: _showOnMap,
                ),
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
                key: ValueKey('${board.id}/${section.title}'),
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
      case _BoardMenuAction.showOnMap:
        _showOnMap();
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

  /// ⋮ entries by role, in three groups split by dividers:
  /// - View: Show on map, Add places…
  /// - Share: the live board (Share board… for a personal board, Sharing
  ///   settings…/info once shared) and Send a copy (a one-time snapshot).
  ///   Subtitles spell out the difference.
  /// - Manage: Rename, Delete / Leave board.
  /// Edit entries only appear where [_can] allows; empty groups (and their
  /// divider) are dropped.
  List<PopupMenuEntry<_BoardMenuAction>> _menuItems(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    PopupMenuItem<_BoardMenuAction> item(
      _BoardMenuAction value,
      IconData icon,
      String label, {
      String? subtitle,
      Color? color,
    }) {
      return PopupMenuItem(
        value: value,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color)),
          subtitle: subtitle == null ? null : Text(subtitle),
        ),
      );
    }

    final shared = _shared;
    final groups = <List<PopupMenuEntry<_BoardMenuAction>>>[
      [
        if (widget.onShowOnMap != null)
          item(_BoardMenuAction.showOnMap, Icons.map_outlined, 'Show on map'),
        if (!_isAuto && _can.canEditPlaces)
          item(_BoardMenuAction.addPlaces, Icons.playlist_add, 'Add places…'),
      ],
      [
        if (shared != null)
          item(
            _BoardMenuAction.sharing,
            Icons.group_outlined,
            _can.canManage ? 'Sharing settings…' : 'Sharing info',
            subtitle: _can.canManage
                ? 'Invite link, people & roles'
                : 'Who is on this board',
          )
        else if (!_isAuto)
          item(
            _BoardMenuAction.shareBoard,
            Icons.person_add_alt,
            'Share board…',
            subtitle: 'Plan together — stays in sync',
          ),
        item(
          _BoardMenuAction.sendCopy,
          Icons.ios_share,
          'Send a copy',
          subtitle: 'One-time snapshot — link or file',
        ),
      ],
      [
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
          item(
            _BoardMenuAction.leave,
            Icons.logout,
            'Leave board',
            color: error,
          ),
      ],
    ];
    final entries = <PopupMenuEntry<_BoardMenuAction>>[];
    for (final group in groups) {
      if (group.isEmpty) continue;
      if (entries.isNotEmpty) entries.add(const PopupMenuDivider());
      entries.addAll(group);
    }
    return entries;
  }

  /// Personal → shared: guests are asked to sign in first; otherwise the
  /// board moves to a shared board and the sharing sheet opens.
  Future<void> _shareBoard(BuildContext context) async {
    final board = widget.board;
    final signedIn = await ensureSignedInForSharing(
      context,
      title: 'Sign in to share',
      message:
          'Shared boards live in your account, so friends can view or '
          'edit them with you.',
    );
    if (!signedIn || !context.mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Share “${board.name}”?',
      body:
          'It becomes a shared board you can invite people to. Your scores '
          '& notes stay private unless you choose to include them.',
      action: 'Share',
      destructive: false,
    );
    if (!confirmed || !context.mounted) return;
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
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete “${board.name}” for everyone?',
      body: 'Everyone loses access. Your own places stay in your Saved list.',
      action: 'Delete',
    );
    if (!confirmed) return;
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
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete “${board.name}”?',
      body: 'Places stay in your Saved list.',
      action: 'Delete',
    );
    if (!confirmed || !context.mounted) return;
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

enum _RowAction { showOnMap, move, saveCopy, remove, deleteFind }

class _SectionBlock extends StatefulWidget {
  const _SectionBlock({
    super.key,
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
  /// board ([kNewFindsBoardId]) — not a stored [Board]; its rows swipe to
  /// delete the find instead — and for viewers of a shared board.
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

  /// Each section (category) collapses independently; starts expanded.
  bool _expanded = true;

  /// Rows collapsing out ahead of a menu-driven move/remove (a swipe has
  /// Dismissible's own animation) — the store update lands once the row has
  /// shrunk away, so the rows below slide up instead of jumping.
  final Set<String> _leaving = {};
  static const _leaveDuration = Duration(milliseconds: 220);

  /// Personal-board rows (not the auto board, not shared) get Move in the
  /// ⋮ menu, long-press move and open the place page with a Move action.
  bool get _isPersonal => widget.canRemove && widget.sharedBoard == null;

  /// Rows of the auto "New finds" board: not on any board, so there is
  /// nothing to remove them from — their swipe and ⋮ delete the find itself.
  bool get _isNewFinds => boardId == kNewFindsBoardId;

  /// Rows with a ⋮ menu and a swipe action.
  bool get _hasRowActions => widget.canRemove || _isNewFinds;

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
        Semantics(
          button: true,
          expanded: _expanded,
          label: '${section.title}, ${plural(ids.length, 'place')}',
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Expanded(
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
                    AnimatedRotation(
                      turns: _expanded ? 0 : -0.25,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        size: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          for (final id in ids.take(_shown))
            KeyedSubtree(
              key: ValueKey('row/$id'),
              child: _leaving.contains(id)
                  ? _CollapseOut(
                      duration: _leaveDuration,
                      child: _itemTile(context, placesById[id]!),
                    )
                  : _itemTile(context, placesById[id]!),
            ),
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
      // Editable rows (personal boards, shared-board owners and editors)
      // and "New finds" rows get a ⋮ menu so removal/deletion isn't
      // swipe-only; view-only shared rows
      // keep the one-tap "Save to my places".
      trailing: _hasRowActions
          ? _rowMenu(context, place)
          : widget.canSaveCopies
          ? IconButton(
              tooltip: 'Save to my places',
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              onPressed: () => _saveToMyPlaces(context, place),
            )
          : const Icon(Icons.chevron_right, size: 20),
      onLongPress: _isPersonal ? () => _movePlace(context, place) : null,
      onTap: () => PlaceDetailSheet.show(
        context,
        place,
        source: widget.sharedBoard != null
            ? PlaceDetailSource.sharedBoard(
                widget.sharedBoard!,
                widget.sharedBoard!.roleOf(SharedBoardStore.instance.uid),
              )
            : _isPersonal
            ? PlaceDetailSource.personalBoard(boardId)
            : PlaceDetailSource.mine,
      ),
    );
    if (!_hasRowActions) return tile;

    // Board rows: swipe = remove from this board. "New finds" rows: swipe =
    // delete the find (with UNDO).
    final swipeLabel = _isNewFinds ? 'Delete' : 'Remove';
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
              swipeLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onError,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => _isNewFinds
          ? _deleteFind(context, place)
          : _removePlace(context, place),
      // A Dismissible's swipe gesture alone isn't exposed to assistive tech
      // — pair it with an explicit custom action.
      child: Semantics(
        customSemanticsActions: {
          if (_isNewFinds)
            CustomSemanticsAction(label: 'Delete find'): () =>
                _deleteFind(context, place, animate: true)
          else
            CustomSemanticsAction(label: 'Remove from board'): () =>
                _removePlace(context, place, animate: true),
          if (_isPersonal)
            CustomSemanticsAction(label: 'Move to another board'): () =>
                _movePlace(context, place),
        },
        child: tile,
      ),
    );
  }

  /// ⋮ on an editable row: Show on map, Move (personal boards), Save to my
  /// places (shared-board editors) and Remove from board — or, on "New
  /// finds" rows, Show on map and Delete find.
  Widget _rowMenu(BuildContext context, Place place) {
    PopupMenuItem<_RowAction> item(
      _RowAction value,
      IconData icon,
      String label,
    ) {
      return PopupMenuItem(
        value: value,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(label),
        ),
      );
    }

    final showOnMap = ShowPlaceOnMap.maybeOf(context);
    return PopupMenuButton<_RowAction>(
      tooltip: 'Place options',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (action) => switch (action) {
        _RowAction.showOnMap => showOnMap?.call(place),
        _RowAction.move => _movePlace(context, place),
        _RowAction.saveCopy => _saveToMyPlaces(context, place),
        _RowAction.remove => _removePlace(context, place, animate: true),
        _RowAction.deleteFind => _deleteFind(context, place, animate: true),
      },
      itemBuilder: (context) => [
        if (showOnMap != null)
          item(_RowAction.showOnMap, Icons.map_outlined, 'Show on map'),
        if (_isPersonal)
          item(
            _RowAction.move,
            Icons.drive_file_move_outline,
            'Move to board…',
          ),
        if (widget.canSaveCopies)
          item(
            _RowAction.saveCopy,
            Icons.bookmark_add_outlined,
            'Save to my places',
          ),
        if (widget.canRemove)
          item(
            _RowAction.remove,
            Icons.remove_circle_outline,
            'Remove from board',
          ),
        if (_isNewFinds)
          item(_RowAction.deleteFind, Icons.delete_outline, 'Delete find'),
      ],
    );
  }

  /// "New finds" rows: delete the find itself (it's on no board to remove
  /// it from), with "Deleted “Name”" + UNDO on the Boards tab's messenger.
  /// [animate] as for [_removePlace].
  Future<void> _deleteFind(
    BuildContext context,
    Place place, {
    bool animate = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    Future<bool> delete() => deleteFindWithUndo(messenger, place);
    await (animate ? _collapseThen(place.id, delete) : delete());
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

  /// Plays the row's collapse-out, then runs [mutate] (the store update
  /// that drops the row). The store call is started before clearing
  /// [_leaving] so both land in the same frame — no flash of the row.
  /// Runs [mutate] even if this block is disposed mid-animation.
  Future<T> _collapseThen<T>(
    String placeId,
    Future<T> Function() mutate,
  ) async {
    if (!mounted) return mutate();
    setState(() => _leaving.add(placeId));
    // The collapse starts on the next frame; allow a couple of frames of
    // slack so the row is fully gone before the store drops it.
    await Future<void>.delayed(
      _leaveDuration + const Duration(milliseconds: 32),
    );
    final result = mutate();
    if (mounted) setState(() => _leaving.remove(placeId));
    return result;
  }

  /// Personal boards only: pick a target in the move picker (the current
  /// board shown as "Current"), collapse the row, then move it in one store
  /// update. "Moved to …" + UNDO goes on the Boards tab's messenger, which
  /// is visible again once the picker has closed.
  Future<void> _movePlace(BuildContext context, Place place) async {
    final messenger = ScaffoldMessenger.of(context);
    final target = await BoardPickerSheet.pickMoveTarget(
      context,
      place,
      fromBoardId: boardId,
    );
    if (target == null) return;
    final move = await _collapseThen(
      place.id,
      () => BoardStore.instance.movePlace(
        placeId: place.id,
        fromBoardId: boardId,
        toBoardId: target.id,
      ),
    );
    if (move != null) showMovedSnackBar(messenger, move);
  }

  /// [animate]: collapse the row first (menu / a11y action); a swipe has
  /// already animated it via Dismissible.
  Future<void> _removePlace(
    BuildContext context,
    Place place, {
    bool animate = false,
  }) async {
    // Grabbed before the store mutation optimistically rebuilds this row's
    // ancestors without it.
    final messenger = ScaffoldMessenger.of(context);
    if (widget.sharedBoard != null) {
      Future<(Place, List<String>)?> remove() =>
          SharedBoardStore.instance.removePlace(boardId, place.id);
      final removed = animate
          ? await _collapseThen(place.id, remove)
          : await remove();
      if (removed == null) return;
      final (copy, titles) = removed;
      messenger.removeCurrentSnackBar();
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
    await removeFromBoardWithUndo(
      messenger,
      boardId: boardId,
      placeId: place.id,
      run: animate ? (remove) => _collapseThen(place.id, remove) : null,
    );
  }
}

/// Shrinks and fades [child] to nothing over [duration] as soon as it is
/// built — a row leaving its section.
class _CollapseOut extends StatefulWidget {
  const _CollapseOut({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  State<_CollapseOut> createState() => _CollapseOutState();
}

class _CollapseOutState extends State<_CollapseOut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  )..reverse();

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizeTransition(
        sizeFactor: _curve,
        axisAlignment: -1,
        child: FadeTransition(opacity: _curve, child: widget.child),
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

  /// Same rule as [NewBoardDialog]: a name is required (trimmed).
  String get _name => _controller.text.trim();

  void _save() {
    if (_name.isNotEmpty) Navigator.pop(context, _name);
  }

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
        // Same cap as NewBoardDialog.
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Board name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.isEmpty ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
