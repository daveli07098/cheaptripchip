// The search pill grows with large text instead of clipping it.
import 'package:cheaptripchip/widgets/place_search_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
  });
  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<Size> pumpAt(WidgetTester tester, double scale) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: PlaceSearchPill(
                controller: controller,
                focusNode: focusNode,
                onOpenFilters: () {},
                onAsk: () {},
                trailing: const SizedBox.square(dimension: 48),
              ),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(PlaceSearchPill));
  }

  testWidgets('56 tall at the default text scale', (tester) async {
    expect((await pumpAt(tester, 1)).height, 56);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('no overflow or clipping at text scale $scale', (tester) async {
      controller.text = 'ramen';
      final size = await pumpAt(tester, scale);
      expect(tester.takeException(), isNull);
      expect(size.height, greaterThanOrEqualTo(56));
      // The field's own box holds its (scaled) text line.
      final field = tester.getSize(find.byType(TextField));
      final text = tester.getSize(find.text('ramen'));
      expect(field.height, greaterThanOrEqualTo(text.height));
      expect(size.height, greaterThanOrEqualTo(field.height));
    });
  }

  testWidgets('grows past 56 when the text line needs it (no clipping)', (
    tester,
  ) async {
    controller.text = 'ramen';
    // bodyLarge (16 px, height 1.5) at 3× is a 72 px line — taller than the
    // old fixed 56 px pill, which clipped it.
    final size = await pumpAt(tester, 3);
    expect(tester.takeException(), isNull);
    final line = tester.getSize(find.byType(EditableText)).height;
    expect(line, greaterThanOrEqualTo(72));
    expect(size.height, greaterThan(line));
  });
}
