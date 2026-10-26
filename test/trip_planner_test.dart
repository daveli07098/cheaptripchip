import 'dart:convert';

import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_details.dart';
import 'package:cheaptripchip/models/trip_plan.dart';
import 'package:cheaptripchip/services/trip_planner.dart';
import 'package:cheaptripchip/services/trip_share.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(
  String id, {
  double lat = 35.0,
  double lng = 139.0,
  PlaceCategory category = PlaceCategory.sightseeing,
  bool favourite = false,
  String hours = '',
}) => Place(
  id: id,
  name: 'Place $id',
  areaLabel: '',
  region: '',
  category: category,
  location: LatLng(lat, lng),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: hours,
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
  isFavorite: favourite,
);

/// Two tight groups ~15 km apart (west a1..a3, east b1..b3), interleaved
/// in board order so clustering — not input order — must split them.
final _twoAreas = [
  _place('a1', lat: 35.680, lng: 139.700),
  _place('b1', lat: 35.680, lng: 139.860),
  _place('a2', lat: 35.682, lng: 139.702),
  _place('b2', lat: 35.682, lng: 139.862),
  _place('a3', lat: 35.684, lng: 139.704),
  _place('b3', lat: 35.684, lng: 139.864),
];

List<String> _ids(List<TripStop> day) => [for (final s in day) s.placeId];

