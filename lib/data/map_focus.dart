import 'package:flutter/foundation.dart';

/// "Show board X on the map", sent from the Boards tab to the map. A new
/// instance per request (no value equality), so asking for the same board
/// twice still notifies.
class MapBoardFocus {
  MapBoardFocus(this.boardKey);

  /// A [BoardRef.key] (see map_filter.dart).
  final String boardKey;
}

/// Cross-tab channel owned by the home shell: the Boards tab calls
/// [showBoard], the map listens and applies the board filter + camera fit.
class MapFocusController extends ValueNotifier<MapBoardFocus?> {
  MapFocusController() : super(null);

  void showBoard(String boardKey) => value = MapBoardFocus(boardKey);
}
