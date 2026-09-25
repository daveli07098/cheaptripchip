import 'package:flutter/material.dart';

import '../data/board_store.dart';
import '../models/board.dart';
import '../theme/app_theme.dart';
import 'add_places_sheet.dart';

/// Emoji choices offered when creating a board, paired with a short
/// Semantics label — the emoji glyph alone isn't an accessible label
/// (WCAG 1.4.1).
const Map<String, String> _kBoardEmojiChoices = {
  '📌': 'Pin',
  '🍜': 'Noodles',
  '🍣': 'Sushi',
  '☕': 'Coffee',
  '🍰': 'Dessert',
  '🍸': 'Cocktails',
  '🗼': 'Tower',
  '⛩️': 'Shrine',
  '🏯': 'Castle',
  '🏖️': 'Beach',
  '⛰️': 'Mountain',
  '🛍️': 'Shopping',
  '🏨': 'Hotel',
  '✈️': 'Flight',
  '❤️': 'Heart',
  '⭐': 'Star',
};

/// "New board" dialog: name + emoji picker → [BoardStore.createBoard].
///
/// Owns its [TextEditingController] so it is disposed only when the dialog
/// route is gone — disposing a controller right after `showDialog` returns
/// crashed elsewhere in this app (see `_RenameBoardDialog` in
/// boards_screen.dart): the dialog's exit animation still rebuilds the
/// TextField with it.
class NewBoardDialog extends StatefulWidget {
  const NewBoardDialog({super.key});

  /// Opens the dialog; if a board was created, shows a confirmation
  /// SnackBar and opens [AddPlacesSheet] for it so places can be added right
  /// away (closing that sheet skips the step, leaving an empty board).
  static Future<void> showAndContinue(BuildContext context) async {
    final board = await showDialog<Board>(
      context: context,
      builder: (_) => const NewBoardDialog(),
    );
    if (board == null || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Created “${board.name}”')));
    if (!context.mounted) return;
    await AddPlacesSheet.show(context, board);
  }

  @override
  State<NewBoardDialog> createState() => _NewBoardDialogState();
}

class _NewBoardDialogState extends State<NewBoardDialog> {
  final _controller = TextEditingController();
  String _emoji = '📌';
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canCreate => _controller.text.trim().isNotEmpty && !_busy;

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final board = await BoardStore.instance.createBoard(name, emoji: _emoji);
    if (!mounted) return;
    Navigator.pop(context, board);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New board'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Board name'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_canCreate) _create();
              },
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _kBoardEmojiChoices.entries)
                  _EmojiChoice(
                    emoji: entry.key,
                    label: entry.value,
                    selected: entry.key == _emoji,
                    onTap: _busy
                        ? null
                        : () => setState(() => _emoji = entry.key),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canCreate ? _create : null,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.coral),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class _EmojiChoice extends StatelessWidget {
  const _EmojiChoice({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? AppTheme.coral.withValues(alpha: 0.18)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? AppTheme.coral
                    : scheme.outline.withValues(alpha: 0.4),
                width: selected ? 2 : 1,
              ),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }
}
