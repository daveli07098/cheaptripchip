import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/place.dart';
import '../models/place_area.dart';
import '../services/auth_service.dart';
import 'firestore_repositories.dart';
import 'guest_storage.dart';
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

  /// The persisted guest repository, created on the first guest [bind] and
  /// reused afterwards so a sign-out → guest round trip never races its own
  /// pending snapshot write.
  LocalPlaceRepository? _guestRepository;

  /// Picks [LocalPlaceRepository] when [user] is null (guest mode) or
  /// [FirestorePlaceRepository] under `users/{uid}/places` when signed in,
  /// cancelling any previous subscription first. Guest data is NOT uploaded
  /// on sign-in — this is deliberate (see the multi-user contract).
  Future<void> bind(AppUser? user) async {
    final repository = user == null
        ? _guestRepository ??= LocalPlaceRepository(
            storage: GuestSnapshotStore.forCollection('places'),
          )
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

  /// Bulk [add] for imports: prepends [newPlaces] (in their given order) in
  /// one [places] update and one repository batch, instead of one listener
  /// notification + write per place.
  Future<void> addAll(List<Place> newPlaces) async {
    if (newPlaces.isEmpty) return;
    places.value = [...newPlaces, ...places.value];
    await _repository.upsertAll(newPlaces);
  }

  /// Firestore chunk size for [updateAreas] — a flush is a few small
  /// batched writes rather than one huge one.
  static const areaWriteChunk = 50;

  /// Sets [Place.region]/[Place.areaLabel]/[Place.countryCode] for many
  /// places at once — the area backfill (AreaResolver) and the detail
  /// sheet's manual edit. Values are written as given (callers decide what
  /// to keep); unknown ids and no-op entries are skipped. One [places]
  /// update, then [PlaceRepository.updateAll] (which, unlike [addAll],
  /// keeps the feed order) in chunks of [areaWriteChunk].
  Future<void> updateAreas(Map<String, PlaceArea> areas) async {
    if (areas.isEmpty) return;
    final changed = <Place>[];
    final next = <Place>[];
    for (final place in places.value) {
      final area = areas[place.id];
      if (area == null ||
          (area.city == place.region &&
              area.district == place.areaLabel &&
              area.countryCode == place.countryCode)) {
        next.add(place);
        continue;
      }
      final updated = place.copyWith(
        region: area.city,
        areaLabel: area.district,
        countryCode: area.countryCode,
      );
      changed.add(updated);
      next.add(updated);
    }
    if (changed.isEmpty) return;
    places.value = next;
    for (var start = 0; start < changed.length; start += areaWriteChunk) {
      await _repository.updateAll(
        changed.skip(start).take(areaWriteChunk).toList(),
      );
    }
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

  /// Sets (or clears, when [score] is null) [Place.myScore] and overwrites
  /// [Place.myNotes] for the place with the given [id]. Optimistic, like
  /// [add]/[toggleFavorite]. Callers must pass the *current* [notes] even
  /// when only the score is changing (and vice versa) — this replaces both
  /// fields, it doesn't merge them.
  Future<void> updateReview(
    String id, {
    int? score,
    required String notes,
  }) async {
    final current = byIdOrNull(id);
    if (current == null) return;
    final updated = current.copyWith(
      myScore: score,
      clearMyScore: score == null,
      myNotes: notes,
    );
    places.value = [
      for (final place in places.value)
        if (place.id == id) updated else place,
    ];
    await _repository.upsert(updated);
  }

  /// Sets (or clears, when [at] is null) [Place.myPhotoAt] for the place
  /// with the given [id]. Called by PhotoStore after the photo bytes are
  /// written/deleted — the bytes themselves never touch the place doc.
  /// Optimistic, like [toggleFavorite].
  Future<void> setPhotoMarker(String id, DateTime? at) async {
    final current = byIdOrNull(id);
    if (current == null) return;
    final updated = current.copyWith(myPhotoAt: at, clearMyPhotoAt: at == null);
    places.value = [
      for (final place in places.value)
        if (place.id == id) updated else place,
    ];
    await _repository.upsert(updated);
  }

  /// Sets (or clears back to the default, when [type] is null)
  /// [Place.restaurantType] for the place with the given [id]. Optimistic,
  /// like [toggleFavorite]/[setPhotoMarker].
  Future<void> setRestaurantType(String id, RestaurantType? type) async {
    final current = byIdOrNull(id);
    if (current == null) return;
    final updated = current.copyWith(
      restaurantType: type,
      clearRestaurantType: type == null,
    );
    places.value = [
      for (final place in places.value)
        if (place.id == id) updated else place,
    ];
    await _repository.upsert(updated);
  }

  /// Changes [Place.category] for the place with the given [id] — the
  /// detail sheet's category chip. [Place.restaurantType] is kept as is:
  /// switching away just hides the cuisine chip
  /// ([Place.effectiveRestaurantType] is null off restaurants), and switching
  /// (back) to restaurant shows the earlier pick or the keyword-detected
  /// guess. Optimistic, like [setRestaurantType].
  Future<void> updateCategory(String id, PlaceCategory category) async {
    final current = byIdOrNull(id);
    if (current == null || current.category == category) return;
    final updated = current.copyWith(category: category);
    places.value = [
      for (final place in places.value)
        if (place.id == id) updated else place,
    ];
    await _repository.upsert(updated);
  }
}
