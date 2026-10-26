import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_details.dart';
import 'package:cheaptripchip/services/place_enricher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(
  String id, {
  String name = 'Ichiran',
  String caption = '一蘭的拉麵超好吃！24小時營業',
  PlaceDetails? details,
}) => Place(
  id: id,
  name: name,
  areaLabel: 'Shibuya',
  region: 'Tokyo',
  category: PlaceCategory.restaurant,
  location: const LatLng(35.66, 139.7),
  descriptionEn: '',
  originalCaption: caption,
  address: '渋谷区宇田川町13-7',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
  restaurantType: RestaurantType.ramen,
  countryCode: 'JP',
  details: details,
);

const _answer = <String, dynamic>{
  'mustTry': ['tonkotsu ramen', 'kae-dama', 'a', 'b', 'c', 'd'],
  'priceLevel': 2,
  'nativeName': '一蘭 渋谷店',
  'tags': ['Late-Night', 'solo-friendly'],
  'openingHours': 'Daily 24h',
  'summaryEn': 'Solo-booth tonkotsu ramen.',
  'summaryZh': null,
  'captionEn': 'Ichiran ramen is great! Open 24h',
  'captionZh': '一蘭的拉麵超好吃！24小時營業',
};

/// An enricher on a fake clock (advanced only by `wait`), an in-memory
/// place list and a recording fake AI.
class _Harness {
  _Harness(
    List<Place> places, {
    Map<String, dynamic> Function(String prompt)? respond,
    int maxPerSession = 150,
    int flushSize = 10,
  }) : places = ValueNotifier(places) {
    enricher = PlaceEnricher(
      extractJson: (prompt) async {
        prompts.add(prompt);
        requestTimes.add(now);
        return (respond ?? (_) => _answer)(prompt);
      },
      isConfigured: () => configured,
      places: this.places,
      applyUpdates: (details, {onlyMissing = false}) async {
        writes.add(Map.of(details));
        var changed = 0;
        this.places.value = [
          for (final p in this.places.value)
            if (details[p.id] case final d?
                when !(onlyMissing && p.details != null))
              (() {
                changed++;
                return p.copyWith(details: d);
              })()
            else
              p,
        ];
        return changed;
      },
      ready: () async {},
      now: () => now,
      wait: (d) async => now = now.add(d),
      maxPerSession: maxPerSession,
      flushSize: flushSize,
    );
  }

  final ValueNotifier<List<Place>> places;
  late final PlaceEnricher enricher;
  DateTime now = DateTime.utc(2026, 10, 18);
  bool configured = true;
  final prompts = <String>[];
  final requestTimes = <DateTime>[];
  final writes = <Map<String, PlaceDetails>>[];

  Place byId(String id) => places.value.firstWhere((p) => p.id == id);
}

