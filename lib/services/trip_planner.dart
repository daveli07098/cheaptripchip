import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../models/trip_plan.dart';
import 'ai_service.dart';

/// Runs a JSON prompt — [AiService.extractJson] in the app, a stub in
/// tests.
typedef JsonPrompt = Future<Map<String, dynamic>> Function(String prompt);

/// AI trip planner: arranges a board's places into [TripPlanOptions.days]
/// days of ordered stops. AI plans first (areas grouped, meals at meal
/// times, opening hours respected); its answer is validated against the
/// places actually sent. When AI is unavailable, errors, or places
/// nothing, [localPlan] clusters by distance on-device instead.
class TripPlanner {
  TripPlanner({JsonPrompt? extractJson}) : _extractJson = extractJson;

  final JsonPrompt? _extractJson;

  /// Extra places sent to AI beyond what fits, so it can pick the ones
  /// that suit the route. Kept small: [AiService] caps the response at
  /// 2048 tokens.
  static const _aiBuffer = 4;

  /// Longest [TripStop.reason] kept from the model.
  static const _maxReasonLength = 120;

  Future<TripPlan> plan(List<Place> places, TripPlanOptions options) async {
    final pool = candidatesFor(places, options);
    if (pool.isEmpty) return localPlan(places, options);
    try {
      final run = _extractJson ?? AiService().extractJson;
      final sent = pool.take(options.capacity + _aiBuffer).toList();
      final json = await run(buildPrompt(sent, options));
      final plan = fromAiJson(json, pool, options);
      if (plan.stopCount > 0) return plan;
      debugPrint('TripPlanner: AI placed no stops, using local plan');
    } catch (e) {
      debugPrint('TripPlanner: AI failed ($e), using local plan');
    }
    return localPlan(places, options);
  }

  /// The places a plan draws from, in priority order: favourites first,
  /// then the rest in board order; only favourites when
  /// [TripPlanOptions.mustVisitOnly] (all places if none are favourited).
  /// Duplicate ids keep their first occurrence.
  static List<Place> candidatesFor(
    List<Place> places,
    TripPlanOptions options,
  ) {
    final seen = <String>{};
    final unique = [
      for (final place in places)
        if (seen.add(place.id)) place,
    ];
    final favourites = unique.where((p) => p.isFavorite).toList();
    if (options.mustVisitOnly && favourites.isNotEmpty) return favourites;
    return [...favourites, ...unique.where((p) => !p.isFavorite)];
  }

  // ---------------------------------------------------------------------
  // AI
  // ---------------------------------------------------------------------

  static String buildPrompt(List<Place> places, TripPlanOptions options) {
    final start = options.startDate;
    final placesJson = jsonEncode([
      for (final p in places)
        {
          'id': p.id,
          'name': p.name,
          'type': p.restaurantType == null
              ? p.category.name
              : '${p.category.name}/${p.restaurantType!.name}',
          if (p.areaDisplay.isNotEmpty) 'area': p.areaDisplay,
          'lat': _round(p.location.latitude),
          'lng': _round(p.location.longitude),
          if (_hoursOf(p).isNotEmpty) 'hours': _hoursOf(p),
          if (p.isFavorite) 'mustVisit': true,
        },
    ]);
    return '''
You are a travel planner. Arrange these saved places into a ${options.days}-day trip.

Rules:
- At most ${options.pace.stopsPerDay} stops per day (${options.pace.label.toLowerCase()} pace). Use each place id at most once; it is fine to leave places out.
- Group each day by area so travel between stops is short, and order stops along a sensible walking route.
- Put restaurants and food places at lunch or dinner, cafes in the morning or afternoon, bars and nightlife at night.
- Respect opening hours ("hours") when given: never schedule a place when it is closed${start == null ? '' : ' (day 1 is ${_weekday(start)} ${options.toJson()['startDate']})'}.
- Prefer places marked mustVisit.
${options.startPoint.trim().isEmpty ? '' : '- Each day starts and ends near: ${options.startPoint.trim()}.\n'}- "slot" is one of: morning, lunch, afternoon, dinner, night. "why" is at most 10 words.

Places (JSON): $placesJson

Return ONLY JSON, exactly ${options.days} days, in this shape:
{"days":[{"stops":[{"id":"<place id>","slot":"morning","why":"<short reason>"}]}]}
''';
  }

