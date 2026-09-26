import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/place.dart';
import '../models/place_area.dart';
import '../models/place_note.dart';
import '../models/restaurant_type_detect.dart';
import '../services/auth_service.dart';
import 'board_store.dart';
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
  Completer<void> _loaded = Completer<void>();

  /// Completes once the currently bound repository has delivered its first
  /// snapshot — i.e. [places] holds the user's real data, not the
  /// [MockData] seed or the previous account's places. Replaced on every
  /// [bindRepository], so await it right after binding.
  Future<void> get loaded => _loaded.future;

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
    final loaded = _loaded = Completer<void>();
    _subscription = repository.watch().listen((value) {
      places.value = value;
      if (!loaded.isCompleted) loaded.complete();
    });
  }

  /// Throwing lookup — test-only; app code uses [byIdOrNull].
  @visibleForTesting
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

  /// Firestore chunk size for [updateAreas] and [rescanRestaurantTypes] — a
  /// flush is a few small batched writes rather than one huge one.
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
  /// in place and notifying listeners. Optimistic, like [add] — but reverted
  /// (and rethrown) if the repository write fails; see [_update].
  Future<void> toggleFavorite(String id) => _update(
    id,
    (current) => current.copyWith(isFavorite: !current.isFavorite),
  );

  /// Sets (or clears, when [score] is null) [Place.myScore] and overwrites
  /// [Place.myNotes] for the place with the given [id]. Optimistic with
  /// revert, like [toggleFavorite]. Callers must pass the *current* [notes]
  /// even when only the score is changing (and vice versa) — this replaces
  /// both fields, it doesn't merge them.
  Future<void> updateReview(String id, {int? score, required String notes}) =>
      _update(
        id,
        (current) => current.copyWith(
          myScore: score,
          clearMyScore: score == null,
          myNotes: notes,
        ),
      );

  /// Sets (or clears, when [at] is null) [Place.myPhotoAt] for the place
  /// with the given [id]. Called by PhotoStore after the photo bytes are
  /// written/deleted — the bytes themselves never touch the place doc.
  /// Optimistic with revert, like [toggleFavorite].
  Future<void> setPhotoMarker(String id, DateTime? at) => _update(
    id,
    (current) => current.copyWith(myPhotoAt: at, clearMyPhotoAt: at == null),
  );

  /// Sets (or clears back to the default, when [type] is null)
  /// [Place.restaurantType] for the place with the given [id]. Optimistic
  /// with revert, like [toggleFavorite]/[setPhotoMarker]. [manual] (default:
  /// this is the detail sheet's picker) marks the pick as the user's own
  /// ([Place.restaurantTypeManual]) so [rescanRestaurantTypes] never
  /// overrides it; clearing always resets the flag.
  Future<void> setRestaurantType(
    String id,
    RestaurantType? type, {
    bool manual = true,
  }) => _update(
    id,
    (current) => current.copyWith(
      restaurantType: type,
      clearRestaurantType: type == null,
      restaurantTypeManual: type != null && manual,
    ),
  );

  /// Re-runs keyword detection over every saved place and stores the
  /// refinements [refinedRestaurantType] finds — automatic types that were
  /// "Other" or a generic bucket a newer, more specific type was split out
  /// of. Manual picks and unset types are never written. One [places]
  /// update, then [PlaceRepository.updateAll] in chunks of [areaWriteChunk]
  /// (like [updateAreas]). Returns how many places changed.
  Future<int> rescanRestaurantTypes() async {
    final changed = <Place>[];
    final next = <Place>[];
    for (final place in places.value) {
      final refined = refinedRestaurantType(place);
      if (refined == null) {
        next.add(place);
        continue;
      }
      final updated = place.copyWith(restaurantType: refined);
      changed.add(updated);
      next.add(updated);
    }
    if (changed.isEmpty) return 0;
    places.value = next;
    for (var start = 0; start < changed.length; start += areaWriteChunk) {
      await _repository.updateAll(
        changed.skip(start).take(areaWriteChunk).toList(),
      );
    }
    return changed.length;
  }

  /// Changes [Place.category] for the place with the given [id] — the
  /// detail sheet's category chip. [Place.restaurantType] is kept as is:
  /// switching away just hides the cuisine chip
  /// ([Place.effectiveRestaurantType] is null off restaurants), and switching
  /// (back) to restaurant shows the earlier pick or the keyword-detected
  /// guess. Optimistic with revert, like [setRestaurantType].
  Future<void> updateCategory(String id, PlaceCategory category) => _update(
    id,
    (current) => current.category == category
        ? null
        : current.copyWith(category: category),
  );

  /// Counter folded into the current microsecond timestamp — same pattern as
  /// TripShare._newId — so note ids stay unique even when several are added
  /// within the same microsecond (e.g. tests).
  static int _noteIdCounter = 0;

  static String _newNoteId() {
    _noteIdCounter++;
    return 'note-${DateTime.now().microsecondsSinceEpoch}-$_noteIdCounter';
  }

  /// Appends a new dated [PlaceNote] to [Place.extraNotes] for the place
  /// with the given [id] — the detail sheet's "Add a visit note". No-ops on
  /// blank [text] or an unknown id. Optimistic with revert, like
  /// [toggleFavorite].
  Future<void> addNote(String id, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _update(id, (current) {
      final note = PlaceNote(
        id: _newNoteId(),
        text: trimmed,
        createdAt: DateTime.now(),
      );
      return current.copyWith(extraNotes: [...current.extraNotes, note]);
    });
  }

  /// Replaces the text of the [Place.extraNotes] entry [noteId] (keeping its
  /// original [PlaceNote.createdAt]) for the place with the given [id].
  /// No-ops on blank [text] or an unknown place/note id.
  Future<void> editNote(String id, String noteId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _update(id, (current) {
      if (!current.extraNotes.any((note) => note.id == noteId)) return null;
      return current.copyWith(
        extraNotes: [
          for (final note in current.extraNotes)
            note.id == noteId ? note.copyWith(text: trimmed) : note,
        ],
      );
    });
  }

  /// Removes the [Place.extraNotes] entry [noteId] for the place with the
  /// given [id]. Returns the removed [PlaceNote] (for an Undo snackbar via
  /// [restoreNote]), or `null` if the place/note wasn't found.
  Future<PlaceNote?> deleteNote(String id, String noteId) async {
    PlaceNote? removed;
    await _update(id, (current) {
      final notes = <PlaceNote>[];
      for (final note in current.extraNotes) {
        if (note.id == noteId) {
          removed = note;
        } else {
          notes.add(note);
        }
      }
      return removed == null ? null : current.copyWith(extraNotes: notes);
    });
    return removed;
  }

  /// Undo for [deleteNote]: re-inserts [note] (same id/createdAt) for the
  /// place with the given [id], unless a note with that id is already
  /// present (e.g. UNDO tapped twice).
  Future<void> restoreNote(String id, PlaceNote note) => _update(
    id,
    (current) => current.extraNotes.any((n) => n.id == note.id)
        ? null
        : current.copyWith(extraNotes: [...current.extraNotes, note]),
  );

  /// Deletes the find [id]: optimistically drops it from [places] and (in
  /// the same synchronous step, before the first await — a swiped
  /// Dismissible must be gone by the next frame) from every personal board
  /// via [BoardStore.removeFromAllBoards], one board write. Then deletes it
  /// from the repository. Shared-board copies are untouched (they're copies).
  ///
  /// The stored photo is NOT deleted here — the caller discards it once the
  /// undo window has passed (PhotoStore.discardPhotoOf), so [restoreDeleted]
  /// has nothing to re-upload. Returns the [DeletedPlace] snapshot for
  /// [restoreDeleted], or null for an unknown id. If a write fails, [places]
  /// and the boards are reverted and the error is rethrown (as [_update]).
  Future<DeletedPlace?> deletePlace(String id) async {
    final previous = places.value;
    final index = previous.indexWhere((p) => p.id == id);
    if (index == -1) return null;
    final boards = BoardStore.instance;
    final deleted = DeletedPlace(
      place: previous[index],
      index: index,
      memberships: boards.membershipsOf(id),
    );
    places.value = [
      for (final place in previous)
        if (place.id != id) place,
    ];
    // Called (not awaited) here so its optimistic update lands now.
    final boardsWrite = boards.removeFromAllBoards(id);
    try {
      await boardsWrite;
    } catch (_) {
      // BoardStore already reverted its own list.
      places.value = previous;
      rethrow;
    }
    try {
      await _repository.delete(id);
    } catch (_) {
      places.value = previous;
      try {
        await boards.restoreMemberships(id, deleted.memberships);
      } catch (error) {
        debugPrint('PlaceStore: re-adding $id to its boards failed: $error');
      }
      rethrow;
    }
    return deleted;
  }

  /// Undo for [deletePlace]: puts the place back at its old index in
  /// [places] and onto its boards at their old sections/positions (see
  /// [BoardStore.restoreMemberships]). No-op if it is already back (UNDO
  /// tapped twice). The feed position is only honoured optimistically, like
  /// [BoardStore.restoreBoard]: once the repository echoes back (Local:
  /// re-added ids land at index 0; Firestore: a fresh `savedAt`), the place
  /// shows at the top of the feed. If the place write fails it is taken out
  /// again and the error is rethrown.
  Future<void> restoreDeleted(DeletedPlace deleted) async {
    final place = deleted.place;
    if (byIdOrNull(place.id) != null) return;
    final current = places.value;
    final index = deleted.index.clamp(0, current.length);
    places.value = [
      ...current.sublist(0, index),
      place,
      ...current.sublist(index),
    ];
    final boards = BoardStore.instance;
    final boardsWrite = boards.restoreMemberships(
      place.id,
      deleted.memberships,
    );
    try {
      await _repository.upsert(place);
    } catch (_) {
      places.value = [
        for (final p in places.value)
          if (p.id != place.id) p,
      ];
      try {
        await boardsWrite;
        await boards.removeFromAllBoards(place.id);
      } catch (error) {
        debugPrint('PlaceStore: undoing restore of ${place.id} failed: $error');
      }
      rethrow;
    }
    await boardsWrite;
  }

  /// The single-place mutation every method above shares: looks up [id],
  /// applies [mutate] (returning `null` means "nothing to change" — no
  /// notification, no write), swaps the result into [places] optimistically,
  /// then writes it. If the repository write fails, [places] goes back to
  /// the list it held before this change and the error is rethrown for the
  /// caller to surface (same contract as PhotoStore._write).
  Future<void> _update(String id, Place? Function(Place current) mutate) async {
    final current = byIdOrNull(id);
    if (current == null) return;
    final updated = mutate(current);
    if (updated == null) return;
    final previous = places.value;
    places.value = [
      for (final place in previous)
        if (place.id == id) updated else place,
    ];
    try {
      await _repository.upsert(updated);
    } catch (_) {
      places.value = previous;
      rethrow;
    }
  }
}

/// What [PlaceStore.deletePlace] removed, for [PlaceStore.restoreDeleted]
/// (and PhotoStore.discardPhotoOf once the undo window has passed).
class DeletedPlace {
  const DeletedPlace({
    required this.place,
    required this.index,
    required this.memberships,
  });

  final Place place;

  /// Its index in [PlaceStore.places] at deletion time.
  final int index;

  /// The personal-board sections it sat in.
  final List<BoardMembership> memberships;

  /// Whether the place carried a photo marker ([Place.myPhotoAt]).
  bool get hadPhoto => place.myPhotoAt != null;
}
