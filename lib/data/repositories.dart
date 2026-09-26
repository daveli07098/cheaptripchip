import '../models/board.dart';
import '../models/place.dart';

/// Backs [PlaceStore] — either [LocalPlaceRepository] (guest mode) or
/// [FirestorePlaceRepository] (signed-in). See lib/data/local_repositories.dart
/// and lib/data/firestore_repositories.dart.
abstract class PlaceRepository {
  Stream<List<Place>> watch();
  Future<void> upsert(Place place);

  /// Saves many places at once (bulk import) — one change event / batched
  /// writes instead of [upsert] per place.
  Future<void> upsertAll(List<Place> places);

  /// Saves edits to many places that already exist (e.g. the area
  /// backfill) in one change event / batched writes. Unlike [upsertAll] it
  /// never resets the "first saved" ordering marker.
  Future<void> updateAll(List<Place> places);
  Future<void> delete(String id);
}

/// Backs [BoardStore] — either [LocalBoardRepository] (guest mode) or
/// [FirestoreBoardRepository] (signed-in). See lib/data/local_repositories.dart
/// and lib/data/firestore_repositories.dart.
abstract class BoardRepository {
  Stream<List<Board>> watch();
  Future<void> upsert(Board board);

  /// Saves several boards together (e.g. both ends of a place move) — one
  /// change event / one atomic batched write, so watchers never see a
  /// half-applied state.
  Future<void> upsertAll(List<Board> boards);
  Future<void> delete(String id);
}
