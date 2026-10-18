import 'dart:async';
import 'dart:io' show File;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../data/map_focus.dart';
import '../data/place_filter_controller.dart';
import '../data/place_store.dart';
import '../models/place.dart';
import '../services/auth_service.dart';
import '../services/board_invite_link.dart';
import '../services/import_service.dart';
import '../services/my_maps_import.dart';
import '../services/trip_share.dart';
import '../services/web_share_intake.dart';
import '../theme/app_theme.dart';
import '../utils/replace_browser_url.dart';
import '../widgets/account_button.dart';
import '../widgets/add_find_sheet.dart';
import '../widgets/board_invite_flow.dart';
import '../widgets/install_hint.dart';
import '../widgets/export_sheet.dart';
import '../widgets/import_sheet.dart';
import '../widgets/my_maps_import_sheet.dart';
import '../widgets/new_board_dialog.dart';
import '../widgets/onboarding_sheet.dart';
import '../widgets/show_place_on_map.dart';
import 'boards_screen.dart';
import 'feed_screen.dart';
import 'map_screen.dart';

/// Entries of the Boards tab's Import menu.
enum _ImportSource { tripLink, myMaps }

/// "⤓ Import", styled like a [TextButton.icon] — the Boards app bar's
/// Import menu anchor.
class _ImportLabel extends StatelessWidget {
  const _ImportLabel();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_outlined, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              'Import',
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// App shell with the Map ⇄ Saved ⇄ Boards triad (ANALYSIS.md §§3,5,6).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.showFirstRunPrompts = true});

  /// The first-launch "How it works" sheet and the web "Add to Home Screen"
  /// hint, each shown until dismissed once. Off in widget tests that aren't
  /// about them (prefs that can't be read also keep them hidden).
  final bool showFirstRunPrompts;

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

  /// Boards tab → "Show on map" → the map applies that board's filter; a
  /// place's "Show on map" (place page, Saved card, board row) → the map
  /// flies to it.
  final _mapFocus = MapFocusController();

  /// Filters + search shared by the Map and Saved tabs.
  final _filters = PlaceFilterController();

  static const _titles = ['Map', 'Saved', 'Boards'];

