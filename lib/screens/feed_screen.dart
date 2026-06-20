import 'package:flutter/material.dart';

import '../data/place_store.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';
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

  List<Place> _filter(List<Place> all) {
    if (_query.trim().isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.areaLabel.toLowerCase().contains(q) ||
          p.descriptionEn.toLowerCase().contains(q) ||
          p.category.labelEn.toLowerCase().contains(q);
    }).toList();
  }

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
              fillColor: AppTheme.surface,
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
              if (results.isEmpty) return const _EmptyState();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore,
                size: 48, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            const Text(
              'Nothing here yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Share a reel or post to CheapTripChip and we’ll '
              'place it on the map for you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
