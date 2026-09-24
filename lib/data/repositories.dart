import '../models/board.dart';
import '../models/place.dart';

/// Backs [PlaceStore] — either [LocalPlaceRepository] (guest mode) or
/// [FirestorePlaceRepository] (signed-in). See lib/data/local_repositories.dart
/// and lib/data/firestore_repositories.dart.
abstract class PlaceRepository {
  Stream<List<Place>> watch();
  Future<void> upsert(Place place);
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
