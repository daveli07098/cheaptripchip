import 'package:flutter/material.dart';

import '../data/place_search.dart';
import '../data/place_store.dart';
import '../models/place.dart';
import '../widgets/place_card.dart';
import 'place_detail_sheet.dart';

/// Saved feed (ANALYSIS.md §6): searchable, scrollable card list of all saves.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String _query = '';

  // Delegates to the shared placeMatches matcher (lib/data/place_search.dart)
  // — a superset of what this screen searched before (name, areaLabel,
  // descriptionEn, category.labelEn), now also matching region, address,
  // category.labelZh and sourceHandle, plus multi-term AND.
  List<Place> _filter(List<Place> all) =>
      all.where((p) => placeMatches(p, _query)).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search saved items, boards, inspiration',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<List<Place>>(
            valueListenable: PlaceStore.instance.places,
            builder: (context, all, _) {
              final results = _filter(all);
              if (results.isEmpty) {
                return _EmptyState(searching: _query.trim().isNotEmpty);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                itemCount: results.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => PlaceCard(
                  place: results[i],
                  onTap: () => PlaceDetailSheet.show(context, results[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});

  /// True when a search query is active and matched nothing — distinct from
  /// a genuinely empty store.
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final title = searching ? 'No matches' : 'No finds yet';
    final body = searching
        ? 'Try another name, area or category.'
        : 'Tap Add a find to save your first place.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.travel_explore,
              size: 48,
              color: onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
