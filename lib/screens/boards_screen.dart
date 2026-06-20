import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../models/board.dart';
import '../theme/app_theme.dart';
import 'place_detail_sheet.dart';

/// Boards (ANALYSIS.md §5): Board → Section → Item hierarchy, expandable.
class BoardsScreen extends StatelessWidget {
  const BoardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: MockData.boards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _BoardCard(board: MockData.boards[i]),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.board});

  final Board board;

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
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          children: [
            for (final section in board.sections)
              _SectionBlock(section: section),
          ],
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section});

  final BoardSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '${section.title.toUpperCase()} · ${section.placeIds.length}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
        for (final id in section.placeIds) _itemTile(context, id),
      ],
    );
  }

  Widget _itemTile(BuildContext context, String id) {
    final place = MockData.placeById(id);
    final color = AppTheme.categoryColor(place.category);
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.2),
        child: Icon(AppTheme.categoryIcon(place.category),
            size: 16, color: color),
      ),
      title: Text(place.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(place.areaLabel,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => PlaceDetailSheet.show(context, place),
    );
  }
}
