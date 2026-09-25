import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../models/place.dart';
import 'guest_storage.dart';
import 'mock_data.dart';
import 'repositories.dart';

/// [PlaceRepository] for guest mode, seeded from [MockData.places].
/// Never mutates [MockData] — copies it into an internal list on construction.
///
/// Without [storage] it is purely in-memory (what tests use). With [storage]
/// (what `PlaceStore.bind` uses) the list is loaded from the last saved
/// snapshot — [MockData] only seeds a first launch — and every change is
/// written back (debounced), so guest places survive app restarts.
class LocalPlaceRepository implements PlaceRepository {
  LocalPlaceRepository({GuestSnapshotStore? storage})
    : _collection = _LocalCollection<Place>(
        seed: MockData.places,
        idOf: (p) => p.id,
        toJson: (p) => p.toJson(),
        fromJson: Place.fromJson,
        storage: storage,
      );

  final _LocalCollection<Place> _collection;

  /// Fires the full current list after every change; each new [watch]
  /// listener gets an immediate replay of the current list (once loaded)
  /// via [Stream.multi], then subsequent updates as they happen.
  @override
  Stream<List<Place>> watch() => _collection.watch();

  /// Inserts new places at the top (feed shows newest first); replaces
  /// existing places by id in place.
  @override
  Future<void> upsert(Place place) => _collection.upsertAll([place]);

  /// Same as [upsert] for many places with a single change event and a
  /// single snapshot write; new places keep their given order at the top.
  @override
  Future<void> upsertAll(List<Place> places) => _collection.upsertAll(places);

  @override
  Future<void> delete(String id) => _collection.delete(id);

  /// Writes any pending snapshot now instead of waiting for the debounce.
  @visibleForTesting
  Future<void> flush() => _collection.flush();
}

/// [BoardRepository] for guest mode, seeded from [MockData.boards]. Same
/// in-memory / persisted split as [LocalPlaceRepository].
class LocalBoardRepository implements BoardRepository {
  LocalBoardRepository({GuestSnapshotStore? storage})
    : _collection = _LocalCollection<Board>(
        seed: MockData.boards,
        idOf: (b) => b.id,
        toJson: (b) => b.toJson(),
        fromJson: Board.fromJson,
        storage: storage,
      );

  final _LocalCollection<Board> _collection;

  @override
  Stream<List<Board>> watch() => _collection.watch();

  /// Inserts new boards at the top; replaces existing boards by id in place.
  @override
  Future<void> upsert(Board board) => _collection.upsertAll([board]);

  @override
  Future<void> delete(String id) => _collection.delete(id);

  @visibleForTesting
  Future<void> flush() => _collection.flush();
}

/// The list + change stream + optional snapshot persistence shared by the
/// two local repositories.
class _LocalCollection<T> {
  _LocalCollection({
    required List<T> seed,
    required this.idOf,
    required this.toJson,
    required this.fromJson,
    this.storage,
  }) {
    if (storage == null) {
      _items = List<T>.from(seed);
      _loaded = true;
      _ready = Future<void>.value();
    } else {
      _ready = _load(seed);
    }
  }

  final String Function(T item) idOf;
  final Map<String, dynamic> Function(T item) toJson;
  final T Function(Map<String, dynamic> json) fromJson;
  final GuestSnapshotStore? storage;

  /// Coalesces bursts of changes (e.g. an import followed by a board
  /// write) into one snapshot write.
  static const _saveDelay = Duration(milliseconds: 250);

  List<T> _items = [];
  bool _loaded = false;
  late final Future<void> _ready;
  Timer? _saveTimer;
  Future<void>? _writing;
  bool _dirty = false;

  final StreamController<List<T>> _changes =
      StreamController<List<T>>.broadcast();

  Future<void> _load(List<T> seed) async {
    List<T>? restored;
    try {
      final raw = await storage!.read();
      if (raw != null) {
        restored = [];
        for (final entry in jsonDecode(raw) as List) {
          try {
            restored.add(fromJson(Map<String, dynamic>.from(entry as Map)));
          } catch (e) {
            debugPrint('LocalRepository: skipping unreadable entry: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('LocalRepository: snapshot unreadable, using seed: $e');
      restored = null;
    }
    _items = restored ?? List<T>.from(seed);
    _loaded = true;
  }

  Stream<List<T>> watch() {
    return Stream<List<T>>.multi((controller) {
      StreamSubscription<List<T>>? subscription;
      var cancelled = false;
      void start() {
        if (cancelled) return;
        controller.add(List.unmodifiable(_items));
        subscription = _changes.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      }

      controller.onCancel = () {
        cancelled = true;
        return subscription?.cancel();
      };
      // In-memory collections replay synchronously, as before persistence
      // existed; persisted ones replay once the snapshot has loaded.
      if (_loaded) {
        start();
      } else {
        _ready.then((_) => start());
      }
    });
  }

  Future<void> upsertAll(List<T> items) async {
    // Only wait while a snapshot is loading: once loaded, mutate and echo
    // synchronously (no microtask hop), as the in-memory repository always
    // did — callers' optimistic updates rely on echoes arriving in order.
    if (!_loaded) await _ready;
    if (items.isEmpty) return;
    final indexById = <String, int>{
      for (var i = 0; i < _items.length; i++) idOf(_items[i]): i,
    };
    final fresh = <T>[];
    final freshIndex = <String, int>{};
    for (final item in items) {
      final id = idOf(item);
      final existing = indexById[id];
      if (existing != null) {
        _items[existing] = item;
      } else if (freshIndex.containsKey(id)) {
        fresh[freshIndex[id]!] = item;
      } else {
        freshIndex[id] = fresh.length;
        fresh.add(item);
      }
    }
    if (fresh.isNotEmpty) _items.insertAll(0, fresh);
    _changed();
    // A bulk save (import) is written before it reports success, so the
    // caller's "Imported N places" never precedes the data reaching disk.
    if (items.length > 1) await flush();
  }

  Future<void> delete(String id) async {
    if (!_loaded) await _ready;
    _items.removeWhere((item) => idOf(item) == id);
    _changed();
  }

  void _changed() {
    _changes.add(List.unmodifiable(_items));
    if (storage == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(flush()));
  }

  /// Writes the current list now. Writes never overlap: a change during a
  /// write marks the snapshot dirty and triggers one more write after it.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final store = storage;
    if (store == null) return;
    if (_writing != null) {
      _dirty = true;
      return _writing;
    }
    final completer = Completer<void>();
    _writing = completer.future;
    try {
      do {
        _dirty = false;
        final json = jsonEncode([for (final item in _items) toJson(item)]);
        try {
          await store.write(json);
        } catch (e) {
          debugPrint('LocalRepository: saving snapshot failed: $e');
        }
      } while (_dirty);
    } finally {
      _writing = null;
      completer.complete();
    }
  }
}
