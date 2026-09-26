import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/repositories.dart';
import 'package:cheaptripchip/models/place.dart';

/// [PlaceRepository] whose reads come from a real [LocalPlaceRepository]
/// but whose single-place writes throw while [failWrites] is true — for
/// exercising PlaceStore's optimistic-update revert and the UI's
/// "Couldn't save" path. [delete] throws while [failDeletes] is true.
class FailingPlaceRepository implements PlaceRepository {
  FailingPlaceRepository({this.failWrites = true, this.failDeletes = false});

  final LocalPlaceRepository _inner = LocalPlaceRepository();
  bool failWrites;
  bool failDeletes;

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
  Future<void> delete(String id) async {
    if (failDeletes) throw StateError('delete failed');
    await _inner.delete(id);
  }
}