void main() {
  group('TripPlanner.fromAiJson', () {
    const options = TripPlanOptions(days: 2);
    final pool = [_place('p1'), _place('p2'), _place('p3'), _place('p4')];

    test('drops unknown ids and repeats; lists the rest as unplaced', () {
      final plan = TripPlanner.fromAiJson(
        {
          'days': [
            {
              'stops': [
                {'id': 'p1', 'slot': 'morning', 'why': 'Coffee first'},
                {'id': 'ghost', 'slot': 'lunch'},
                {'id': 'p1', 'slot': 'dinner'},
                {'id': 'p2', 'slot': 'LUNCH', 'reason': 'Nearby'},
              ],
            },
            {
              'stops': [
                {'id': 'p2', 'slot': 'night'},
                {'placeId': 'p3', 'slot': 'bogus'},
              ],
            },
            {
              'stops': [
                {'id': 'p4', 'slot': 'morning'},
              ],
            },
          ],
        },
        pool,
        options,
      );

      expect(plan.days, hasLength(2));
      expect(_ids(plan.days[0]), ['p1', 'p2']);
      expect(plan.days[0][0].reason, 'Coffee first');
      expect(plan.days[0][1].slot, TimeSlot.lunch);
      expect(plan.days[0][1].reason, 'Nearby');
      // Unknown slot inherits the previous slot (none → morning).
      expect(_ids(plan.days[1]), ['p3']);
      expect(plan.days[1][0].slot, TimeSlot.morning);
      // p4 was only on the ignored third day.
      expect(plan.unplaced, ['p4']);
      expect(plan.source, TripPlanSource.ai);
    });

    test('pads missing days and survives garbage', () {
      final plan = TripPlanner.fromAiJson({'days': 'nope'}, pool, options);
      expect(plan.days, [isEmpty, isEmpty]);
      expect(plan.unplaced, ['p1', 'p2', 'p3', 'p4']);
    });
  });

  group('TripPlanner.plan', () {
    test('uses AI when it places stops', () async {
      String? prompt;
      final planner = TripPlanner(
        extractJson: (p) async {
          prompt = p;
          return {
            'days': [
              {
                'stops': [
                  {'id': 'a1', 'slot': 'morning', 'why': 'Start here'},
                ],
              },
            ],
          };
        },
      );
      final plan = await planner.plan([
        _place('a1', hours: 'Mon closed'),
        _place('a2'),
      ], const TripPlanOptions(days: 1, startPoint: 'Hotel Gracery'));
      expect(plan.source, TripPlanSource.ai);
      expect(_ids(plan.days.single), ['a1']);
      expect(plan.unplaced, ['a2']);
      expect(prompt, contains('Mon closed'));
      expect(prompt, contains('Hotel Gracery'));
    });

    test('prompt prefers enriched opening hours', () {
      final place = _place('x', hours: 'old hours').copyWith(
        details: PlaceDetails(
          openingHours: 'Tue-Sun 11:00-21:00',
          enrichedAt: DateTime(2026),
        ),
      );
      final prompt = TripPlanner.buildPrompt([place], const TripPlanOptions());
      expect(prompt, contains('Tue-Sun 11:00-21:00'));
      expect(prompt, isNot(contains('old hours')));
    });

    test('falls back to the local plan when AI throws', () async {
      final planner = TripPlanner(extractJson: (_) async => throw 'down');
      final plan = await planner.plan(
        _twoAreas,
        const TripPlanOptions(days: 2),
      );
      expect(plan.source, TripPlanSource.local);
      expect(plan.stopCount, 6);
    });

    test('falls back when AI places nothing', () async {
      final planner = TripPlanner(
        extractJson: (_) async => {
          'days': [
            {
              'stops': [
                {'id': 'unknown'},
              ],
            },
          ],
        },
      );
      final plan = await planner.plan(
        _twoAreas,
        const TripPlanOptions(days: 2),
      );
      expect(plan.source, TripPlanSource.local);
    });
  });

  group('TripPlanner.localPlan', () {
    test('clusters by area into days and uses each place once', () {
      final plan = TripPlanner.localPlan(
        _twoAreas,
        const TripPlanOptions(days: 2),
      );
      expect(plan.days, hasLength(2));
      final groups = [for (final day in plan.days) _ids(day).toSet()];
      expect(
        groups,
        containsAll([
          {'a1', 'a2', 'a3'},
          {'b1', 'b2', 'b3'},
        ]),
      );
      // Day 1 holds the top-priority (first) place.
      expect(groups.first, contains('a1'));
      // Nearest-neighbour order walks the line end to end.
      expect(
        _ids(plan.days.first),
        anyOf(equals(['a1', 'a2', 'a3']), equals(['a3', 'a2', 'a1'])),
      );
      expect(plan.unplaced, isEmpty);
    });

    test('is deterministic', () {
      const options = TripPlanOptions(days: 3, pace: TripPace.relaxed);
      final a = TripPlanner.localPlan(_twoAreas, options);
      final b = TripPlanner.localPlan(_twoAreas, options);
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    });

    test('honours capacity; favourites first; overflow is unplaced', () {
      final places = [
        for (var i = 0; i < 6; i++) _place('p$i', lat: 35 + i * 0.001),
        _place('fav', lat: 36, favourite: true),
      ];
      final plan = TripPlanner.localPlan(
        places,
        const TripPlanOptions(days: 1, pace: TripPace.relaxed),
      );
      expect(plan.days.single, hasLength(TripPace.relaxed.stopsPerDay));
      expect(_ids(plan.days.single), contains('fav'));
      expect(plan.unplaced, hasLength(4));
      final all = [..._ids(plan.days.single), ...plan.unplaced];
      expect(all.toSet(), hasLength(7));
    });

    test('more days than places leaves the extra days free', () {
      final plan = TripPlanner.localPlan([
        _place('x'),
      ], const TripPlanOptions(days: 3));
      expect(plan.days, hasLength(3));
      expect(_ids(plan.days.first), ['x']);
      expect(plan.days[1], isEmpty);
    });

    test('must-visits only plans favourites', () {
      final plan = TripPlanner.localPlan([
        _place('a'),
        _place('b', favourite: true),
      ], const TripPlanOptions(days: 1, mustVisitOnly: true));
      expect(_ids(plan.days.single), ['b']);
      expect(plan.unplaced, isEmpty);
    });

    test('food lands at a meal and nightlife at night', () {
      final plan = TripPlanner.localPlan([
        _place('ramen', category: PlaceCategory.food),
        _place('bar', lat: 35.001, category: PlaceCategory.nightlife),
      ], const TripPlanOptions(days: 1));
      final slots = {for (final s in plan.days.single) s.placeId: s.slot};
      expect(slots['ramen'], anyOf(TimeSlot.lunch, TimeSlot.dinner));
      expect(slots['bar'], TimeSlot.night);
    });
  });

  group('TripPlan', () {
    final plan = TripPlan(
      days: const [
        [
          TripStop(placeId: 'a', slot: TimeSlot.morning, reason: 'r'),
          TripStop(placeId: 'b', slot: TimeSlot.lunch),
        ],
        [TripStop(placeId: 'c', slot: TimeSlot.dinner)],
      ],
      unplaced: const ['d'],
      options: TripPlanOptions(
        days: 2,
        startDate: DateTime(2026, 11, 2),
        pace: TripPace.packed,
        startPoint: 'Shinjuku Station',
      ),
      source: TripPlanSource.ai,
    );

    test('JSON round-trips, also through Board', () {
      final board = Board(
        id: 'b1',
        name: 'Tokyo',
        emoji: '🗼',
        sections: const [],
        tripPlan: plan,
      );
      final decoded = Board.fromJson(
        jsonDecode(jsonEncode(board.toJson())) as Map<String, dynamic>,
      );
      expect(jsonEncode(decoded.tripPlan!.toJson()), jsonEncode(plan.toJson()));
      expect(decoded.tripPlan!.options.startDate, DateTime(2026, 11, 2));
      expect(board.copyWith(name: 'x').tripPlan, isNotNull);
      expect(board.copyWith(clearTripPlan: true).tripPlan, isNull);
      expect(Board.fromJson({'id': 'x'}).tripPlan, isNull);
    });

    test('moveStop within and across days', () {
      final within = plan.moveStop(
        fromDay: 0,
        fromIndex: 0,
        toDay: 0,
        toIndex: 1,
      );
      expect(_ids(within.days[0]), ['b', 'a']);
      final across = plan.moveStop(
        fromDay: 0,
        fromIndex: 1,
        toDay: 1,
        toIndex: 0,
      );
      expect(_ids(across.days[0]), ['a']);
      expect(_ids(across.days[1]), ['b', 'c']);
    });

    test('reconciledWith drops gone places and adds new ones', () {
      final r = plan.reconciledWith(['a', 'c', 'd', 'e']);
      expect(_ids(r.days[0]), ['a']);
      expect(r.unplaced, ['d', 'e']);
    });

    test('share text lists days and leftovers', () {
      final byId = {
        for (final id in ['a', 'b', 'c', 'd']) id: _place(id),
      };
      final text = TripPlanner.shareText('Tokyo', plan, byId);
      expect(text, contains('Day 1 (Mon 2/11)'));
      expect(text, contains('1. Morning: Place a'));
      expect(text, contains("Didn't fit: Place d"));
    });
  });

  group('TripShare.googleMapsRouteUrls', () {
    List<Place> places(int n) => [for (var i = 0; i < n; i++) _place('s$i')];

    test('empty and single place', () {
      expect(TripShare.googleMapsRouteUrls(const []), isEmpty);
      final single = TripShare.googleMapsRouteUrls(places(1));
      expect(single.single.path, '/maps/search/');
      final withOrigin = TripShare.googleMapsRouteUrls(
        places(1),
        origin: 'Hotel',
      );
      expect(withOrigin.single.queryParameters['origin'], 'Hotel');
    });

    test('11 points fit one link', () {
      final urls = TripShare.googleMapsRouteUrls(places(11));
      expect(urls, hasLength(1));
      expect(
        urls.single.queryParameters['waypoints']!.split('|'),
        hasLength(9),
      );
    });

    test('longer routes split into chained links within the limit', () {
      final urls = TripShare.googleMapsRouteUrls(places(14), origin: 'Hotel');
      // 15 points: 11 in the first link, then 5 (overlapping by one).
      expect(urls, hasLength(2));
      expect(urls[0].queryParameters['origin'], 'Hotel');
      expect(urls[0].queryParameters['destination'], 'Place s9');
      expect(urls[1].queryParameters['origin'], 'Place s9');
      expect(urls[1].queryParameters['destination'], 'Place s13');
      for (final url in urls) {
        final waypoints = url.queryParameters['waypoints'];
        expect(
          waypoints == null ? 0 : waypoints.split('|').length,
          lessThanOrEqualTo(TripShare.maxRouteWaypoints),
        );
      }
    });
  });
}
