import 'package:cheaptripchip/data/memory_photo_repository.dart';
import 'package:cheaptripchip/data/photo_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/widgets/map_pin.dart';
import 'package:cheaptripchip/widgets/place_card.dart';
import 'package:cheaptripchip/widgets/place_list_sheet.dart';
import 'package:cheaptripchip/widgets/place_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// A ramen restaurant: its pin shows 🍜 — so must its list row, preview
/// card and feed card (they used to show the generic 🍽️).
const _ramen = Place(
  id: 'ramen',
  name: 'Ramen Bar',
  areaLabel: 'Ikebukuro',
  region: 'Tokyo',
  category: PlaceCategory.restaurant,
  location: LatLng(35.73, 139.71),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
  restaurantType: RestaurantType.ramen,
);

Future<void> _expectRamenOnly(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
  expect(find.text(RestaurantType.ramen.emoji), findsOneWidget);
  expect(find.text(PlaceCategory.restaurant.emoji), findsNothing);
  expect(
    find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Ramen',
    ),
    findsOneWidget,
  );
}

void main() {
  setUp(() => PhotoStore.instance.bindRepository(MemoryPhotoRepository()));

  testWidgets('map pin', (tester) async {
    await _expectRamenOnly(
      tester,
      Center(
        child: MapPin(
          place: _ramen,
          selected: false,
          brightness: Brightness.light,
          onTap: () {},
        ),
      ),
    );
  });

  testWidgets('list sheet row', (tester) async {
    await _expectRamenOnly(
      tester,
      PlaceListSheet(
        places: const [_ramen],
        total: 1,
        selectedId: ValueNotifier(null),
        onSelectPlace: (_) {},
        onOpenDetail: (_) {},
        onAddFind: () {},
      ),
    );
  });

  testWidgets('preview card (no-photo tile + meta row)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlacePreviewCard(place: _ramen, onOpenDetails: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    // Thumbnail fallback and the category line both show the marker.
    expect(find.text(RestaurantType.ramen.emoji), findsNWidgets(2));
    expect(find.text(PlaceCategory.restaurant.emoji), findsNothing);
  });

  testWidgets('feed card', (tester) async {
    await _expectRamenOnly(tester, PlaceCard(place: _ramen, onTap: () {}));
  });
}
