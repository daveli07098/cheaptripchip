import 'package:flutter/widgets.dart';

import '../models/place.dart';

/// Provided by the home shell: "Show on map" for one place — switches to
/// the Map tab, flies there and opens its preview card. Screens read it
/// with [maybeOf]; outside the shell (tests, previews) it is null and the
/// action is hidden.
///
/// Modal sheets are pushed on the root navigator, above the shell, so
/// PlaceDetailSheet.show looks this up from the caller's context and hands
/// the callback to the sheet.
class ShowPlaceOnMap extends InheritedWidget {
  const ShowPlaceOnMap({super.key, required this.onShow, required super.child});

  final ValueChanged<Place> onShow;

  /// A plain lookup (no dependency), so it is safe from event handlers; the
  /// shell's callback never changes.
  static ValueChanged<Place>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShowPlaceOnMap>()?.onShow;

  @override
  bool updateShouldNotify(ShowPlaceOnMap oldWidget) =>
      onShow != oldWidget.onShow;
}
