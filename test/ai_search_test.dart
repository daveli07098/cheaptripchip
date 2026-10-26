import 'dart:async';

import 'package:cheaptripchip/data/map_filter.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_details.dart';
import 'package:cheaptripchip/services/ai_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(
  String id, {
  String name = '',
  PlaceCategory category = PlaceCategory.restaurant,
  RestaurantType? type,
  String region = 'Tokyo',
  String area = '',
  int? myScore,
  bool fav = false,
  String hours = '',
  PlaceDetails? details,
  LatLng location = const LatLng(35.68, 139.76),
}) => Place(
  id: id,
  name: name.isEmpty ? 'Place $id' : name,
  areaLabel: area,
  region: region,
  category: category,
  location: location,
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: hours,
  sourceHandle: '',
  sourcePlatform: SourcePlatform.googleMyMaps,
  restaurantType: type,
  myScore: myScore,
  isFavorite: fav,
  details: details,
);

PlaceDetails _details({int? price, List<String> tags = const []}) =>
    PlaceDetails(priceLevel: price, tags: tags, enrichedAt: DateTime(2026));

final _places = [
  _place(
    'ramen-cheap',
    type: RestaurantType.ramen,
    details: _details(price: 1),
  ),
  _place(
    'ramen-pricey',
    type: RestaurantType.ramen,
    myScore: 9,
    details: _details(price: 4),
  ),
  _place('cafe-9', category: PlaceCategory.cafe, myScore: 9),
  _place('cafe-5', category: PlaceCategory.cafe, myScore: 5, fav: true),
  _place(
    'izakaya-late',
    type: RestaurantType.izakaya,
    hours: '18:00–02:00',
    region: 'Osaka',
    area: 'Namba',
  ),
  _place('temple', category: PlaceCategory.sightseeing, name: 'Senso-ji'),
];

List<String> _ids(String q, {LatLng? near}) =>
    localAskSearch(q, _places, near: near).placeIds;

