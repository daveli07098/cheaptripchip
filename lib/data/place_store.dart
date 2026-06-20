import 'package:flutter/foundation.dart';

import '../models/place.dart';
import 'mock_data.dart';

/// In-memory runtime store for saved places, seeded from [MockData].
///
/// This is runtime STATE (so a newly-extracted place shows up immediately), not
/// persistence. Saves do not survive an app restart yet — that's the Firebase
/// layer's job (planned). When Firebase lands, back this store with a Firestore
/// stream; the screens listen via [ValueListenableBuilder] and won't change.
class PlaceStore {
  PlaceStore._();
  static final PlaceStore instance = PlaceStore._();

  final ValueNotifier<List<Place>> places =
      ValueNotifier<List<Place>>(List<Place>.from(MockData.places));

  /// Add a newly-saved place to the top of the feed.
  void add(Place place) {
    places.value = [place, ...places.value];
  }

  Place byId(String id) => places.value.firstWhere((p) => p.id == id);
}