  /// Validates the AI's answer against [pool]: unknown ids and repeats are
  /// dropped, days beyond [TripPlanOptions.days] are ignored (missing ones
  /// are empty), and every pool place not placed is listed in
  /// [TripPlan.unplaced] in pool order. A truncated/partial answer simply
  /// places fewer stops.
  static TripPlan fromAiJson(
    Map<String, dynamic> json,
    List<Place> pool,
    TripPlanOptions options,
  ) {
    final known = {for (final p in pool) p.id};
    final used = <String>{};
    final rawDays = json['days'] is List ? json['days'] as List : const [];
    final days = <List<TripStop>>[];
    for (var d = 0; d < options.days; d++) {
      final rawDay = d < rawDays.length ? rawDays[d] : null;
      final rawStops = rawDay is Map && rawDay['stops'] is List
          ? rawDay['stops'] as List
          : rawDay is List
          ? rawDay
          : const [];
      final stops = <TripStop>[];
      for (final raw in rawStops) {
        if (raw is! Map) continue;
        final id = (raw['id'] ?? raw['placeId'])?.toString();
        if (id == null || !known.contains(id) || !used.add(id)) continue;
        final reason = (raw['why'] ?? raw['reason'])?.toString().trim() ?? '';
        stops.add(
          TripStop(
            placeId: id,
            slot:
                TimeSlot.tryParse(raw['slot']) ??
                stops.lastOrNull?.slot ??
                TimeSlot.morning,
            reason: reason.length > _maxReasonLength
                ? '${reason.substring(0, _maxReasonLength - 1)}…'
                : reason,
          ),
        );
      }
      days.add(stops);
    }
    return TripPlan(
      days: days,
      unplaced: [
        for (final p in pool)
          if (!used.contains(p.id)) p.id,
      ],
      options: options,
      source: TripPlanSource.ai,
    );
  }

  // ---------------------------------------------------------------------
  // Local fallback
  // ---------------------------------------------------------------------

  static const _distance = Distance();

  /// Deterministic on-device plan: the first [TripPlanOptions.capacity]
  /// candidates are clustered by distance into up to
  /// [TripPlanOptions.days] days (each capped at the pace's stops/day),
  /// days are chained nearest-first, and each day is ordered
  /// nearest-neighbour from its outermost stop. Time slots follow the
  /// route; food and nightlife are nudged to meal times / night.
  static TripPlan localPlan(List<Place> places, TripPlanOptions options) {
    final pool = candidatesFor(places, options);
    final chosen = pool.take(options.capacity).toList();
    final k = math.min(options.days, chosen.length);
    final clusters = k == 0
        ? <List<Place>>[]
        : _cluster(chosen, k, options.pace.stopsPerDay);
    final orderedDays = _chainDays(clusters);

    final days = [
      for (final day in orderedDays) _stopsFor(_nearestNeighbour(day)),
      for (var i = orderedDays.length; i < options.days; i++) <TripStop>[],
    ];
    return TripPlan(
      days: days,
      unplaced: [for (final p in pool.skip(chosen.length)) p.id],
      options: options,
      source: TripPlanSource.local,
    );
  }

  static double _meters(LatLng a, LatLng b) =>
      _distance.as(LengthUnit.Meter, a, b);

  static LatLng _centroid(List<Place> places) {
    var lat = 0.0, lng = 0.0;
    for (final p in places) {
      lat += p.location.latitude;
      lng += p.location.longitude;
    }
    return LatLng(lat / places.length, lng / places.length);
  }

  /// Capacity-limited k-means: farthest-point seeding from the first
  /// (highest-priority) place, then a few rounds of assigning the closest
  /// (place, centre) pairs first while a centre has room. Ties break by
  /// input order, so the result is a pure function of the input.
  static List<List<Place>> _cluster(List<Place> places, int k, int cap) {
    final centres = <LatLng>[places.first.location];
    while (centres.length < k) {
      var best = 0;
      var bestDistance = -1.0;
      for (var i = 0; i < places.length; i++) {
        final nearest = centres
            .map((c) => _meters(c, places[i].location))
            .reduce(math.min);
        if (nearest > bestDistance) {
          bestDistance = nearest;
          best = i;
        }
      }
      centres.add(places[best].location);
    }

    var groups = <List<Place>>[];
    for (var round = 0; round < 6; round++) {
      final pairs =
          [
            for (var i = 0; i < places.length; i++)
              for (var c = 0; c < centres.length; c++)
                (i: i, c: c, d: _meters(places[i].location, centres[c])),
          ]..sort((a, b) {
            final byDistance = a.d.compareTo(b.d);
            if (byDistance != 0) return byDistance;
            final byPlace = a.i.compareTo(b.i);
            return byPlace != 0 ? byPlace : a.c.compareTo(b.c);
          });
      final assigned = List<int?>.filled(places.length, null);
      final sizes = List<int>.filled(centres.length, 0);
      for (final pair in pairs) {
        if (assigned[pair.i] != null || sizes[pair.c] >= cap) continue;
        assigned[pair.i] = pair.c;
        sizes[pair.c]++;
      }
      groups = [
        for (var c = 0; c < centres.length; c++)
          [
            for (var i = 0; i < places.length; i++)
              if (assigned[i] == c) places[i],
          ],
      ];
      for (var c = 0; c < centres.length; c++) {
        if (groups[c].isNotEmpty) centres[c] = _centroid(groups[c]);
      }
    }
    return groups.where((g) => g.isNotEmpty).toList();
  }

