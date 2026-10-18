import 'dart:async';

import 'package:cheaptripchip/data/map_filter.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_filter_controller.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/services/ai_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final places = MockData.places;

  PlaceFilterController withAnswer(List<String> ids) => PlaceFilterController(
    aiSearch: AiSearch(
      ask: (_) async => {'placeIds': ids, 'explanation': 'Picked for you'},
    ),
  );

  test('AI ids replace the word-by-word query match, in rank order', () {
    final filter = MapFilter(
      query: 'where should I get coffee?',
      aiPlaceIds: {'p3', 'p1'},
    );
    final visible = MapFilterCache().visibleFor(places, filter);
    expect(visible.map((p) => p.id), ['p3', 'p1']);
    expect(filter.activeCount, 0, reason: 'its own chip, not a chip filter');
  });

  test('AI results AND with the chip filters', () {
    final filter = MapFilter(
      aiPlaceIds: {'p3', 'p1'},
      category: PlaceCategory.cafe,
    );
    expect(MapFilterCache().visibleFor(places, filter).map((p) => p.id), [
      'p3',
    ]);
  });

  test('ask shows the answer; editing the question drops it', () async {
    final filters = withAnswer(['p3', 'ghost', 'p1']);
    addTearDown(filters.dispose);
    final result = await filters.ask('coffee near me?', places: places);
    expect(result!.placeIds, ['p3', 'p1']);
    expect(filters.search.text, 'coffee near me?');
    expect(filters.filter.aiPlaceIds, {'p3', 'p1'});
    expect(filters.aiResult!.explanation, 'Picked for you');
    expect(filters.asking, isFalse);

    filters.search.text = 'coffee near me';
    expect(filters.filter.hasAiResults, isFalse);
    expect(filters.aiResult, isNull);
    expect(filters.filter.query, 'coffee near me');
  });

  test(
    'clearAiResults drops results and question; clearFilters keeps them',
    () async {
      final filters = withAnswer(['p3']);
      addTearDown(filters.dispose);
      await filters.ask('best coffee?', places: places);
      filters
        ..setFavoritesOnly(true)
        ..clearFilters();
      expect(filters.filter.hasAiResults, isTrue);

      filters.clearAiResults();
      expect(filters.filter.hasAiResults, isFalse);
      expect(filters.aiResult, isNull);
      expect(filters.search.text, isEmpty);
    },
  );

  test('a superseded answer is discarded', () async {
    final pending = Completer<Map<String, dynamic>>();
    final filters = PlaceFilterController(
      aiSearch: AiSearch(ask: (_) => pending.future),
    );
    addTearDown(filters.dispose);
    final asked = filters.ask('best coffee?', places: places);
    expect(filters.asking, isTrue);
    filters.showAll();
    pending.complete({
      'placeIds': ['p3'],
    });
    expect(await asked, isNull);
    expect(filters.filter.hasAiResults, isFalse);
    expect(filters.asking, isFalse);
  });
}
