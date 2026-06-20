import 'package:flutter_test/flutter_test.dart';

import 'package:cheaptripchip/main.dart';

void main() {
  testWidgets('App boots into the explore/map shell with bottom nav',
      (WidgetTester tester) async {
    await tester.pumpWidget(const CheapTripChipApp());
    await tester.pump();

    // The three-tab navigation triad should be present.
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Boards'), findsOneWidget);

    // The primary "Add a find" action is visible.
    expect(find.text('Add a find'), findsOneWidget);
  });
}
