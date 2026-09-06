import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../data/place_store.dart';
import '../models/board.dart';
import '../models/place.dart';
import '../theme/app_theme.dart';
import 'place_detail_sheet.dart';

/// Boards (ANALYSIS.md §5): Board → Section → Item hierarchy, expandable.
class BoardsScreen extends StatelessWidget {
  const BoardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlaceStore.instance.places,
      builder: (context, places, _) {
        final placesById = {for (final p in places) p.id: p};
        final autoBoard = newFindsBoard(places, MockData.boards);
        final boards = [?autoBoard, ...MockData.boards];
        return ListView.separated(
          // Bottom padding keeps the last board clear of the floating
          // "Add a find" button.
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: boards.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) =>
              _BoardCard(board: boards[i], placesById: placesById),
        );
      },
    );
  }
}

/// Auto-generated board (title 'New finds', emoji 📌) for [places] not
/// referenced by any section in [boards], grouped one section per category.
///
/// Returns null when every place is already referenced by a board — i.e.
/// there is nothing new to surface.
Board? newFindsBoard(List<Place> places, List<Board> boards) {
  final referencedIds = <String>{
    for (final board in boards)
      for (final section in board.sections) ...section.placeIds,
  };
  final unreferenced = places.where((p) => !referencedIds.contains(p.id));
  if (unreferenced.isEmpty) return null;

  // Group by category, preserving the order categories are first encountered.
  final byCategory = <PlaceCategory, List<String>>{};
  for (final place in unreferenced) {
    byCategory.putIfAbsent(place.category, () => []).add(place.id);
  }

  return Board(
    id: 'new-finds',
    name: 'New finds',
    emoji: '📌',
    sections: [
      for (final entry in byCategory.entries)
        BoardSection(title: entry.key.labelEn, placeIds: entry.value),
    ],
  );
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.board, required this.placesById});

  final Board board;
  final Map<String, Place> placesById;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: board.id == 'b1',
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Text(board.emoji, style: const TextStyle(fontSize: 26)),
          title: Text(
            board.name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${board.sections.length} sections · ${board.itemCount} places',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          children: [
            for (final section in board.sections)
              _SectionBlock(section: section, placesById: placesById),
          ],
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section, required this.placesById});

  final BoardSection section;
  final Map<String, Place> placesById;

  @override
  Widget build(BuildContext context) {
    // A section place id that no longer resolves against the live store
    // (e.g. removed) is skipped rather than crashing the tile.
    final ids = section.placeIds.where(placesById.containsKey).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '${section.title.toUpperCase()} · ${ids.length}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        for (final id in ids) _itemTile(context, placesById[id]!),
      ],
    );
  }

  Widget _itemTile(BuildContext context, Place place) {
    final color = AppTheme.categoryColor(
      place.category,
      Theme.of(context).brightness,
    );
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.2),
        // Emoji aren't accessible labels — expose the category via Semantics
        // and hide the raw glyph from the a11y tree (WCAG 1.4.1).
        child: Semantics(
          label: place.category.labelEn,
          child: ExcludeSemantics(
            child: Text(
              place.category.emoji,
              style: const TextStyle(fontSize: 15, height: 1),
            ),
          ),
        ),
      ),
      title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        place.areaLabel,
        style: TextStyle(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => PlaceDetailSheet.show(context, place),
    );
  }
}
