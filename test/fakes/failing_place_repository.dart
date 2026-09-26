import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/repositories.dart';
import 'package:cheaptripchip/models/place.dart';

/// [PlaceRepository] whose reads come from a real [LocalPlaceRepository]
/// but whose single-place writes throw while [failWrites] is true — for
/// exercising PlaceStore's optimistic-update revert and the UI's
/// "Couldn't save" path.
class FailingPlaceRepository implements PlaceRepository {
  FailingPlaceRepository({this.failWrites = true});

  final LocalPlaceRepository _inner = LocalPlaceRepository();
  bool failWrites;

  @override
  Stream<List<Place>> watch() => _inner.watch();

  @override
  Future<void> upsert(Place place) async {
    if (failWrites) throw StateError('write failed');
    await _inner.upsert(place);
  }

  @override
  Future<void> upsertAll(List<Place> places) => _inner.upsertAll(places);

  @override
  Future<void> updateAll(List<Place> places) => _inner.updateAll(places);

  @override
  Future<void> delete(String id) => _inner.delete(id);
}
