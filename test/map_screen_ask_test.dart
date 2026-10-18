import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_filter_controller.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/screens/feed_screen.dart';
import 'package:cheaptripchip/screens/map_screen.dart';
import 'package:cheaptripchip/services/ai_search.dart';
import 'package:cheaptripchip/widgets/ai_results_chip.dart';
import 'package:cheaptripchip/widgets/place_card.dart';
import 'package:cheaptripchip/widgets/place_search_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final total = MockData.places.length;
  String? prompt;

  PlaceFilterController filtersAnswering(List<String> ids) =>
      PlaceFilterController(
        aiSearch: AiSearch(
          ask: (p) async {
            prompt = p;
            return {'placeIds': ids, 'explanation': 'Two coffee picks'};
          },
        ),
      );

  setUp(() {
    prompt = null;
    PlaceStore.instance.places.value = List.of(MockData.places);
  });

  testWidgets('ask → AI results chip + explanation → clear', (tester) async {
    final filters = filtersAnswering(['p3', 'not-a-place', 'p1']);
    addTearDown(filters.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(onAddFind: () {}, filters: filters),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'where to get coffee?');
    await tester.pump();
    // Question-like text offers an "Ask" chip under the pill.
    expect(find.text('Ask “where to get coffee?”'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(prompt, contains('map the user is looking at'));
    expect(find.text('AI results · 2'), findsOneWidget);
    expect(find.text('Two coffee picks'), findsOneWidget);
    expect(find.text('2 of $total places'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AiResultsChip),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();
    expect(find.byType(AiResultsChip), findsOneWidget);
    expect(find.text('AI results · 2'), findsNothing);
    expect(find.text('$total of $total places'), findsOneWidget);
    expect(filters.search.text, isEmpty);
  });

  testWidgets('the ✨ button asks even a plain word', (tester) async {
    final filters = filtersAnswering(['p1']);
    addTearDown(filters.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(onAddFind: () {}, filters: filters),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Gogo');
    await tester.pump();
    await tester.tap(find.byTooltip(kAskTooltip));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('AI results · 1'), findsOneWidget);
  });

  testWidgets('Saved tab: suggestion chip asks offline via keywords', (
    tester,
  ) async {
    final filters = PlaceFilterController(
      aiSearch: AiSearch(configured: false),
    );
    addTearDown(filters.dispose);
    await tester.pumpWidget(MaterialApp(home: FeedScreen(filters: filters)));
    await tester.pump();
    final suggestions = filters.suggestionsFor(
      PlaceStore.instance.places.value,
    );
    expect(suggestions, isNotEmpty);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.text(suggestions.first));
    await tester.pump();
    await tester.pump();

    expect(filters.search.text, suggestions.first);
    expect(find.textContaining('AI results ·'), findsOneWidget);
    final explanation = filters.aiResult!.explanation;
    expect(filters.aiResult!.usedAi, isFalse);
    expect(explanation, anyOf(contains('keyword match'), contains('關鍵字')));
    expect(find.text(explanation), findsOneWidget);
    // ListView.separated: n cards + n - 1 gaps (lazy, so count the delegate).
    final list = tester.widget<ListView>(find.byType(ListView));
    final items = list.childrenDelegate.estimatedChildCount ?? 0;
    expect((items + 1) ~/ 2, filters.aiResult!.placeIds.length);
    expect(find.byType(PlaceCard), findsWidgets);
  });
}