  /// iPhone Safari, not installed, hint not dismissed (see
  /// [shouldShowInstallHint]).
  bool _showInstallHint = false;

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
    final sharedOnLaunch = kIsWeb && _initWebShareIntake();
    if (widget.showFirstRunPrompts) {
      // A post shared in on launch opens "Add a find" — the welcome sheet
      // would cover it, so it waits for a later launch.
      if (!sharedOnLaunch) _maybeShowOnboarding();
      _initInstallHint();
    }
  }

  /// First launch: the "How it works" sheet, once. Skipped (until a later
  /// launch) when something — e.g. a share-intake "Add a find" sheet — is
  /// already open on top of the shell.
  Future<void> _maybeShowOnboarding() async {
    if (await OnboardingPrefs.seen() || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      showOnboardingSheet(context);
    });
  }

  Future<void> _initInstallHint() async {
    final wanted = await installHintWanted();
    if (wanted && mounted) setState(() => _showInstallHint = true);
  }

  void _dismissInstallHint() {
    setState(() => _showInstallHint = false);
    InstallHintPrefs.dismiss();
  }

  /// Web stand-in for share intake: a start URL like `/?add=<post link>`
  /// (Apple Shortcut) or `/?text=…&url=…` (Android Web Share Target) opens
  /// "Add a find" with the link and starts extracting right away. The query
  /// is removed from the address bar first, so a reload doesn't re-add it.
  /// Returns whether the start URL carried a share.
  bool _initWebShareIntake() {
    final shared = sharedTextFromQuery(Uri.base.queryParameters);
    if (shared == null) return false;
    replaceBrowserUrl(withoutShareParams(Uri.base));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Let a signed-in session restore first, so the find is saved to the
      // account rather than to guest storage. Guests proceed after the wait.
      await AuthService.instance.ready.timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
      if (!mounted) return;
      _openAddSheet(initialText: shared, autoExtract: true);
    });
    return true;
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
    // A shared screenshot/photo (Android "Share → cheaptripchip" from the
    // gallery or a screenshot preview) is read with Gemini vision.
    final image = files
        .where((f) => f.type == SharedMediaType.image)
        .firstOrNull;
    if (image != null) {
      await _openAddSheetWithImage(image.path);
      return;
    }
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
    _mapFocus.dispose();
    _filters.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = _index != 0;

    // Every tab (and the place pages opened from them) reaches the map's
    // per-place "Show on map" through this scope.
    return ShowPlaceOnMap(
      onShow: _showPlaceOnMap,
      child: _buildScaffold(context, showAppBar),
    );
  }

  Widget _buildScaffold(BuildContext context, bool showAppBar) {
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
                    // A labelled affordance rather than a bare download
                    // icon, whose meaning wasn't obvious. A plain (non-
                    // interactive) child: the menu button owns the tap.
                    child: const _ImportLabel(),
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
                // The theme picker lives in the account sheet (Appearance).
                const AccountButton(),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: IndexedStack(
        index: _index,
        children: [
          MapScreen(
            onAddFind: _openAddFind,
            focus: _mapFocus,
            filters: _filters,
          ),
          FeedScreen(filters: _filters, onAddFind: _openAddFind),
          BoardsScreen(
            onShowOnMap: _showBoardOnMap,
            onImportTripLink: _importFromLinkDialog,
            onImportMyMaps: _importFromMyMapsDialog,
            onAddFind: _openAddFind,
          ),
        ],
      ),
      // The map tab surfaces its own "Add a find" button in the sheet
      // header (so it stays reachable at any drag extent and doesn't cover
      // the sheet/attribution); Saved keeps the "Add a find" FAB, on its own
      // Scaffold (see FeedScreen.onAddFind) so its Filters drawer covers it;
      // Boards gets a "New board" FAB instead (its own creation flow).
      floatingActionButton: switch (_index) {
        0 => null,
        2 => FloatingActionButton.extended(
          onPressed: () => NewBoardDialog.showAndContinue(context),
          backgroundColor: AppTheme.coral,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          icon: const Icon(Icons.add),
          label: const Text('New board'),
        ),
        _ => null,
      },
      // The install hint sits just above the tabs: visible on every tab and
      // clear of the map's search pill at the top.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showInstallHint)
            InstallHintBanner(onDismiss: _dismissInstallHint),
          _navigationBar(),
        ],
      ),
    );
  }

  Widget _navigationBar() {
    return NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: 'Map',
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
    );
  }

  /// Switches to the map tab, then asks it to show board [boardKey].
  void _showBoardOnMap(String boardKey) {
    setState(() => _index = 0);
    _mapFocus.showBoard(boardKey);
  }

  /// Switches to the map tab, then asks it to fly to [place] and open its
  /// preview card.
  void _showPlaceOnMap(Place place) {
    setState(() => _index = 0);
    _mapFocus.showPlace(
      placeId: place.id,
      name: place.name,
      location: place.location,
    );
  }

  /// Zero-arg wrapper so [MapScreen]'s `VoidCallback onAddFind` can call
  /// [_openAddSheet], which takes an optional `initialText` (used by the
  /// share-intake flow above).
  void _openAddFind() => _openAddSheet();

  Future<void> _openAddSheetWithImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (mounted) _openAddSheet(initialImage: bytes);
    } catch (e) {
      debugPrint('shared image unreadable: $e');
    }
  }

  void _openAddSheet({
    String initialText = '',
    bool autoExtract = false,
    Uint8List? initialImage,
  }) {
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
        child: AddFindSheet(
          initialText: initialText,
          autoExtract: autoExtract,
          initialImage: initialImage,
        ),
      ),
    );
  }
}
