// PlaceCard touch target and large-text name wrapping.
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/widgets/place_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _place = Place(
  id: 'card-1',
  name: 'A very long place name that will not fit on a single card line',
  areaLabel: 'Shibuya',
  region: 'Tokyo, Japan',
  category: PlaceCategory.cafe,
  location: LatLng(35.6, 139.7),
  descriptionEn: 'Somewhere.',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
);

Future<void> _pump(WidgetTester tester, {double scale = 1}) =>
    tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: ListView(
              children: [
                PlaceCard(place: _place, onTap: () {}, onShowOnMap: () {}),
              ],
            ),
          ),
        ),
      ),
    );

int? _nameMaxLines(WidgetTester tester) =>
    tester.widget<Text>(find.text(_place.name)).maxLines;

void main() {
  testWidgets('"Show on map" has a ≥48×48 hit area, icon stays small', (
    tester,
  ) async {
    await _pump(tester);
    final size = tester.getSize(find.byTooltip('Show on map'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byIcon(Icons.map_outlined)), const Size(18, 18));
  });

  testWidgets('name is one line normally, two above text scale 1.2', (
    tester,
  ) async {
    await _pump(tester);
    expect(_nameMaxLines(tester), 1);

    await _pump(tester, scale: 1.3);
    expect(_nameMaxLines(tester), 2);
    expect(tester.takeException(), isNull);
  });
}
