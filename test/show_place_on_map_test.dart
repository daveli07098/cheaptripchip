import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/screens/home_shell.dart';
import 'package:cheaptripchip/widgets/place_card.dart';
import 'package:cheaptripchip/widgets/place_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Show on map" for one place — from a Saved card, the place page and a
/// board row's ⋮ menu: switches to the map, opens the place's preview card
/// and flies close to it, clearing filters/search that would hide it.
void main() {
  setUp(() async {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    await Future<void>.delayed(Duration.zero);
  });

  final total = MockData.places.length;

  int selectedTab(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  MapCamera camera(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(NavigationDestination, label));
    await tester.pumpAndSettle();
  }

  void expectShown(WidgetTester tester, Place place) {
    expect(selectedTab(tester), 0);
    expect(
      find.descendant(
        of: find.byType(PlacePreviewCard),
        matching: find.text(place.name),
      ),
      findsOneWidget,
    );
    expect(camera(tester).zoom, greaterThanOrEqualTo(16));
    expect(camera(tester).visibleBounds.contains(place.location), isTrue);
  }

  testWidgets('Saved card map button flies to the place', (tester) async {
    final place = MockData.places[1];
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Saved');

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(PlaceCard, place.name),
        matching: find.byTooltip('Show on map'),
      ),
    );
    await tester.pumpAndSettle();

    expectShown(tester, place);
  });

  testWidgets('place page "Show on map" closes the sheet and flies there', (
    tester,
  ) async {
    final place = MockData.places.first;
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Saved');
    await tester.tap(find.widgetWithText(PlaceCard, place.name));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byTooltip('Show on map'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expectShown(tester, place);
  });

  testWidgets('a board row ⋮ "Show on map" clears a search that hid it', (
    tester,
  ) async {
    final place = MockData.places[2]; // p3, on "Coffee & Quiet"
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'teamLab');
    await tester.pumpAndSettle();
    expect(find.text('1 of $total places'), findsOneWidget);

    await openTab(tester, 'Boards');
    await tester.tap(find.text('Coffee & Quiet'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.widgetWithText(ListTile, place.name).last,
            matching: find.byTooltip('Place options'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show on map').last);
    await tester.pumpAndSettle();

    expect(find.text('$total of $total places'), findsOneWidget);
    expectShown(tester, place);
  });
}
