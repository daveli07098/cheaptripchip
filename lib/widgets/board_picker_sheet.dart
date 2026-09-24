import 'package:flutter/material.dart';

import '../data/board_store.dart';
import '../models/board.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';

/// "New finds" board id (see `kNewFindsBoardId` in boards_screen.dart) —
/// duplicated as a literal rather than imported to avoid a cycle
/// (boards_screen.dart imports place_detail_sheet.dart, which uses this
/// file). It is never actually present in [BoardStore.instance.boards] (it's
/// derived at display time in boards_screen.dart, never upserted through the
/// repository) — the filter below is defensive only.
const String _kNewFindsBoardId = 'new-finds';

/// Label for the detail sheet's "Add to board" button, driven by which
/// boards [placeId] is already saved to.
String addToBoardLabel(List<Board> containing) {
  if (containing.isEmpty) return 'Add to board';
  if (containing.length == 1) return 'In ${containing.first.name}';
  return 'In ${containing.length} boards';
}

/// "Add to board" picker: a Google-Maps-"Save to list"-style sheet listing
/// every stored board with a checkbox toggled by [BoardStore.containsPlace],
/// plus "New board…" at the bottom. Tapping a row toggles membership
/// immediately and the sheet stays open so several boards can be picked.
class BoardPickerSheet extends StatelessWidget {
  const BoardPickerSheet({super.key, required this.place});

  final Place place;

  static Future<void> show(BuildContext context, Place place) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BoardPickerSheet(place: place),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, controller) {
        // Own messenger + transparent Scaffold, same shape as
        // PlaceDetailSheet: this picker is itself the topmost modal route
        // (over the detail sheet, which stays open underneath), so a
        // SnackBar raised on the detail sheet's messenger would render
        // beneath this sheet's modal barrier and never be seen. Giving the
        // picker its own messenger/Scaffold puts "Added to <board>" /
        // "Removed from <board>" on top of the picker's own content instead.
        return ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: _PickerBody(place: place, controller: controller),
          ),
        );
      },
    );
  }
}

class _PickerBody extends StatefulWidget {
  const _PickerBody({required this.place, required this.controller});

  final Place place;
  final ScrollController controller;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  final _nameController = TextEditingController();
  bool _creatingNew = false;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _notify(String message, {SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.of(context);
    // Toggling several boards in quick succession shouldn't queue up a
    // string of 4s SnackBars — replace whatever's showing.
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: action,
      ),
    );
  }

  Future<void> _toggle(Board board, bool alreadyIn) async {
    if (alreadyIn) {
      final removedFrom = await BoardStore.instance.removePlaceFromBoard(
        boardId: board.id,
        placeId: widget.place.id,
      );
      if (removedFrom.isEmpty || !mounted) return;
      _notify(
        'Removed from ${board.name}',
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            for (final title in removedFrom) {
              await BoardStore.instance.addPlaceToBoard(
                boardId: board.id,
                placeId: widget.place.id,
                sectionTitle: title,
              );
            }
          },
        ),
      );
    } else {
      await BoardStore.instance.addPlaceToBoard(
        boardId: board.id,
        placeId: widget.place.id,
      );
      if (!mounted) return;
      _notify('Added to ${board.name}');
    }
  }

  Future<void> _createAndAdd() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      // One upsert with the section pre-filled, rather than createBoard +
      // addPlaceToBoard — the latter reads back `boards` in between and can
      // race the repository's asynchronous echo (see board_store.dart).
      final board = await BoardStore.instance.createBoard(
        name,
        sections: [
          BoardSection(
            title: widget.place.category.labelEn,
            placeIds: [widget.place.id],
          ),
        ],
      );
      if (!mounted) return;
      setState(() {
        _creatingNew = false;
        _nameController.clear();
        _busy = false;
      });
      _notify('Added to ${board.name}');
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          controller: widget.controller,
          padding: EdgeInsets.zero,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Add to board',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            ValueListenableBuilder<List<Board>>(
              valueListenable: BoardStore.instance.boards,
              builder: (context, boards, _) {
                final storedBoards = boards.where(
                  (b) => b.id != _kNewFindsBoardId,
                );
                return Column(
                  children: [
                    for (final board in storedBoards)
                      CheckboxListTile(
                        value: BoardStore.instance.containsPlace(
                          board.id,
                          widget.place.id,
                        ),
                        // onChanged carries the *new* value the tap wants;
                        // false means it was checked (in the board) and is
                        // being unchecked, i.e. a removal.
                        onChanged: (newValue) =>
                            _toggle(board, newValue == false),
                        controlAffinity: ListTileControlAffinity.trailing,
                        // The tile's own title already carries the board
                        // name for screen readers — just hide the raw emoji
                        // glyph rather than re-labelling it (WCAG 1.4.1).
                        secondary: ExcludeSemantics(
                          child: Text(
                            board.emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                        title: Text(board.name),
                        subtitle: Text(
                          '${board.itemCount} '
                          '${board.itemCount == 1 ? 'place' : 'places'}',
                        ),
                      ),
                  ],
                );
              },
            ),
            if (!_creatingNew)
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New board…'),
                enabled: !_busy,
                onTap: () => setState(() => _creatingNew = true),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        autofocus: true,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          hintText: 'Board name',
                        ),
                        onSubmitted: (_) => _createAndAdd(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _busy ? null : _createAndAdd,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.coral,
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
