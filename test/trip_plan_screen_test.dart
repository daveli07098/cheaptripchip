import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/trip_plan.dart';
import 'package:cheaptripchip/screens/trip_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(String id, double lat) => Place(
  id: id,
  name: 'Place $id',
  areaLabel: '',
  region: '',
  category: PlaceCategory.sightseeing,
  location: LatLng(lat, 139.7),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
);

final _places = {
  for (final (i, id) in ['a', 'b', 'c', 'd'].indexed)
    id: _place(id, 35 + i / 100),
};

const _plan = TripPlan(
  days: [
    [
      TripStop(placeId: 'a', slot: TimeSlot.morning, reason: 'Open early'),
      TripStop(placeId: 'b', slot: TimeSlot.lunch),
    ],
    [TripStop(placeId: 'c', slot: TimeSlot.dinner)],
  ],
  unplaced: ['d'],
  options: TripPlanOptions(days: 2),
  source: TripPlanSource.ai,
);

void main() {
  late List<TripPlan> changes;
  late List<Uri> launched;

  Future<void> pump(WidgetTester tester, {bool showMaps = false}) async {
    changes = [];
    launched = [];
    await tester.pumpWidget(
      MaterialApp(
        home: TripPlanScreen(
          title: 'Tokyo',
          plan: _plan,
          placesById: _places,
          onChanged: changes.add,
          launch: (uri) async {
            launched.add(uri);
            return true;
          },
          showMaps: showMaps,
        ),
      ),
    );
  }

  List<String> ids(TripPlan plan, int day) => [
    for (final s in plan.days[day]) s.placeId,
  ];

  testWidgets('shows day tabs, stops with slots and reasons', (tester) async {
    await pump(tester);
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Day 2'), findsOneWidget);
    expect(find.text("Didn't fit (1)"), findsOneWidget);
    expect(find.text('Place a'), findsOneWidget);
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Open early'), findsOneWidget);

    await tester.tap(find.text('Day 2'));
    await tester.pumpAndSettle();
    expect(find.text('Place c'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);

    await tester.tap(find.text("Didn't fit (1)"));
    await tester.pumpAndSettle();
    expect(find.text('Place d'), findsOneWidget);
  });

  testWidgets('drag reorders stops within a day', (tester) async {
    await pump(tester);
    final handle = find.byIcon(Icons.drag_indicator).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(changes, isNotEmpty);
    expect(ids(changes.last, 0), ['b', 'a']);
  });

  testWidgets('moves a stop to another day from its menu', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Stop options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Day 2'));
    await tester.pumpAndSettle();

    expect(ids(changes.last, 0), ['b']);
    expect(ids(changes.last, 1), ['c', 'a']);
  });

  testWidgets('opens the day in Google Maps', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Open day in Google Maps'));
    await tester.pump();

    expect(launched, hasLength(1));
    expect(launched.single.path, '/maps/dir/');
    expect(launched.single.queryParameters['origin'], 'Place a');
    expect(launched.single.queryParameters['destination'], 'Place b');
  });

  testWidgets('renders the day map with numbered pins', (tester) async {
    await pump(tester, showMaps: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FlutterMap), findsOneWidget);
    for (final n in ['1', '2']) {
      expect(
        find.descendant(of: find.byType(FlutterMap), matching: find.text(n)),
        findsOneWidget,
      );
    }
  });
}