void main() {
  group('prompt and parse', () {
    test('prompt carries the place facts and the no-invention rules', () {
      final prompt = PlaceEnricher.buildPrompt(_place('a'));
      expect(prompt, contains('Name: Ichiran'));
      expect(prompt, contains('Category: Restaurant (Ramen)'));
      expect(prompt, contains('Area: Shibuya, Tokyo'));
      expect(prompt, contains('Country code: JP'));
      expect(prompt, contains('Address: 渋谷区宇田川町13-7'));
      expect(prompt, contains('一蘭的拉麵超好吃'));
      expect(prompt, contains('Use ONLY the caption'));
      expect(prompt, contains('set it to null'));
      for (final key in [
        'mustTry',
        'priceLevel',
        'nativeName',
        'tags',
        'openingHours',
        'summaryEn',
        'summaryZh',
        'captionEn',
        'captionZh',
      ]) {
        expect(prompt, contains('"$key"'));
      }
    });

    test('long captions are truncated', () {
      final prompt = PlaceEnricher.buildPrompt(
        _place('a', caption: 'x' * 10000),
      );
      expect(
        prompt,
        isNot(contains('x' * (PlaceEnricher.maxCaptionChars + 1))),
      );
    });

    test('enrich parses leniently and caps lists', () async {
      final h = _Harness([]);
      final details = await h.enricher.enrich(_place('a'));
      expect(h.prompts, hasLength(1));
      expect(details.mustTry, hasLength(5));
      expect(details.priceLevel, 2);
      expect(details.nativeName, '一蘭 渋谷店');
      expect(details.tags, ['late-night', 'solo-friendly']);
      expect(details.openingHours, 'Daily 24h');
      expect(details.summaryZh, isNull);
      expect(details.captionEn, startsWith('Ichiran'));
      expect(details.enrichedAt, h.now);
    });

    test('drops a native name equal to the name and translations of '
        'an empty caption', () {
      final details = PlaceEnricher.parse(
        {..._answer, 'nativeName': 'Ichiran', 'priceLevel': 'expensive'},
        place: _place('a', caption: ''),
        at: DateTime.utc(2026),
      );
      expect(details.nativeName, isNull);
      expect(details.priceLevel, isNull);
      expect(details.captionEn, isNull);
      expect(details.captionZh, isNull);
    });
  });

  group('background queue', () {
    test('enriches places without details, throttled to one per 2 s, '
        'and never overwrites existing details', () async {
      final existing = PlaceDetails(
        priceLevel: 4,
        enrichedAt: DateTime.utc(2020),
      );
      final h = _Harness([
        _place('a'),
        _place('b', details: existing),
        _place('c'),
        _place('d'),
      ]);
      await h.enricher.run();
      expect(h.prompts, hasLength(3));
      expect(h.prompts.any((p) => p.contains('Name: Ichiran')), isTrue);
      for (var i = 1; i < h.requestTimes.length; i++) {
        expect(
          h.requestTimes[i].difference(h.requestTimes[i - 1]),
          greaterThanOrEqualTo(const Duration(seconds: 2)),
        );
      }
      expect(h.byId('a').details!.priceLevel, 2);
      expect(h.byId('b').details, same(existing));
      expect(h.byId('c').details, isNotNull);
      expect(h.byId('d').details, isNotNull);
      // One batched write at the end (flushSize 10 not reached).
      expect(h.writes, hasLength(1));
      expect(h.writes.single.keys, unorderedEquals(['a', 'c', 'd']));
    });

    test('a manual refresh landing meanwhile wins over the queue', () async {
      final manual = PlaceDetails(
        priceLevel: 1,
        enrichedAt: DateTime.utc(2026),
      );
      late _Harness h;
      h = _Harness(
        [_place('a')],
        respond: (_) {
          // Simulate "Refresh details" finishing while the queue's request
          // for the same place is in flight.
          h.places.value = [h.byId('a').copyWith(details: manual)];
          return _answer;
        },
      );
      await h.enricher.run();
      expect(h.byId('a').details, same(manual));
    });

    test('flushes in batches of flushSize', () async {
      final h = _Harness([
        for (var i = 0; i < 5; i++) _place('p$i'),
      ], flushSize: 2);
      await h.enricher.run();
      expect(h.writes.map((w) => w.length), [2, 2, 1]);
    });

    test('stops at maxPerSession requests', () async {
      final h = _Harness([
        for (var i = 0; i < 5; i++) _place('p$i'),
      ], maxPerSession: 3);
      await h.enricher.run();
      expect(h.prompts, hasLength(3));
      expect(h.places.value.where((p) => p.details == null), hasLength(2));
      // A second run in the same session makes no more requests.
      await h.enricher.run();
      expect(h.prompts, hasLength(3));
    });

    test('gives up for the session after consecutive failures', () async {
      final h = _Harness([
        for (var i = 0; i < 6; i++) _place('p$i'),
      ], respond: (_) => throw Exception('SocketException: offline'));
      await h.enricher.run();
      expect(h.prompts, hasLength(3));
      expect(h.writes, isEmpty);
      expect(h.places.value.every((p) => p.details == null), isTrue);
    });

    test('skips everything when AI is not configured', () async {
      final h = _Harness([_place('a')])..configured = false;
      await h.enricher.run();
      expect(h.prompts, isEmpty);
      expect(h.enricher.isConfigured, isFalse);
    });

    test('skips nameless places', () async {
      final h = _Harness([_place('a', name: ' ')]);
      await h.enricher.run();
      expect(h.prompts, isEmpty);
    });

    test('refresh replaces existing details immediately', () async {
      final h = _Harness([
        _place('a', details: PlaceDetails(enrichedAt: DateTime.utc(2020))),
      ]);
      final details = await h.enricher.refresh(h.byId('a'));
      expect(details.priceLevel, 2);
      expect(h.byId('a').details!.priceLevel, 2);
      expect(h.enricher.requestCount, 0);
    });
  });
}