void main() {
  group('looksLikeQuestion', () {
    test('questions and intents ask; names and areas search', () {
      for (final q in [
        'where should I eat tonight?',
        'cheap ramen',
        'cafés I rated 8+',
        'late night food',
        '還未去過嘅',
        '附近有咩食',
        'show me sushi',
        'ramen spots in tokyo',
      ]) {
        expect(looksLikeQuestion(q), isTrue, reason: q);
      }
      for (final q in ['Gogo', 'ramen', '池袋', 'zzz-no-such-place', '']) {
        expect(looksLikeQuestion(q), isFalse, reason: q);
      }
    });
  });

  group('parseAskResponse', () {
    test('drops unknown and duplicate ids, keeps rank order', () {
      final r = parseAskResponse(
        {
          'placeIds': ['cafe-9', 'ghost', 'temple', 'cafe-9', 42],
          'explanation': '  Two picks  ',
        },
        question: 'q',
        places: _places,
      )!;
      expect(r.placeIds, ['cafe-9', 'temple']);
      expect(r.explanation, 'Two picks');
      expect(r.usedAi, isTrue);
    });

    test('a structured filter fills in when no ids came back', () {
      final r = parseAskResponse(
        {
          'placeIds': <String>[],
          'filter': {'category': 'cafe', 'minScore': 8, 'bogus': 1},
        },
        question: '我評過8分以上嘅café',
        places: _places,
      )!;
      expect(r.placeIds, ['cafe-9']);
      expect(r.filter!.category, PlaceCategory.cafe);
      expect(r.explanation, '找到 1 個地方', reason: 'default, in 中文');
    });

    test('invalid filter values are ignored', () {
      expect(
        AskFilter.fromJson({
          'category': 'spaceship',
          'minScore': 99,
          'maxPriceLevel': 'cheap',
        }),
        isNull,
      );
    });

    test('an answer with neither ids nor filter is unusable', () {
      expect(parseAskResponse({}, question: 'q', places: _places), isNull);
    });
  });

  group('localAskSearch', () {
    test('sub-type + cheap (soft) narrows to the cheap ramen', () {
      expect(_ids('cheap ramen'), ['ramen-cheap']);
      expect(_ids('平價 拉麵'), ['ramen-cheap']);
      expect(_ids('安い ラーメン'), ['ramen-cheap']);
    });

    test('cheap is ignored when no candidate has a price', () {
      expect(_ids('cheap izakaya'), ['izakaya-late']);
    });

    test('rated N+ with a category', () {
      expect(_ids('cafés I rated 8+'), ['cafe-9']);
      expect(_ids('8分以上 咖啡'), ['cafe-9']);
    });

    test('late night food', () {
      expect(_ids('late night food'), ['izakaya-late']);
      expect(_ids('宵夜'), ['izakaya-late']);
    });

    test('not visited / favourites / area', () {
      expect(_ids('還未去過嘅'), ['ramen-cheap', 'izakaya-late', 'temple']);
      expect(_ids('my favourites'), ['cafe-5']);
      expect(_ids('food in osaka'), ['izakaya-late']);
    });

    test('leftover words match names; nonsense matches nothing', () {
      expect(_ids('where is senso-ji'), ['temple']);
      expect(_ids('show me zzzq'), isEmpty);
    });

    test('near ranks by distance from the given centre', () {
      final osaka = const LatLng(34.67, 135.50);
      final near = localAskSearch('nearby', [
        ..._places.take(2),
        _place('osaka-1', location: osaka),
      ], near: osaka);
      expect(near.placeIds.first, 'osaka-1');
      expect(near.explanation, contains('map centre'));
    });

    test('explanation follows the question language', () {
      expect(
        localAskSearch('cheap ramen', _places).explanation,
        contains('Found 1 place'),
      );
      expect(localAskSearch('拉麵', _places).explanation, contains('找到'));
    });
  });

  group('suggestions', () {
    test('only offered when the user has matching places', () {
      final s = askSuggestionsFor(_places);
      expect(s, contains('cheap ramen'));
      expect(s, contains('cafés I rated 8+'));
      expect(s, contains('late night food'));
      expect(s, contains('還未去過嘅'));
      expect(s.length, lessThanOrEqualTo(5));
      for (final q in s) {
        expect(localAskSearch(q, _places).placeIds, isNotEmpty, reason: q);
      }
      expect(
        askSuggestionsFor([_place('a', category: PlaceCategory.shopping)]),
        isNot(contains('late night food')),
      );
    });
  });

  group('AiSearch', () {
    test('sends a compact index and validates the answer', () async {
      String? prompt;
      final ai = AiSearch(
        ask: (p) async {
          prompt = p;
          return {
            'placeIds': ['p3', 'nope'],
            'explanation': 'Coffee',
          };
        },
      );
      final r = await ai.ask(
        'where to get coffee near me?',
        places: MockData.places,
        boards: BoardIndex.from(places: MockData.places),
        near: const LatLng(35.68, 139.76),
      );
      expect(r.placeIds, ['p3']);
      expect(r.usedAi, isTrue);
      expect(prompt, contains('p3|Koffee Mameya|cafe|'));
      expect(prompt, contains('km'));
      expect(prompt, contains('map the user is looking at'));
    });

    test('caps the index and keeps keyword matches in it', () {
      final many = [
        for (var i = 0; i < 400; i++)
          _place('x$i', category: PlaceCategory.shopping),
        _place('needle', type: RestaurantType.ramen),
      ];
      final picked = prefilterForAsk('ramen please', many);
      expect(picked.length, kAskIndexCap);
      expect(picked.first.id, 'needle');
    });

    test('falls back to keywords when AI fails or is slow', () async {
      final failing = AiSearch(ask: (_) async => throw Exception('offline'));
      final r = await failing.ask('cheap ramen', places: _places);
      expect(r.usedAi, isFalse);
      expect(r.placeIds, ['ramen-cheap']);
      expect(r.explanation, contains('AI unavailable'));

      final slow = AiSearch(
        ask: (_) => Completer<Map<String, dynamic>>().future,
        timeout: const Duration(milliseconds: 10),
      );
      expect((await slow.ask('cheap ramen', places: _places)).usedAi, isFalse);
    });

    test('unconfigured skips AI entirely', () async {
      var called = false;
      final ai = AiSearch(
        ask: (_) async {
          called = true;
          return {};
        },
        configured: false,
      );
      final r = await ai.ask('cheap ramen', places: _places);
      expect(called, isFalse);
      expect(r.placeIds, ['ramen-cheap']);
    });
  });
}