  /// Day order: start with the cluster holding the top-priority place, then
  /// always the nearest remaining cluster centre.
  static List<List<Place>> _chainDays(List<List<Place>> clusters) {
    if (clusters.isEmpty) return clusters;
    final remaining = [...clusters];
    final ordered = [remaining.removeAt(0)];
    while (remaining.isNotEmpty) {
      final from = _centroid(ordered.last);
      var best = 0;
      for (var i = 1; i < remaining.length; i++) {
        if (_meters(from, _centroid(remaining[i])) <
            _meters(from, _centroid(remaining[best]))) {
          best = i;
        }
      }
      ordered.add(remaining.removeAt(best));
    }
    return ordered;
  }

  /// Nearest-neighbour route starting from the stop farthest from the
  /// day's centre (an end of the area), so the walk sweeps across it.
  static List<Place> _nearestNeighbour(List<Place> day) {
    if (day.length < 2) return day;
    final centre = _centroid(day);
    final remaining = [...day];
    var start = 0;
    for (var i = 1; i < remaining.length; i++) {
      if (_meters(remaining[i].location, centre) >
          _meters(remaining[start].location, centre)) {
        start = i;
      }
    }
    final route = [remaining.removeAt(start)];
    while (remaining.isNotEmpty) {
      final from = route.last.location;
      var best = 0;
      for (var i = 1; i < remaining.length; i++) {
        if (_meters(from, remaining[i].location) <
            _meters(from, remaining[best].location)) {
          best = i;
        }
      }
      route.add(remaining.removeAt(best));
    }
    return route;
  }

  /// A day's shape, spread over however many stops it has.
  static const _dayTemplate = [
    TimeSlot.morning,
    TimeSlot.morning,
    TimeSlot.lunch,
    TimeSlot.afternoon,
    TimeSlot.afternoon,
    TimeSlot.dinner,
    TimeSlot.night,
  ];

  static List<TripStop> _stopsFor(List<Place> route) {
    final stops = <TripStop>[];
    for (var i = 0; i < route.length; i++) {
      final place = route[i];
      final position = route.length == 1
          ? 0
          : (i * (_dayTemplate.length - 1) / (route.length - 1)).round();
      var slot = _nudge(_dayTemplate[position], place.category);
      // Never go back in time along the route.
      final previous = stops.lastOrNull?.slot;
      if (previous != null && slot.index < previous.index) slot = previous;
      final reason = i == 0
          ? (place.areaDisplay.isEmpty
                ? 'Start of the day'
                : 'Start the day in ${place.areaDisplay}')
          : '${_formatDistance(_meters(route[i - 1].location, place.location))} '
                'from the previous stop';
      stops.add(TripStop(placeId: place.id, slot: slot, reason: reason));
    }
    return stops;
  }

  static TimeSlot _nudge(TimeSlot slot, PlaceCategory category) {
    switch (category) {
      case PlaceCategory.nightlife:
        return TimeSlot.night;
      case PlaceCategory.restaurant || PlaceCategory.food:
        return switch (slot) {
          TimeSlot.morning => TimeSlot.lunch,
          TimeSlot.afternoon => TimeSlot.dinner,
          _ => slot,
        };
      default:
        return slot;
    }
  }

  static String _formatDistance(double meters) => meters < 1000
      ? '${(meters / 50).round() * 50} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  // ---------------------------------------------------------------------
  // Share text
  // ---------------------------------------------------------------------

  /// Plain-text itinerary for the system share sheet.
  static String shareText(
    String title,
    TripPlan plan,
    Map<String, Place> placesById,
  ) {
    final buffer = StringBuffer('$title — ${plan.days.length}-day plan\n');
    for (var d = 0; d < plan.days.length; d++) {
      final date = plan.dateOf(d);
      buffer.writeln(
        '\nDay ${d + 1}${date == null ? '' : ' (${_weekday(date)} ${date.day}/${date.month})'}',
      );
      final day = plan.days[d];
      if (day.isEmpty) buffer.writeln('  Free day');
      for (var i = 0; i < day.length; i++) {
        final place = placesById[day[i].placeId];
        if (place == null) continue;
        final area = place.areaDisplay.isEmpty ? '' : ' — ${place.areaDisplay}';
        buffer.writeln('  ${i + 1}. ${day[i].slot.label}: ${place.name}$area');
      }
    }
    final unplaced = [for (final id in plan.unplaced) ?placesById[id]?.name];
    if (unplaced.isNotEmpty) {
      buffer.writeln("\nDidn't fit: ${unplaced.join(', ')}");
    }
    return buffer.toString().trimRight();
  }

  /// Opening hours for the prompt: the enriched `details.openingHours`
  /// when known, else the free-form [Place.hours].
  static String _hoursOf(Place place) {
    final enriched = place.details?.openingHours?.trim() ?? '';
    final hours = enriched.isNotEmpty ? enriched : place.hours.trim();
    return hours.length > 80 ? hours.substring(0, 80) : hours;
  }

  static double _round(double v) => (v * 10000).round() / 10000;

  static String _weekday(DateTime d) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}
