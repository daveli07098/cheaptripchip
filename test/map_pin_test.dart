import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/widgets/map_pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place({
  required PlaceCategory category,
  RestaurantType? restaurantType,
  String name = 'Somewhere',
}) {
  return Place(
    id: 'p',
    name: name,
    areaLabel: '',
    region: '',
    category: category,
    location: const LatLng(35.66, 139.70),
    descriptionEn: '',
    originalCaption: '',
    address: '',
    hours: '',
    sourceHandle: '',
    sourcePlatform: SourcePlatform.instagram,
    restaurantType: restaurantType,
  );
}

Future<void> _pumpPin(WidgetTester tester, Place place) {
  return tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: MapPin(
          place: place,
          selected: false,
          brightness: Brightness.light,
          onTap: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('restaurant pin shows its sub-type emoji', (tester) async {
    await _pumpPin(
      tester,
      _place(
        category: PlaceCategory.restaurant,
        restaurantType: RestaurantType.ramen,
      ),
    );
    expect(find.text('🍜'), findsOneWidget);
    expect(find.bySemanticsLabel('Ramen'), findsOneWidget);
  });

  testWidgets('"Other" restaurant keeps the generic emoji', (tester) async {
    await _pumpPin(
      tester,
      _place(
        category: PlaceCategory.restaurant,
        restaurantType: RestaurantType.other,
      ),
    );
    expect(find.text(PlaceCategory.restaurant.emoji), findsOneWidget);
  });

  testWidgets('non-restaurant pin shows its category emoji', (tester) async {
    await _pumpPin(tester, _place(category: PlaceCategory.cafe));
    expect(find.text('☕'), findsOneWidget);
    expect(find.bySemanticsLabel('Cafe'), findsOneWidget);
  });
}
