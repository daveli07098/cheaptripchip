/// Board → Section → Item organization hierarchy (see ANALYSIS.md §5).
///
/// A [Board] is a top-level trip/theme container. Each [BoardSection] groups
/// saved places (referenced by [Place.id]) under a category within the board.
class Board {
  const Board({
    required this.id,
    required this.name,
    required this.emoji,
    required this.sections,
  });

  final String id;
  final String name;
  final String emoji;
  final List<BoardSection> sections;

  int get itemCount =>
      sections.fold(0, (sum, section) => sum + section.placeIds.length);
}

class BoardSection {
  const BoardSection({
    required this.title,
    required this.placeIds,
  });

  final String title;

  /// References [Place.id] values — the same place can live in multiple boards.
  final List<String> placeIds;
}
