import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/shared_board_store.dart';
import '../models/shared_board.dart';
import '../services/board_invite_link.dart';

/// Link modes in the owner's segmented control.
enum _LinkMode { off, view, edit }

/// Sharing settings for a shared board. The owner manages the invite link
/// (off / view only / can edit, copy, share, reset), members' roles, the
/// "include my scores & notes" toggle, and "Stop sharing". Everyone else
/// sees their role, the members, and "Leave board". Rebuilds live from
/// [SharedBoardStore]; closes itself if the board goes away.
class SharingSheet extends StatelessWidget {
  const SharingSheet({super.key, required this.boardId, this.store});

  final String boardId;

  /// Defaults to [SharedBoardStore.instance] (a seam for tests).
  final SharedBoardStore? store;

  static Future<void> show(BuildContext context, String boardId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SharingSheet(boardId: boardId),
    );
  }

  SharedBoardStore get _store => store ?? SharedBoardStore.instance;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SharedBoard>>(
      valueListenable: _store.boards,
      builder: (context, _, _) {
        final board = _store.byIdOrNull(boardId);
        if (board == null) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('This board is no longer shared with you.'),
            ),
          );
        }
        final role = board.roleOf(_store.uid);
        final isOwner = role == BoardRole.owner;
        final muted = Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    isOwner ? 'Share “${board.name}”' : board.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    isOwner
                        ? 'Shared · ${_people(board.memberCount)}'
                        : 'Shared by ${board.ownerName} · '
                              '${role?.label ?? 'No access'}',
                    style: TextStyle(color: muted),
                  ),
                ),
                if (isOwner) ..._ownerLinkControls(context, board, muted),
                _sectionLabel(context, 'People'),
                for (final uid in _orderedMembers(board))
                  _memberTile(context, board, uid, isOwner),
                const Divider(height: 24),
                if (isOwner)
                  ListTile(
                    leading: Icon(
                      Icons.link_off,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Stop sharing',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    subtitle: const Text(
                      'Turns it back into your own board. Others lose access.',
                    ),
                    onTap: () => _stopSharing(context, board),
                  )
                else
                  ListTile(
                    leading: Icon(
                      Icons.logout,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Leave board',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () => confirmLeave(context, board, store: _store),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _people(int n) => '$n ${n == 1 ? 'person' : 'people'}';

  /// Owner first, then everyone else by name.
  static List<String> _orderedMembers(SharedBoard board) {
    final others =
        board.members.keys.where((uid) => uid != board.ownerId).toList()..sort(
          (a, b) => (board.memberNames[a] ?? '').toLowerCase().compareTo(
            (board.memberNames[b] ?? '').toLowerCase(),
          ),
        );
    return [board.ownerId, ...others];
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  List<Widget> _ownerLinkControls(
    BuildContext context,
    SharedBoard board,
    Color muted,
  ) {
    final mode = switch (board.linkRole) {
      BoardRole.editor => _LinkMode.edit,
      BoardRole.viewer => _LinkMode.view,
      _ => _LinkMode.off,
    };
    final link = BoardInviteLink.https(board.id, board.inviteCode).toString();
    return [
      _sectionLabel(context, 'Anyone with the link'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<_LinkMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _LinkMode.off, label: Text('Off')),
              ButtonSegment(value: _LinkMode.view, label: Text('View only')),
              ButtonSegment(value: _LinkMode.edit, label: Text('Can edit')),
            ],
            selected: {mode},
            onSelectionChanged: (selection) =>
                _store.setLinkRole(board.id, switch (selection.first) {
                  _LinkMode.off => null,
                  _LinkMode.view => BoardRole.viewer,
                  _LinkMode.edit => BoardRole.editor,
                }),
          ),
        ),
      ),
      if (mode != _LinkMode.off) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'People who open the link and sign in join as '
            '“${board.linkRole!.label}”.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy link'),
                onPressed: () => _copyLink(context, link),
              ),
              TextButton.icon(
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Share link'),
                onPressed: () => _shareLink(context, board, link),
              ),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset link'),
                onPressed: () => _resetLink(context, board),
              ),
            ],
          ),
        ),
      ],
      SwitchListTile(
        title: const Text('Include my scores & notes'),
        subtitle: const Text('On the places you added'),
        value: board.includeOwnerNotes,
        onChanged: (value) => _store.setIncludeOwnerNotes(board.id, value),
      ),
    ];
  }

  Widget _memberTile(
    BuildContext context,
    SharedBoard board,
    String uid,
    bool viewerIsOwner,
  ) {
    final name = board.memberNames[uid] ?? 'Someone';
    final isMe = uid == _store.uid;
    final role = board.roleOf(uid) ?? BoardRole.viewer;
    final Widget trailing;
    if (!viewerIsOwner || role == BoardRole.owner) {
      trailing = Text(role.label);
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<BoardRole>(
            value: role,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(
                value: BoardRole.editor,
                child: Text('Can edit'),
              ),
              DropdownMenuItem(
                value: BoardRole.viewer,
                child: Text('View only'),
              ),
            ],
            onChanged: (value) {
              if (value != null) _store.setMemberRole(board.id, uid, value);
            },
          ),
          IconButton(
            tooltip: 'Remove $name',
            icon: const Icon(Icons.person_remove_outlined),
            onPressed: () => _removeMember(context, board, uid, name),
          ),
        ],
      );
    }
    return ListTile(
      leading: CircleAvatar(
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
      ),
      title: Text(isMe ? '$name (you)' : name),
      trailing: trailing,
    );
  }

  Future<void> _copyLink(BuildContext context, String link) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: link));
    messenger?.showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  Future<void> _shareLink(
    BuildContext context,
    SharedBoard board,
    String link,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Join my board “${board.name}” on CheapTripChip:\n$link',
          subject: board.name,
        ),
      );
    } catch (e) {
      debugPrint('Share failed: $e');
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet')),
      );
    }
  }

  Future<void> _resetLink(BuildContext context, SharedBoard board) async {
    final confirmed = await _confirm(
      context,
      title: 'Reset link?',
      body:
          'Links you already sent stop working. People who already joined '
          'keep their access.',
      action: 'Reset',
    );
    if (confirmed) await _store.resetLink(board.id);
  }

  Future<void> _removeMember(
    BuildContext context,
    SharedBoard board,
    String uid,
    String name,
  ) async {
    // Removing a member also resets the invite link (SharedBoardStore.
    // removeMember) so their old link can't be used to rejoin — the link is
    // only worth mentioning here when it was actually on.
    final confirmed = await _confirm(
      context,
      title: 'Remove $name?',
      body: board.linkRole == null
          ? 'They lose access to “${board.name}”.'
          : "They'll lose access and the current link stops working — "
                'share the new link with anyone else who still needs it.',
      action: 'Remove',
    );
    if (confirmed) await _store.removeMember(board.id, uid);
  }

  Future<void> _stopSharing(BuildContext context, SharedBoard board) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await _confirm(
      context,
      title: 'Stop sharing “${board.name}”?',
      body:
          'It becomes your own board again. Places others added are saved '
          'to your Saved list. Everyone else loses access.',
      action: 'Stop sharing',
    );
    if (!confirmed) return;
    navigator.pop();
    await _store.stopSharing(board.id);
    messenger?.showSnackBar(
      SnackBar(content: Text('“${board.name}” is no longer shared')),
    );
  }

  /// Confirms, then leaves [board] — closing this sheet first when called
  /// from inside it. Also used by the board card's ⋮ → "Leave board".
  static Future<void> confirmLeave(
    BuildContext context,
    SharedBoard board, {
    SharedBoardStore? store,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final isSheet = context.findAncestorWidgetOfExactType<SharingSheet>();
    final confirmed = await _confirm(
      context,
      title: 'Leave “${board.name}”?',
      body: 'You need a new invite link to come back.',
      action: 'Leave',
    );
    if (!confirmed) return;
    if (isSheet != null) navigator.pop();
    await (store ?? SharedBoardStore.instance).leave(board.id);
    messenger?.showSnackBar(SnackBar(content: Text('Left “${board.name}”')));
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
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
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }
}
