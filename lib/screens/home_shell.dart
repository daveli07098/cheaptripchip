import 'dart:async';
import 'dart:io' show File;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../data/place_store.dart';
import '../services/board_invite_link.dart';
import '../services/import_service.dart';
import '../services/my_maps_import.dart';
import '../services/place_extractor.dart';
import '../services/trip_share.dart';
import '../theme/app_theme.dart';
import '../theme/theme_toggle_button.dart';
import '../widgets/account_button.dart';
import '../widgets/board_invite_flow.dart';
import '../widgets/export_sheet.dart';
import '../widgets/import_sheet.dart';
import '../widgets/my_maps_import_sheet.dart';
import '../widgets/new_board_dialog.dart';
import 'boards_screen.dart';
import 'feed_screen.dart';
import 'map_screen.dart';
import 'place_detail_sheet.dart';

/// Entries of the Boards tab's Import menu.
enum _ImportSource { tripLink, myMaps }

/// App shell with the Map ⇄ Saved ⇄ Boards triad (ANALYSIS.md §§3,5,6).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  StreamSubscription<Uri>? _linkSub;

  /// Guards against the same import arriving twice (receive_sharing_intent
  /// and app_links both see Android VIEW intents) and stacked prompts.
  String? _lastImportKey;
  DateTime? _lastImportAt;
  bool _importInProgress = false;

  /// Same duplicate-delivery guard for shared-board invite links.
  String? _lastInviteKey;
  DateTime? _lastInviteAt;

  static const _titles = ['Explore', 'Saved', 'Boards'];

  bool get _shareIntakeSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_shareIntakeSupported) {
      _initShareIntake();
      _initAppLinks();
    }
  }

  /// `cheaptripchip://import?...` links (see [TripShare.toAppLink]) and
  /// shared-board invites (`https://…/b/{id}?c=…` App Links and
  /// `cheaptripchip://board/{id}?c=…`, see [BoardInviteLink]). The
  /// app_links stream emits the cold-start link too, so there is no separate
  /// getInitialLink() call — that would prompt twice. Mobile only.
  void _initAppLinks() {
    try {
      _linkSub = AppLinks().uriLinkStream.listen((uri) {
        final invite = BoardInviteLink.parse(uri);
        if (invite != null) {
          _openInvite(invite);
          return;
        }
        final bundle = TripShare.fromAppLink(uri);
        if (bundle != null) _promptImport(bundle, key: uri.toString());
      }, onError: (Object e) => debugPrint('app link error: $e'));
    } catch (e) {
      // Native plugin not available (e.g. test harness) — links are optional.
      debugPrint('app links unavailable: $e');
    }
  }

  /// Share-sheet intake (ANALYSIS.md §1): a reel/post shared into the app opens
  /// the "Add a find" sheet pre-filled with the link. Mobile only.
  void _initShareIntake() {
    try {
      // While the app is running.
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        _handleShared,
        onError: (Object e) => debugPrint('share intake error: $e'),
      );
      // Cold-start: app launched from a share.
      ReceiveSharingIntent.instance
          .getInitialMedia()
          .then((files) {
            _handleShared(files);
            ReceiveSharingIntent.instance.reset();
          })
          .catchError((Object e) {
            // Block body (not `=>`) so this returns `null`, not `void` — the
            // onError callback must return `FutureOr<Null>`.
            debugPrint('share intake init error: $e');
          });
    } catch (e) {
      // Native plugin not available (e.g. test harness) — share intake is optional.
      debugPrint('share intake unavailable: $e');
    }
  }

  Future<void> _handleShared(List<SharedMediaFile> files) async {
    if (files.isEmpty || !mounted) return;
    // For text/URL shares the content arrives in `path`.
    final shared = files
        .map((f) => f.path)
        .where((p) => p.trim().isNotEmpty)
        .join('\n');
    if (shared.isEmpty) return;

    // A shared-board invite link joins the board rather than importing.
    final invite = BoardInviteLink.fromText(shared);
    if (invite != null) {
      _openInvite(invite);
      return;
    }

    // A shared trip (app link in text, or a .cheaptrip.json file) imports
    // directly instead of going through Gemini extraction.
    final bundle =
        TripShare.fromText(shared) ?? await _bundleFromSharedFiles(files);
    if (!mounted) return;
    if (bundle != null) {
      _promptImport(bundle, key: shared);
      return;
    }
    // A shared Google My Maps link imports the whole map. Only the URL form
    // counts here (not a bare id), so ordinary shares never land in it.
    final mid = shared.contains('/maps/d/') ? parseMyMapsId(shared) : null;
    if (mid != null) {
      _promptMyMapsImport(mid, key: shared);
    } else {
      _openAddSheet(initialText: shared);
    }
  }

  Future<TripBundle?> _bundleFromSharedFiles(
    List<SharedMediaFile> files,
  ) async {
    if (kIsWeb) return null;
    for (final file in files) {
      final isJson =
          file.path.toLowerCase().endsWith('.json') ||
          file.mimeType == 'application/json';
      if (!isJson) continue;
      try {
        final bundle = TripShare.fromFileJson(
          await File(file.path).readAsString(),
        );
        if (bundle != null) return bundle;
      } catch (e) {
        debugPrint('shared file unreadable: $e');
      }
    }
    return null;
  }

  /// Joins the board behind [invite] (signing in first if needed), ignoring
  /// a duplicate delivery of the same link within a few seconds —
  /// receive_sharing_intent and app_links can both see one VIEW intent.
  Future<void> _openInvite(BoardInvite invite) async {
    if (!mounted) return;
    final key = '${invite.boardId}?${invite.code}';
    final now = DateTime.now();
    if (key == _lastInviteKey &&
        _lastInviteAt != null &&
        now.difference(_lastInviteAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastInviteKey = key;
    _lastInviteAt = now;
    await openBoardInvite(
      context,
      invite,
      onShowBoards: () {
        if (mounted) setState(() => _index = 2);
      },
    );
  }

  /// Shows the import preview for [bundle]; on confirm switches to Boards and
  /// reports what was added. [key] identifies the source so a duplicate
  /// delivery of the same link within a few seconds is ignored.
  Future<void> _promptImport(TripBundle bundle, {String? key}) {
    return _runImport(
      key: key,
      open: () => ImportSheet.show(context, bundle),
      describe: (result, places) =>
          'Imported ${result.added} $places '
          '(${result.alreadySaved} already saved)',
    );
  }

  /// Same flow for a Google My Maps map [mid]: load → preview → import.
  Future<void> _promptMyMapsImport(String mid, {String? key}) {
    return _runImport(
      key: key,
      open: () => MyMapsImportSheet.show(context, mid),
      describe: (result, places) =>
          'Imported ${result.added} $places into “${result.board.name}” '
          '(${result.alreadySaved} already saved)',
    );
  }

  /// Shared guard + result handling for both import sheets: ignores a
  /// duplicate delivery of [key] within a few seconds and stacked prompts;
  /// on success switches to Boards and shows [describe]'s SnackBar.
  Future<void> _runImport({
    required String? key,
    required Future<ImportResult?> Function() open,
    required String Function(ImportResult result, String places) describe,
  }) async {
    if (!mounted) return;
    final now = DateTime.now();
    if (_importInProgress) return;
    if (key != null &&
        key == _lastImportKey &&
        _lastImportAt != null &&
        now.difference(_lastImportAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastImportKey = key;
    _lastImportAt = now;
    _importInProgress = true;
    // Captured before the sheet opens so the SnackBar has a valid messenger.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await open();
      if (result == null || !mounted) return;
      setState(() => _index = 2);
      final places = result.added == 1 ? 'place' : 'places';
      messenger.showSnackBar(SnackBar(content: Text(describe(result, places))));
    } finally {
      _importInProgress = false;
    }
  }

  /// Manual fallback (works on web too): paste a shared link or message.
  Future<void> _importFromLinkDialog() async {
    final bundle = await ImportLinkDialog.show(context);
    if (bundle != null && mounted) await _promptImport(bundle);
  }

  /// Boards tab → Import → From Google My Maps: paste a link, then preview.
  Future<void> _importFromMyMapsDialog() async {
    final mid = await MyMapsLinkDialog.show(context);
    if (mid != null && mounted) await _promptMyMapsImport(mid);
  }

  void _shareAllSaved() {
    ExportSheet.show(
      context,
      TripBundle(
        title: 'My saved places',
        places: List.of(PlaceStore.instance.places.value),
      ),
    );
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = _index != 0;

    return Scaffold(
      extendBodyBehindAppBar: !showAppBar,
      appBar: showAppBar
          ? AppBar(
              title: Text(_titles[_index]),
              actions: [
                if (_index == 1)
                  IconButton(
                    tooltip: 'Share all saved',
                    icon: const Icon(Icons.ios_share),
                    onPressed: _shareAllSaved,
                  ),
                if (_index == 2)
                  PopupMenuButton<_ImportSource>(
                    tooltip: 'Import',
                    icon: const Icon(Icons.download_outlined),
                    onSelected: (source) => switch (source) {
                      _ImportSource.tripLink => _importFromLinkDialog(),
                      _ImportSource.myMaps => _importFromMyMapsDialog(),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _ImportSource.tripLink,
                        child: ListTile(
                          leading: Icon(Icons.link),
                          title: Text('From a shared trip link'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ImportSource.myMaps,
                        child: ListTile(
                          leading: Icon(Icons.map_outlined),
                          title: Text('From Google My Maps'),
                        ),
                      ),
                    ],
                  ),
                const AccountButton(),
                const SizedBox(width: 4),
                const ThemeToggleButton(),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: IndexedStack(
        index: _index,
        children: [
          MapScreen(onAddFind: _openAddFind),
          const FeedScreen(),
          const BoardsScreen(),
        ],
      ),
      // The map tab surfaces its own "Add a find" button in the sheet
      // header (so it stays reachable at any drag extent and doesn't cover
      // the sheet/attribution); Saved keeps the "Add a find" FAB; Boards
      // gets a "New board" FAB instead (its own creation flow, not a find).
      floatingActionButton: switch (_index) {
        0 => null,
        2 => FloatingActionButton.extended(
          onPressed: () => NewBoardDialog.showAndContinue(context),
          backgroundColor: AppTheme.coral,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          icon: const Icon(Icons.add),
          label: const Text('New board'),
        ),
        _ => FloatingActionButton.extended(
          onPressed: () => _openAddSheet(),
          backgroundColor: AppTheme.coral,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          icon: const Icon(Icons.add_link),
          label: const Text('Add a find'),
        ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Boards',
          ),
        ],
      ),
    );
  }

  /// Zero-arg wrapper so [MapScreen]'s `VoidCallback onAddFind` can call
  /// [_openAddSheet], which takes an optional `initialText` (used by the
  /// share-intake flow above).
  void _openAddFind() => _openAddSheet();

  void _openAddSheet({String initialText = ''}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: AddFindSheet(initialText: initialText),
      ),
    );
  }
}

/// The "Add a find" sheet: paste a link or caption → Gemini extraction →
/// geocode → saved to the store and shown on the map/feed.
class AddFindSheet extends StatefulWidget {
  const AddFindSheet({super.key, this.initialText = ''});

  final String initialText;

  @override
  State<AddFindSheet> createState() => _AddFindSheetState();
}

class _AddFindSheetState extends State<AddFindSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  final _extractor = PlaceExtractor();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _extractor.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final place = await _extractor.extract(input);
      PlaceStore.instance.add(place);
      if (!mounted) return;
      Navigator.pop(context);
      // Show the freshly-extracted place.
      PlaceDetailSheet.show(context, place);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    if (e is CaptionUnavailableException) {
      debugPrint('extraction error: $e');
      return "Couldn't read this post's caption (it may be private). "
          'Paste the caption or the place name too.';
    }
    if (e is NoPlaceFoundException) {
      debugPrint('extraction error: $e');
      return "Couldn't find a place in this post. "
          'Add the place name and try again.';
    }
    final msg = e.toString();
    debugPrint('extraction error: $msg');
    if (msg.contains('GEMINI_API_KEY')) {
      return 'No Gemini key set. Run with '
          '--dart-define=GEMINI_API_KEY=your_key to enable extraction.';
    }
    if (msg.contains('403') ||
        msg.contains('API_KEY_SERVICE_BLOCKED') ||
        msg.contains('are blocked')) {
      return 'The Gemini key isn\'t allowed to use this API yet. In Google '
          'Cloud Console → Credentials → this key → API restrictions, add '
          '"Generative Language API".';
    }
    // Strip the leading `Exception: ` prefix `Exception.toString()` adds,
    // so the user sees the underlying message, not Dart plumbing.
    final stripped = msg.startsWith('Exception: ')
        ? msg.substring('Exception: '.length)
        : msg;
    return 'Extraction failed: $stripped';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add a find',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Paste an Instagram/TikTok link (and its caption for best results). '
              'Gemini extracts the place, we map it and write a summary.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 2,
              enabled: !_busy,
              decoration: const InputDecoration(
                hintText:
                    'https://instagram.com/reel/...\n\nPaste the caption here too',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.coral, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _extract,
              icon: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_busy ? 'Extracting…' : 'Extract & save'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.coral,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
