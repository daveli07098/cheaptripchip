import 'dart:async';

import '../models/board.dart';
import '../models/place.dart';
import 'mock_data.dart';
import 'repositories.dart';

/// In-memory [PlaceRepository] for guest mode, seeded from [MockData.places].
/// Never mutates [MockData] — copies it into an internal list on construction.
class LocalPlaceRepository implements PlaceRepository {
  LocalPlaceRepository() : _items = List<Place>.from(MockData.places);

  final List<Place> _items;

  /// Fires the full current list after every [upsert]/[delete]; each new
  /// [watch] listener gets an immediate replay of the current list via
  /// [Stream.multi], then subsequent updates as they happen.
  final StreamController<List<Place>> _changes =
      StreamController<List<Place>>.broadcast();

  @override
  Stream<List<Place>> watch() {
    return Stream<List<Place>>.multi((controller) {
      controller.add(List.unmodifiable(_items));
      final subscription = _changes.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  /// Inserts new places at the top (feed shows newest first); replaces
  /// existing places by id in place.
  @override
  Future<void> upsert(Place place) async {
    final index = _items.indexWhere((p) => p.id == place.id);
    if (index == -1) {
      _items.insert(0, place);
    } else {
      _items[index] = place;
    }
    _changes.add(List.unmodifiable(_items));
  }

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((p) => p.id == id);
    _changes.add(List.unmodifiable(_items));
  }
}

/// In-memory [BoardRepository] for guest mode, seeded from [MockData.boards].
/// Never mutates [MockData] — copies it into an internal list on construction.
class LocalBoardRepository implements BoardRepository {
  LocalBoardRepository() : _items = List<Board>.from(MockData.boards);

  final List<Board> _items;

  /// Fires the full current list after every [upsert]/[delete]; each new
  /// [watch] listener gets an immediate replay of the current list via
  /// [Stream.multi], then subsequent updates as they happen.
  final StreamController<List<Board>> _changes =
      StreamController<List<Board>>.broadcast();

  @override
  Stream<List<Board>> watch() {
    return Stream<List<Board>>.multi((controller) {
      controller.add(List.unmodifiable(_items));
      final subscription = _changes.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  /// Inserts new boards at the top; replaces existing boards by id in place.
  @override
  Future<void> upsert(Board board) async {
    final index = _items.indexWhere((b) => b.id == board.id);
    if (index == -1) {
      _items.insert(0, board);
    } else {
      _items[index] = board;
    }
    _changes.add(List.unmodifiable(_items));
  }

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((b) => b.id == id);
    _changes.add(List.unmodifiable(_items));
  }
}
