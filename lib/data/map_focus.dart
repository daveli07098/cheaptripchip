import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// A request, sent from another tab, for the map to show something. A new
/// instance per request (no value equality), so asking for the same thing
/// twice still notifies.
sealed class MapFocus {}

/// "Show board X on the map", sent from the Boards tab.
class MapBoardFocus extends MapFocus {
  MapBoardFocus(this.boardKey);

  /// A [BoardRef.key] (see map_filter.dart).
  final String boardKey;
}

/// "Show this place on the map", sent from the place page, a Saved card or
/// a board row. [location] is used when [placeId] isn't one of the user's
/// own places (a shared-board copy): the map flies there without a pin.
class MapPlaceFocus extends MapFocus {
  MapPlaceFocus({
    required this.placeId,
    required this.name,
    required this.location,
  });

  final String placeId;
  final String name;
  final LatLng location;
}

/// Cross-tab channel owned by the home shell: the Boards tab calls
/// [showBoard], the map listens and applies the board filter + camera fit;
/// [showPlace] flies to one place and opens its preview card.
class MapFocusController extends ValueNotifier<MapFocus?> {
  MapFocusController() : super(null);

  void showBoard(String boardKey) => value = MapBoardFocus(boardKey);

  void showPlace({
    required String placeId,
    required String name,
    required LatLng location,
  }) => value = MapPlaceFocus(placeId: placeId, name: name, location: location);
}
