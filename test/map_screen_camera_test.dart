import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/screens/map_screen.dart';
import 'package:cheaptripchip/widgets/map_pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _hongKong = LatLng(22.3193, 114.1694);

/// Mock data (Tokyo) plus two Hong Kong places.
final _places = [
  ...MockData.places,
  for (final id in ['hk1', 'hk2'])
    Place(
      id: id,
      name: 'Noodles $id',
      areaLabel: 'Mong Kok',
      region: 'Hong Kong',
      countryCode: 'HK',
      category: PlaceCategory.restaurant,
      location: _hongKong,
      descriptionEn: '',
      originalCaption: '',
      address: '',
      hours: '',
      sourceHandle: '',
      sourcePlatform: SourcePlatform.googleMyMaps,
    ),
];

MapCamera _camera(WidgetTester tester) =>
    tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;

Finder _inDrawer(Finder finder) =>
    find.descendant(of: find.byType(Drawer), matching: finder);

Future<void> _pumpMap(WidgetTester tester, [List<Place>? places]) async {
  PlaceStore.instance.places.value = List.of(places ?? _places);
  await tester.pumpWidget(MaterialApp(home: MapScreen(onAddFind: () {})));
  await tester.pump();
}

void main() {
  testWidgets('picking an area flies the camera to it once the drawer '
      'closes', (tester) async {
    await _pumpMap(tester);
    await tester.tap(find.byTooltip('Categories'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      _inDrawer(find.text('Hong Kong')),
      200,
      scrollable: _inDrawer(find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(_inDrawer(find.text('Hong Kong')));
    await tester.pumpAndSettle();

    final center = _camera(tester).center;
    expect(center.latitude, closeTo(_hongKong.latitude, 0.05));
    expect(center.longitude, closeTo(_hongKong.longitude, 0.05));
  });

  testWidgets('tapping a list row eases the camera there instead of jumping', (
    tester,
  ) async {
    await _pumpMap(tester, MockData.places);
    final start = _camera(tester);
    // Drag the sheet up so the first row is fully on screen.
    await tester.drag(find.textContaining(' places'), const Offset(0, -250));
    await tester.pumpAndSettle();

    await tester.tap(find.text(MockData.places.first.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midway = _camera(tester);
    expect(midway.zoom, isNot(closeTo(15, 0.01)));
    expect(midway.center, isNot(start.center));

    await tester.pumpAndSettle();
    expect(_camera(tester).zoom, greaterThanOrEqualTo(15));
  });

  testWidgets('tapping a pin selects only that pin', (tester) async {
    await _pumpMap(tester, MockData.places);
    final pins = find.byType(MapPin);
    expect(pins, findsWidgets);
    final tappedId = tester.widget<MapPin>(pins.first).place.id;
    await tester.tap(pins.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    final selected = tester
        .widgetList<MapPin>(find.byType(MapPin))
        .where((p) => p.selected)
        .map((p) => p.place.id);
    expect(selected, [tappedId]);
  });
}
