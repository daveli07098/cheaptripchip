import 'package:latlong2/latlong.dart';

import '../data/board_store.dart';
import '../data/place_store.dart';
import '../models/board.dart';
import '../models/place.dart';
import 'my_maps_import.dart';
import 'trip_share.dart';

/// Outcome of [ImportService.importBundle].
class ImportResult {
  const ImportResult({
    required this.board,
    required this.added,
    required this.alreadySaved,
  });

  /// The board created to hold the imported places.
  final Board board;

  /// Places newly saved to the [PlaceStore].
  final int added;

  /// Bundle places that matched an existing saved place and were reused.
  final int alreadySaved;
}

/// Imports a shared [TripBundle] into the stores. Pure logic — no widgets —
/// so it can be unit-tested against injected local repositories.
class ImportService {
  ImportService._();

  /// Two places closer than this (and with the same name) are duplicates.
  static const duplicateRadiusMeters = 50.0;

  static const importedBoardEmoji = '📥';
  static const importedSectionTitle = 'Shared';

  static const _distance = Distance();

  /// Whether [a] and [b] are the same real-world place: same name
  /// (case-insensitive, trimmed) and within [duplicateRadiusMeters].
  static bool isDuplicate(Place a, Place b) {
    if (a.name.trim().toLowerCase() != b.name.trim().toLowerCase()) {
      return false;
    }
    return _distance.as(LengthUnit.Meter, a.location, b.location) <=
        duplicateRadiusMeters;
  }

  /// Saves every place in [bundle] not already saved, then creates one board
  /// named after the bundle (emoji 📥) whose single "Shared" section holds
  /// all of the bundle's places — new ids for added places, the existing ids
  /// for duplicates. Duplicates inside the bundle itself collapse to one.
  static Future<ImportResult> importBundle(
    TripBundle bundle, {
    PlaceStore? placeStore,
    BoardStore? boardStore,
  }) {
    final title = bundle.title.trim().isEmpty
        ? 'Shared trip'
        : bundle.title.trim();
    return importSections(
      boardName: title,
      emoji: importedBoardEmoji,
      sections: [ImportSection(importedSectionTitle, bundle.places)],
      placeStore: placeStore,
      boardStore: boardStore,
    );
  }

  static const myMapsBoardEmoji = '🗺️';
  static const defaultMyMapsBoardName = 'temp';

  /// Imports the chosen layers of a Google My Maps export into one board
  /// named [boardName] (emoji 🗺️), one section per layer, in map order.
  static Future<ImportResult> importMyMaps(
    MyMapsDocument map, {
    required List<MyMapsFolder> folders,
    String boardName = defaultMyMapsBoardName,
    PlaceStore? placeStore,
    BoardStore? boardStore,
  }) {
    // Ids only need to be unique: a millisecond stamp plus a running index
    // (1,700+ places are created within the same millisecond).
    final stamp = DateTime.now().millisecondsSinceEpoch;
    var index = 0;
    final mapTitle = map.title.isEmpty ? 'Google My Maps' : map.title;
    final name = boardName.trim().isEmpty
        ? defaultMyMapsBoardName
        : boardName.trim();
    return importSections(
      boardName: name,
      emoji: myMapsBoardEmoji,
      sections: [
        for (final folder in folders)
          ImportSection(folder.name, [
            for (final placemark in folder.placemarks)
              placemark.toPlace(id: 'mm-$stamp-${index++}', mapTitle: mapTitle),
          ]),
      ],
      placeStore: placeStore,
      boardStore: boardStore,
    );
  }

  /// Core of every import: saves each incoming place that isn't already
  /// saved (one [PlaceStore.addAll] batch), then creates one board with a
  /// section per [sections] entry holding its places — new ids for added
  /// places, existing ids for duplicates of saved places ([isDuplicate]).
  /// Duplicates within the import collapse into the first occurrence (which
  /// may then sit in several sections). Empty sections are dropped.
  static Future<ImportResult> importSections({
    required String boardName,
    required String emoji,
    required List<ImportSection> sections,
    PlaceStore? placeStore,
    BoardStore? boardStore,
  }) async {
    final places = placeStore ?? PlaceStore.instance;
    final boards = boardStore ?? BoardStore.instance;

    final known = DuplicateIndex(places.places.value);
    final existingIds = {for (final p in places.places.value) p.id};
    final toAdd = <Place>[];
    final matchedExisting = <String>{};
    final boardSections = <BoardSection>[];

    for (final section in sections) {
      final ids = <String>[];
      for (final incoming in section.places) {
        final match = known.find(incoming);
        final String id;
        if (match != null) {
          id = match.id;
          if (existingIds.contains(id)) matchedExisting.add(id);
        } else {
          toAdd.add(incoming);
          known.add(incoming);
          id = incoming.id;
        }
        if (!ids.contains(id)) ids.add(id);
      }
      if (ids.isNotEmpty) {
        boardSections.add(BoardSection(title: section.title, placeIds: ids));
      }
    }

    await places.addAll(toAdd);
    final board = await boards.createBoard(
      boardName,
      emoji: emoji,
      sections: boardSections,
    );
    return ImportResult(
      board: board,
      added: toAdd.length,
      alreadySaved: matchedExisting.length,
    );
  }
}

/// One named group of places to import — becomes one [BoardSection].
class ImportSection {
  const ImportSection(this.title, this.places);

  final String title;
  final List<Place> places;
}

/// Places bucketed by normalised name, so [ImportService.isDuplicate]
/// checks only same-name candidates: O(1) per lookup instead of scanning
/// every saved place (an import of 1,700 places into 1,700 saved ones
/// would otherwise be ~3 million distance checks).
class DuplicateIndex {
  DuplicateIndex([Iterable<Place> places = const []]) {
    places.forEach(add);
  }

  final Map<String, List<Place>> _byName = {};

  static String _key(Place p) => p.name.trim().toLowerCase();

  void add(Place place) =>
      _byName.putIfAbsent(_key(place), () => []).add(place);

  /// The first indexed place [ImportService.isDuplicate] of [place], or null.
  Place? find(Place place) {
    final candidates = _byName[_key(place)];
    if (candidates == null) return null;
    for (final candidate in candidates) {
      if (ImportService.isDuplicate(candidate, place)) return candidate;
    }
    return null;
  }
}
