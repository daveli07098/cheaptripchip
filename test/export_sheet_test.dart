import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/services/trip_share.dart';
import 'package:cheaptripchip/widgets/export_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(int i, {String description = ''}) => Place(
  id: 'p$i',
  name: 'Place number $i',
  areaLabel: 'Area $i',
  region: 'Tokyo, Japan',
  category: PlaceCategory.food,
  location: LatLng(35 + i / 1000, 139 + i / 1000),
  descriptionEn: description,
  originalCaption: '',
  address: 'Address $i',
  hours: '',
  sourceHandle: '@handle$i',
  sourcePlatform: SourcePlatform.tiktok,
);

Future<void> _open(WidgetTester tester, TripBundle bundle) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ExportSheet.show(context, bundle),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String title) =>
    tester.widget<ListTile>(find.widgetWithText(ListTile, title)).enabled;

void main() {
  const options = [
    'Share link',
    'Share file',
    'Export to Google My Maps',
    'Open route in Google Maps',
  ];

  testWidgets('shows the four export options, all enabled', (tester) async {
    await _open(
      tester,
      TripBundle(title: 'Tokyo', places: [_place(1), _place(2)]),
    );

    for (final option in options) {
      expect(find.text(option), findsOneWidget);
      expect(_enabled(tester, option), isTrue);
    }
  });

  testWidgets('disables "Share link" when the bundle is too big for a link', (
    tester,
  ) async {
    // Unique, long, incompressible-ish descriptions push the link past
    // TripShare.maxLinkLength.
    final places = [
      for (var i = 0; i < 200; i++)
        _place(i, description: 'Note ${i * 7919} ${'$i-${i * i}' * 20}'),
    ];
    final bundle = TripBundle(title: 'Huge', places: places);
    expect(TripShare.linkFits(bundle), isFalse);

    await _open(tester, bundle);

    expect(_enabled(tester, 'Share link'), isFalse);
    expect(
      find.text('Too many places for a link — share as a file'),
      findsOneWidget,
    );
    expect(_enabled(tester, 'Share file'), isTrue);
    expect(
      find.text(
        'Only the first ${ExportSheet.maxRouteStops} stops fit in a route',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an empty bundle explains there is nothing to share', (
    tester,
  ) async {
    await _open(tester, const TripBundle(title: 'Empty', places: []));

    expect(find.textContaining('Nothing to share'), findsOneWidget);
    for (final option in options) {
      expect(find.text(option), findsNothing);
    }
  });
}
