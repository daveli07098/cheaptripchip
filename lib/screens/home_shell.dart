import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'boards_screen.dart';
import 'feed_screen.dart';
import 'map_screen.dart';

/// App shell with the Map ⇄ Saved ⇄ Boards triad (ANALYSIS.md §§3,5,6).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Explore', 'Saved', 'Boards'];

  @override
  Widget build(BuildContext context) {
    // The map fills the screen edge-to-edge; Saved/Boards get an app bar.
    final showAppBar = _index != 0;

    return Scaffold(
      extendBodyBehindAppBar: !showAppBar,
      appBar: showAppBar
          ? AppBar(title: Text(_titles[_index]))
          : null,
      body: IndexedStack(
        index: _index,
        children: const [
          MapScreen(),
          FeedScreen(),
          BoardsScreen(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context),
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

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add a find',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Paste an Instagram or TikTok link and we’ll extract the '
                'place, map it, and write a summary.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  hintText: 'https://instagram.com/reel/...',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Extraction pipeline not wired in this draft yet'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Extract & save'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.coral,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
