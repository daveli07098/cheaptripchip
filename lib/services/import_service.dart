import 'package:latlong2/latlong.dart';

import '../data/board_store.dart';
import '../data/place_store.dart';
import '../models/board.dart';
import '../models/place.dart';
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
  }) async {
    final places = placeStore ?? PlaceStore.instance;
    final boards = boardStore ?? BoardStore.instance;

    // One snapshot up front: PlaceStore.add is optimistic, but the
    // repository echo may briefly replace [places] mid-loop.
    final known = List<Place>.from(places.places.value);
    final boardIds = <String>[];
    var added = 0;
    var alreadySaved = 0;

    for (final incoming in bundle.places) {
      Place? match;
      for (final existing in known) {
        if (isDuplicate(existing, incoming)) {
          match = existing;
          break;
        }
      }
      if (match != null) {
        if (!boardIds.contains(match.id)) {
          boardIds.add(match.id);
          alreadySaved++;
        }
        continue;
      }
      await places.add(incoming);
      known.add(incoming);
      boardIds.add(incoming.id);
      added++;
    }

    final title = bundle.title.trim().isEmpty
        ? 'Shared trip'
        : bundle.title.trim();
    final board = await boards.createBoard(
      title,
      emoji: importedBoardEmoji,
      sections: [
        if (boardIds.isNotEmpty)
          BoardSection(title: importedSectionTitle, placeIds: boardIds),
      ],
    );
    return ImportResult(board: board, added: added, alreadySaved: alreadySaved);
  }
}
