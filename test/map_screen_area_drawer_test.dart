import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/screens/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Mock data (6 places, all region "Tokyo, Japan", one district each) plus
/// two resolved Hong Kong places and one with no area yet.
final _places = [
  ...MockData.places,
  for (final (id, district) in [('hk1', 'Mong Kok'), ('hk2', 'Mong Kok')])
    Place(
      id: id,
      name: 'Noodles $id',
      areaLabel: district,
      region: 'Hong Kong',
      countryCode: 'HK',
      category: PlaceCategory.restaurant,
      location: const LatLng(22.3193, 114.1694),
      descriptionEn: '',
      originalCaption: '',
      address: '',
      hours: '',
      sourceHandle: '',
      sourcePlatform: SourcePlatform.googleMyMaps,
    ),
  const Place(
    id: 'unknown',
    name: 'Somewhere',
    areaLabel: '',
    region: '',
    category: PlaceCategory.sightseeing,
    location: LatLng(35.0, 135.0),
    descriptionEn: '',
    originalCaption: '',
    address: '',
    hours: '',
    sourceHandle: '',
    sourcePlatform: SourcePlatform.googleMyMaps,
  ),
];

Finder _inDrawer(Finder finder) =>
    find.descendant(of: find.byType(Drawer), matching: finder);

Future<void> _openDrawerAt(WidgetTester tester, Finder target) async {
  await tester.tap(find.byTooltip('Categories'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    _inDrawer(target),
    200,
    scrollable: _inDrawer(find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpMap(WidgetTester tester) async {
  PlaceStore.instance.places.value = List.of(_places);
  await tester.pumpWidget(MaterialApp(home: MapScreen(onAddFind: () {})));
  await tester.pump();
}

void main() {
  final total = _places.length;

  testWidgets('Areas section lists cities by count, filters by district', (
    tester,
  ) async {
    await _pumpMap(tester);
    expect(find.text('$total of $total places'), findsOneWidget);

    await _openDrawerAt(tester, find.text('Unknown area'));
    expect(_inDrawer(find.text('Areas')), findsOneWidget);

    // Tokyo (6) sorts above Hong Kong (2); the flag shows for HK.
    final tokyoY = tester.getTopLeft(_inDrawer(find.text('Tokyo'))).dy;
    final hkY = tester.getTopLeft(_inDrawer(find.text('Hong Kong'))).dy;
    expect(tokyoY, lessThan(hkY));
    expect(_inDrawer(find.text('🇭🇰')), findsOneWidget);

    await tester.tap(find.byTooltip('Show Hong Kong districts'));
    await tester.pumpAndSettle();
    await tester.tap(_inDrawer(find.text('Mong Kok')));
    await tester.pumpAndSettle();

    expect(find.text('Mong Kok, Hong Kong · 2'), findsOneWidget);
    expect(find.text('2 of $total places'), findsOneWidget);
  });

  testWidgets('area AND category; each chip clears only its own filter', (
    tester,
  ) async {
    await _pumpMap(tester);

    // Category: Restaurant (Gogo in Tokyo + the two Hong Kong places).
    await tester.tap(find.byTooltip('Categories'));
    await tester.pumpAndSettle();
    await tester.tap(_inDrawer(find.text('Restaurant')));
    await tester.pumpAndSettle();
    expect(find.text('3 of $total places'), findsOneWidget);

    // Area: the whole city of Tokyo.
    await _openDrawerAt(tester, find.text('Tokyo'));
    await tester.tap(_inDrawer(find.text('Tokyo')));
    await tester.pumpAndSettle();
    expect(find.text('Restaurant · 3'), findsOneWidget);
    expect(find.text('Tokyo · 6'), findsOneWidget);
    expect(find.text('1 of $total places'), findsOneWidget);

    // Clearing the area chip keeps the category.
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Clear area filter',
        ),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tokyo · 6'), findsNothing);
    expect(find.text('Restaurant · 3'), findsOneWidget);
    expect(find.text('3 of $total places'), findsOneWidget);
  });

  testWidgets('"Unknown area" filters to places without a city', (
    tester,
  ) async {
    await _pumpMap(tester);
    await _openDrawerAt(tester, find.text('Unknown area'));
    await tester.tap(_inDrawer(find.text('Unknown area')));
    await tester.pumpAndSettle();
    expect(find.text('Unknown area · 1'), findsOneWidget);
    expect(find.text('1 of $total places'), findsOneWidget);
  });
}
