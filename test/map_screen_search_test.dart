import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/screens/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search bar narrows the place-list sheet count', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MapScreen(onAddFind: () {})));
    await tester.pump();

    final total = PlaceStore.instance.places.value.length;
    expect(find.text('$total of $total places'), findsOneWidget);

    // "Gogo" (mock data's p1, '五感 (Gogo)') is a unique name — narrows to 1.
    await tester.enterText(find.byType(TextField), 'Gogo');
    await tester.pump();
    expect(find.text('1 of $total places'), findsOneWidget);

    // A query matching nothing narrows to zero.
    await tester.enterText(find.byType(TextField), 'zzz-no-such-place');
    await tester.pump();
    expect(find.text('0 of $total places'), findsOneWidget);

    // Clearing the query restores every place.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pump();
    expect(find.text('$total of $total places'), findsOneWidget);
  });
}
