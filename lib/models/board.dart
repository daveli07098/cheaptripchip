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

  Board copyWith({String? name, String? emoji, List<BoardSection>? sections}) {
    return Board(
      id: id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      sections: sections ?? this.sections,
    );
  }

  /// Serializes to plain JSON types only, so this can be written directly to
  /// Firestore. [sections] becomes a list of [BoardSection.toJson] maps.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'sections': sections.map((section) => section.toJson()).toList(),
    };
  }

  /// Lenient parse counterpart to [toJson]. Missing/null [sections] falls
  /// back to an empty list rather than throwing.
  factory Board.fromJson(Map<String, dynamic> json) {
    return Board(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '',
      sections:
          (json['sections'] as List?)
              ?.map(
                (section) => BoardSection.fromJson(
                  Map<String, dynamic>.from(section as Map),
                ),
              )
              .toList() ??
          const [],
    );
  }
}

class BoardSection {
  const BoardSection({required this.title, required this.placeIds});

  final String title;

  /// References [Place.id] values — the same place can live in multiple boards.
  final List<String> placeIds;

  BoardSection copyWith({String? title, List<String>? placeIds}) {
    return BoardSection(
      title: title ?? this.title,
      placeIds: placeIds ?? this.placeIds,
    );
  }

  /// Serializes to plain JSON types only, so this can be written directly to
  /// Firestore.
  Map<String, dynamic> toJson() {
    return {'title': title, 'placeIds': placeIds};
  }

  /// Lenient parse counterpart to [toJson]. Missing/null [placeIds] falls
  /// back to an empty list rather than throwing.
  factory BoardSection.fromJson(Map<String, dynamic> json) {
    return BoardSection(
      title: json['title'] as String? ?? '',
      placeIds:
          (json['placeIds'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }
}

/// [sections] with the [remove] place ids dropped from every section (any
/// section left empty is pruned — it would render as a bare header), then
/// the [add] ids folded in, each into the section titled [sectionTitleFor]
/// (created at the end if missing). An id in both sets ends up removed; an
/// id already on the board isn't added twice. Shared by BoardStore (personal
/// boards) and SharedBoardStore.
List<BoardSection> sectionsWithChanges(
  List<BoardSection> sections, {
  Iterable<String> add = const [],
  Set<String> remove = const {},
  required String Function(String placeId) sectionTitleFor,
}) {
  var result = [
    for (final section in sections)
      section.copyWith(
        placeIds: section.placeIds.where((id) => !remove.contains(id)).toList(),
      ),
  ].where((section) => section.placeIds.isNotEmpty).toList();

  final alreadyIn = <String>{for (final section in result) ...section.placeIds};
  for (final placeId in add) {
    if (remove.contains(placeId) || alreadyIn.contains(placeId)) continue;
    final title = sectionTitleFor(placeId);
    final index = result.indexWhere((section) => section.title == title);
    if (index == -1) {
      result = [
        ...result,
        BoardSection(title: title, placeIds: [placeId]),
      ];
    } else {
      result = [
        for (var i = 0; i < result.length; i++)
          if (i == index)
            result[i].copyWith(placeIds: [...result[i].placeIds, placeId])
          else
            result[i],
      ];
    }
    alreadyIn.add(placeId);
  }
  return result;
}
