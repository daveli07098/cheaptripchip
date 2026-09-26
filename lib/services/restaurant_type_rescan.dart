import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/place_store.dart';
import '../models/restaurant_type_detect.dart';

/// Runs [PlaceStore.rescanRestaurantTypes] once per
/// [restaurantTypeDetectionVersion] for the data set identified by
/// [accountKey] (the signed-in uid, or `'guest'`), after [PlaceStore]'s bound
/// repository has delivered its first snapshot. Keyed per account so a
/// guest-mode rescan doesn't suppress the signed-in one after login. The
/// version is recorded only after a successful pass, so a failed write is
/// retried next launch. Returns how many places changed (0 when skipped).
Future<int> rescanRestaurantTypesIfNeeded(String accountKey) async {
  final placeStore = PlaceStore.instance;
  final loaded = placeStore.loaded;
  await loaded;
  final prefs = await SharedPreferences.getInstance();
  // Rebound to another account meanwhile: [PlaceStore.places] may still hold
  // this account's data, which must never be written into the new one.
  if (!identical(loaded, placeStore.loaded)) return 0;
  final key = 'restaurantTypeDetectionVersion.$accountKey';
  if ((prefs.getInt(key) ?? 0) >= restaurantTypeDetectionVersion) return 0;
  final int changed;
  try {
    changed = await placeStore.rescanRestaurantTypes();
  } catch (e) {
    // Offline/permission errors: leave the version unrecorded and retry
    // on the next launch rather than surfacing an unawaited error.
    debugPrint('Restaurant type rescan failed: $e');
    return 0;
  }
  await prefs.setInt(key, restaurantTypeDetectionVersion);
  if (changed > 0) {
    debugPrint('Restaurant types refined for $changed places');
  }
  return changed;
}
