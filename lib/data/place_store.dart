import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/place.dart';
import '../services/auth_service.dart';
import 'firestore_repositories.dart';
import 'local_repositories.dart';
import 'mock_data.dart';
import 'repositories.dart';

/// Runtime store for saved places, seeded from [MockData] until [bind] is
/// called with a real [AppUser] (or `null` for guest mode).
///
/// This is runtime STATE mirrored from a [PlaceRepository] — [LocalPlaceRepository]
/// backs guest mode, [FirestorePlaceRepository] backs signed-in users (see
/// lib/data/repositories.dart). The screens listen via [ValueListenableBuilder]
/// and don't change based on which repository is bound.
class PlaceStore {
  PlaceStore._();
  static final PlaceStore instance = PlaceStore._();

  final ValueNotifier<List<Place>> places = ValueNotifier<List<Place>>(
    List<Place>.from(MockData.places),
  );

  PlaceRepository _repository = LocalPlaceRepository();
  StreamSubscription<List<Place>>? _subscription;

  /// Picks [LocalPlaceRepository] when [user] is null (guest mode) or
  /// [FirestorePlaceRepository] under `users/{uid}/places` when signed in,
  /// cancelling any previous subscription first. Guest data is NOT uploaded
  /// on sign-in — this is deliberate (see the multi-user contract).
  Future<void> bind(AppUser? user) async {
    final repository = user == null
        ? LocalPlaceRepository()
        : FirestorePlaceRepository(user.uid);
    bindRepository(repository);
  }

  /// Test seam: bind directly to a given [repository] (e.g. a
  /// [LocalPlaceRepository] seeded for a test), bypassing [AppUser]
  /// resolution. Cancels any previous subscription and immediately starts
  /// mirroring [repository]'s stream into [places].
  @visibleForTesting
  void bindRepository(PlaceRepository repository) {
    _subscription?.cancel();
    _repository = repository;
    _subscription = repository.watch().listen((value) {
      places.value = value;
    });
  }

  Place byId(String id) => places.value.firstWhere((p) => p.id == id);

  /// Same as [byId] but returns null instead of throwing when not found.
  Place? byIdOrNull(String id) {
    for (final place in places.value) {
      if (place.id == id) return place;
    }
    return null;
  }

  /// Add a newly-saved place to the top of the feed. Optimistically updates
  /// [places] before the repository write resolves, so the UI doesn't wait on
  /// Firestore; callers may ignore the returned future.
  Future<void> add(Place place) async {
    places.value = [place, ...places.value];
    await _repository.upsert(place);
  }

  /// Flips [Place.isFavorite] for the place with the given [id], replacing it
  /// in place and notifying listeners. Optimistic, like [add].
  Future<void> toggleFavorite(String id) async {
    final current = byIdOrNull(id);
    if (current == null) return;
    final updated = current.copyWith(isFavorite: !current.isFavorite);
    places.value = [
      for (final place in places.value)
        if (place.id == id) updated else place,
    ];
    await _repository.upsert(updated);
  }
}
