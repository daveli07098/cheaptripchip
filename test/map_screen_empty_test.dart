import 'package:cheaptripchip/data/guest_storage.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/screens/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regression: guest places load from disk after the first frame, so the
  // map can build with zero places. Fitting the camera to an empty list gave
  // LatLng(NaN, NaN) and a red screen in TileLayer.
  testWidgets('map builds without error when there are no places', (
    tester,
  ) async {
    // An empty saved snapshot ('[]') means no places, not the mock seed.
    PlaceStore.instance.bindRepository(
      LocalPlaceRepository(storage: MemorySnapshotStore('[]')),
    );
    await tester.pumpWidget(MaterialApp(home: MapScreen(onAddFind: () {})));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(PlaceStore.instance.places.value, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
