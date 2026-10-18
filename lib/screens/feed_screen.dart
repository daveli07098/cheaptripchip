import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/board_store.dart';
import '../data/map_filter.dart';
import '../data/place_filter_controller.dart';
import '../data/place_store.dart';
import '../data/shared_board_store.dart';
import '../models/place.dart';
import '../services/ai_search.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_results_chip.dart';
import '../widgets/ask_suggestions.dart';
import '../widgets/delete_find.dart';
import '../widgets/empty_state_card.dart';
import '../widgets/filter_chips.dart';
import '../widgets/filter_drawer.dart';
import '../widgets/onboarding_sheet.dart';
import '../widgets/place_card.dart';
import '../widgets/place_search_pill.dart';
import '../widgets/show_place_on_map.dart';
import 'place_detail_sheet.dart';

/// Saved feed (ANALYSIS.md §6): scrollable card list of all saves, narrowed
/// by the SAME filters + search as the map ([PlaceFilterController], owned
/// by the home shell) — the same search pill, Filters drawer and chips.
/// Only the map's camera moves are map-only.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.filters, this.onAddFind});

  /// Shared with the map; null = a private one, e.g. in tests.
  final PlaceFilterController? filters;

  /// The "Add a find" FAB; null hides it. It lives on this screen's own
  /// Scaffold (not the home shell's) so the Filters drawer's scrim covers it.
  final VoidCallback? onAddFind;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchFocusNode = FocusNode();
  PlaceFilterController? _ownFilters;

  PlaceFilterController get _filters =>
      widget.filters ?? (_ownFilters ??= PlaceFilterController());

  // Last results, reused while places/boards/filter are unchanged.
  List<Place>? _loaded;
  MapFilter? _filter;
  BoardIndex? _boards;
  List<Place> _results = const [];

  /// Filters every loaded place — not the map's [MapPlaceIndex.all], which
  /// drops non-finite coordinates: a place that can't be drawn is still a
  /// save and belongs here.
  List<Place> _resultsFor(
    List<Place> loaded,
    MapFilter filter,
    BoardIndex boards,
  ) {
    if (identical(loaded, _loaded) &&
        filter == _filter &&
        identical(boards, _boards)) {
      return _results;
    }
    _loaded = loaded;
    _filter = filter;
    _boards = boards;
    // AI results come back ranked best-first.
    return _results = rankedForFilter(
      loaded
          .where((p) => filter.matches(p, boardIndex: boards))
          .toList(growable: false),
      filter,
    );
  }

  /// "Ask your places" from the Saved tab: "near me" is the map's last
  /// visible centre ([PlaceFilterController.mapCenter]).
  void _ask(String question, BoardIndex boards) {
    _searchFocusNode.unfocus();
    _filters.ask(
      question,
      places: PlaceStore.instance.places.value,
      boards: boards,
    );
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _ownFilters?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filters = _filters;
    return ListenableBuilder(
      listenable: Listenable.merge([
        PlaceStore.instance.places,
        BoardStore.instance.boards,
        SharedBoardStore.instance.boards,
        filters,
      ]),
      builder: (context, _) {
        final loaded = PlaceStore.instance.places.value;
        final index = filters.cache.indexFor(loaded);
        final boardIndex = filters.cache.boardsFor(
          loaded,
          BoardStore.instance.boards.value,
          SharedBoardStore.instance.boards.value,
        );
        final filter = filters.filter;
        final results = _resultsFor(loaded, filter, boardIndex);
        // An empty store shows its own "Add a find" button in the empty
        // state, so the FAB would only duplicate it.
        final emptyStore = loaded.isEmpty;
        return Scaffold(
          key: _scaffoldKey,
          // The home shell's Scaffold already avoids the keyboard.
          resizeToAvoidBottomInset: false,
          // Opens from the ☰ button only, same as the map.
          drawerEnableOpenDragGesture: false,
          floatingActionButton: widget.onAddFind == null || emptyStore
              ? null
              : FloatingActionButton.extended(
                  onPressed: widget.onAddFind,
                  backgroundColor: AppTheme.coral,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add a find'),
                ),
          drawer: FilterDrawer(
            filters: filters,
            index: index,
            boardIndex: boardIndex,
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: PlaceSearchPill(
                  controller: filters.search,
                  focusNode: _searchFocusNode,
                  activeFilters: filter.activeCount,
                  elevation: 1,
                  onOpenFilters: () => _scaffoldKey.currentState?.openDrawer(),
                  onSubmitted: (text) => looksLikeQuestion(text)
                      ? _ask(text, boardIndex)
                      : _searchFocusNode.unfocus(),
                  onAsk: () => _ask(filters.search.text, boardIndex),
                  asking: filters.asking,
                ),
              ),
              AskSuggestions(
                controller: filters.search,
                focusNode: _searchFocusNode,
                suggestions: filters.suggestionsFor(loaded),
                onAsk: (question) => _ask(question, boardIndex),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              ),
              ActiveFilterChips(
                filters: filters,
                index: index,
                boardIndex: boardIndex,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              ),
              AiResultsChip(
                filters: filters,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: results.isEmpty
                    ? _EmptyState(
                        narrowed:
                            loaded.isNotEmpty &&
                            (filter.query.trim().isNotEmpty ||
                                filter.hasActiveFilters ||
                                filter.hasAiResults),
                        onAddFind: widget.onAddFind,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            _dismissibleCard(context, results[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Saved-tab card: tap opens the place page, the map button shows it on
/// the map, and a swipe end-to-start deletes the find (with UNDO) — same
/// look as the Boards tab's swipe-to-remove rows.
Widget _dismissibleCard(BuildContext context, Place place) {
  final scheme = Theme.of(context).colorScheme;
  final showOnMap = ShowPlaceOnMap.maybeOf(context);
  // Grabbed per call: the optimistic delete rebuilds this list without the
  // card, so the card's context can't be used afterwards.
  void delete() => deleteFindWithUndo(ScaffoldMessenger.of(context), place);
  return Dismissible(
    key: ValueKey('saved/${place.id}'),
    direction: DismissDirection.endToStart,
    background: Container(
      // Matches the Card's default margin and the theme's 18dp corners.
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: scheme.onError),
          const SizedBox(width: 8),
          Text(
            'Delete',
            style: TextStyle(
              color: scheme.onError,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
    onDismissed: (_) => delete(),
    // A Dismissible's swipe gesture alone isn't exposed to assistive tech
    // — pair it with an explicit custom action.
    child: Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: 'Delete find'): delete,
      },
      child: PlaceCard(
        place: place,
        onTap: () => PlaceDetailSheet.show(context, place),
        onShowOnMap: showOnMap == null ? null : () => showOnMap(place),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.narrowed, this.onAddFind});

  /// True when the search and/or filters hide every saved place — distinct
  /// from a genuinely empty store.
  final bool narrowed;

  /// The "Add a find" action of a genuinely empty store; hidden when null.
  final VoidCallback? onAddFind;

  @override
  Widget build(BuildContext context) {
    if (narrowed) {
      return const EmptyStateCard(
        icon: Icons.search_off,
        title: 'No matches',
        body: 'Try another search, or clear the filters.',
      );
    }
    return EmptyStateCard(
      icon: Icons.travel_explore,
      title: 'No finds yet',
      body:
          'Share a post from Instagram or TikTok, paste its link, or add a '
          'screenshot. $kSameFindsExplainer',
      // Bottom padding keeps the buttons clear of the shell's navigation.
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
      actions: [
        if (onAddFind case final onAddFind?)
          FilledButton.icon(
            onPressed: onAddFind,
            icon: const Icon(Icons.add_link),
            label: const Text('Add a find'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.coral,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => showOnboardingSheet(context),
          icon: const Icon(Icons.help_outline),
          label: const Text('How it works'),
        ),
      ],
    );
  }
}
