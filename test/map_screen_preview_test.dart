import 'package:cheaptripchip/screens/map_screen.dart';
import 'package:cheaptripchip/widgets/map_pin.dart';
import 'package:cheaptripchip/widgets/place_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping a pin shows the preview card; empty map hides it', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: MapScreen(onAddFind: () {})));
    await tester.pump();
    expect(find.byType(PlacePreviewCard), findsNothing);

    final pins = find.byType(MapPin);
    expect(pins, findsWidgets);
    await tester.tap(pins.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PlacePreviewCard), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);

    // Empty map (left edge, between the search bar and the sheet).
    await tester.tapAt(const Offset(4, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(PlacePreviewCard), findsNothing);
  });
}
