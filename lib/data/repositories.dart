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
  Future<void> delete(String id);
}

/// Backs [BoardStore] — either [LocalBoardRepository] (guest mode) or
/// [FirestoreBoardRepository] (signed-in). See lib/data/local_repositories.dart
/// and lib/data/firestore_repositories.dart.
abstract class BoardRepository {
  Stream<List<Board>> watch();
  Future<void> upsert(Board board);
  Future<void> delete(String id);
}
