import 'package:cheaptripchip/widgets/score_stars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScoreStars', () {
    /// Pumps a [ScoreStars] driven by a [StatefulBuilder] so taps flow
    /// through `onChanged` back into `value`, like a real caller wiring it
    /// to `PlaceStore.updateReview`.
    Future<void> pumpStars(WidgetTester tester, {int? initialValue}) async {
      int? value = initialValue;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ScoreStars(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                );
              },
            ),
          ),
        ),
      );
    }

    /// Taps within the 3rd star's 48dp box — [leftHalf] true hits its left
    /// half (sets 5), false hits its right half (sets 6). Star boxes are
    /// laid out left-to-right starting at the picker's top-left corner.
    Future<void> tapThirdStar(
      WidgetTester tester, {
      required bool leftHalf,
    }) async {
      final topLeft = tester.getTopLeft(find.byType(ScoreStars));
      // Star boxes: 48dp each, stars 1/2/3 precede this offset.
      const starSize = 48.0;
      final starLeft = topLeft.dx + starSize * 2; // 3rd star (0-indexed: 2)
      final dx = starLeft + (leftHalf ? starSize * 0.25 : starSize * 0.75);
      final dy = topLeft.dy + starSize / 2;
      await tester.tapAt(Offset(dx, dy));
      await tester.pump();
    }

    testWidgets('tapping left half of the 3rd star sets 5', (tester) async {
      await pumpStars(tester);
      await tapThirdStar(tester, leftHalf: true);

      expect(find.text('5/10'), findsOneWidget);
    });

    testWidgets('tapping right half of the 3rd star sets 6', (tester) async {
      await pumpStars(tester, initialValue: 5);
      await tapThirdStar(tester, leftHalf: false);

      expect(find.text('6/10'), findsOneWidget);
    });

    testWidgets('tapping the same value again clears it', (tester) async {
      await pumpStars(tester, initialValue: 6);
      await tapThirdStar(tester, leftHalf: false);

      expect(find.text('Tap to rate'), findsOneWidget);
    });

    testWidgets('exposes a single Semantics node with the score', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpStars(tester, initialValue: 9);

      // One SemanticsNode for the whole picker — not five per-star nodes —
      // carrying the "9 out of 10" value a screen reader would announce.
      final data = tester.getSemantics(find.byType(ScoreStars));
      expect(data.value, '9 out of 10');
      expect(find.byType(ScoreStars), findsOneWidget);

      handle.dispose();
    });
  });
}
