import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../data/place_store.dart';
import '../services/place_extractor.dart';
import '../theme/app_theme.dart';
import 'boards_screen.dart';
import 'feed_screen.dart';
import 'map_screen.dart';
import 'place_detail_sheet.dart';

/// App shell with the Map ⇄ Saved ⇄ Boards triad (ANALYSIS.md §§3,5,6).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  static const _titles = ['Explore', 'Saved', 'Boards'];

  bool get _shareIntakeSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_shareIntakeSupported) _initShareIntake();
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
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        _handleShared(files);
        ReceiveSharingIntent.instance.reset();
      }).catchError((Object e) => debugPrint('share intake init error: $e'));
    } catch (e) {
      // Native plugin not available (e.g. test harness) — share intake is optional.
      debugPrint('share intake unavailable: $e');
    }
  }

  void _handleShared(List<SharedMediaFile> files) {
    if (files.isEmpty || !mounted) return;
    // For text/URL shares the content arrives in `path`.
    final shared = files
        .map((f) => f.path)
        .where((p) => p.trim().isNotEmpty)
        .join('\n');
    if (shared.isNotEmpty) _openAddSheet(initialText: shared);
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = _index != 0;

    return Scaffold(
      extendBodyBehindAppBar: !showAppBar,
      appBar: showAppBar ? AppBar(title: Text(_titles[_index])) : null,
      body: IndexedStack(
        index: _index,
        children: const [
          MapScreen(),
          FeedScreen(),
          BoardsScreen(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(),
        backgroundColor: AppTheme.coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_link),
        label: const Text('Add a find'),
      ),
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

  void _openAddSheet({String initialText = ''}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
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
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
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
    final msg = e.toString();
    if (msg.contains('GEMINI_API_KEY')) {
      return 'No Gemini key set. Run with '
          '--dart-define=GEMINI_API_KEY=your_key to enable extraction.';
    }
    return 'Extraction failed: $msg';
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
            const Text('Add a find',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Paste an Instagram/TikTok link (and its caption for best results). '
              'Gemini extracts the place, we map it and write a summary.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
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
                hintText: 'https://instagram.com/reel/...\n\nPaste the caption here too',
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
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
