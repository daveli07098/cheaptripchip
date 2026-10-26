/// AI trip planner data (see lib/services/trip_planner.dart and
/// lib/screens/trip_plan_screen.dart): a board's places arranged into days
/// of ordered stops. Pure data — no Flutter imports — so the planner and its
/// tests stay fast. Stored on [Board.tripPlan] (personal boards only).
library;

/// Rough part of the day a stop is suggested for. Declaration order is the
/// order of a day — the local fallback planner hands slots out along a
/// day's route in this order.
enum TimeSlot {
  morning('Morning', '🌅'),
  lunch('Lunch', '🍱'),
  afternoon('Afternoon', '☀️'),
  dinner('Dinner', '🍽️'),
  night('Night', '🌙');

  const TimeSlot(this.label, this.emoji);

  final String label;
  final String emoji;

  /// Lenient parse of [Enum.name] (case-insensitive); `null` for anything
  /// else so callers pick their own default.
  static TimeSlot? tryParse(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim().toLowerCase();
    for (final slot in values) {
      if (slot.name == value) return slot;
    }
    return null;
  }
}

/// How full each day is: [stopsPerDay] caps the stops a day gets.
enum TripPace {
  relaxed('Relaxed', 3),
  normal('Normal', 5),
  packed('Packed', 7);

  const TripPace(this.label, this.stopsPerDay);

  final String label;
  final int stopsPerDay;

  static TripPace parse(Object? raw) => values.firstWhere(
    (pace) => pace.name == raw,
    orElse: () => TripPace.normal,
  );
}

/// What the user asked for in the "Plan a trip" sheet.
class TripPlanOptions {
  const TripPlanOptions({
    this.days = 3,
    this.startDate,
    this.pace = TripPace.normal,
    this.startPoint = '',
    this.mustVisitOnly = false,
  });

  static const minDays = 1;
  static const maxDays = 14;

  /// Number of days, clamped to [minDays]..[maxDays] on parse.
  final int days;

  /// First day of the trip (date only); null when the user didn't say.
  final DateTime? startDate;

  final TripPace pace;

  /// Free-text start point (hotel, station); empty when not given.
  final String startPoint;

  /// Plan only favourited places ("must-visits"). When false, favourites
  /// still go first if not everything fits.
  final bool mustVisitOnly;

  /// Most stops the whole plan can hold.
  int get capacity => days * pace.stopsPerDay;

  Map<String, dynamic> toJson() => {
    'days': days,
    'startDate': startDate == null ? null : _dateOnly(startDate!),
    'pace': pace.name,
    'startPoint': startPoint,
    'mustVisitOnly': mustVisitOnly,
  };

  factory TripPlanOptions.fromJson(Map<String, dynamic> json) {
    final days = json['days'];
    final startDate = json['startDate'];
    return TripPlanOptions(
      days: days is num ? days.toInt().clamp(minDays, maxDays) : 3,
      startDate: startDate is String ? DateTime.tryParse(startDate) : null,
      pace: TripPace.parse(json['pace']),
      startPoint: json['startPoint'] is String
          ? json['startPoint'] as String
          : '',
      mustVisitOnly: json['mustVisitOnly'] == true,
    );
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// One stop: a place (by [Place.id]) at a [slot], with a short [reason].
class TripStop {
  const TripStop({required this.placeId, required this.slot, this.reason = ''});

  final String placeId;
  final TimeSlot slot;
  final String reason;

  TripStop copyWith({TimeSlot? slot, String? reason}) => TripStop(
    placeId: placeId,
    slot: slot ?? this.slot,
    reason: reason ?? this.reason,
  );

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'slot': slot.name,
    'reason': reason,
  };

  /// `null` for an entry without a place id.
  static TripStop? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['placeId'];
    if (id is! String || id.isEmpty) return null;
    return TripStop(
      placeId: id,
      slot: TimeSlot.tryParse(raw['slot']) ?? TimeSlot.afternoon,
      reason: raw['reason'] is String ? raw['reason'] as String : '',
    );
  }
}

/// Whether the plan came from AI or the on-device distance fallback.
enum TripPlanSource { ai, local }

/// A trip: [days] of ordered stops plus the [unplaced] place ids that didn't
/// fit ("Didn't fit"). Every place id appears at most once across both.
class TripPlan {
  const TripPlan({
    required this.days,
    this.unplaced = const [],
    this.options = const TripPlanOptions(),
    this.source = TripPlanSource.local,
  });

  final List<List<TripStop>> days;
  final List<String> unplaced;
  final TripPlanOptions options;
  final TripPlanSource source;

  int get stopCount => days.fold(0, (sum, day) => sum + day.length);

  /// Calendar date of day [index] (0-based), when a start date is set.
  DateTime? dateOf(int index) {
    final start = options.startDate;
    if (start == null) return null;
    return DateTime(start.year, start.month, start.day + index);
  }

  TripPlan _with({List<List<TripStop>>? days, List<String>? unplaced}) =>
      TripPlan(
        days: days ?? this.days,
        unplaced: unplaced ?? this.unplaced,
        options: options,
        source: source,
      );

  /// Moves stop [fromIndex] of day [fromDay] to position [toIndex] of day
  /// [toDay] (clamped to that day's length). Same-day moves use
  /// list-insert semantics on the list *after* removal. Out-of-range
  /// [fromDay]/[fromIndex]/[toDay] return this plan unchanged.
  TripPlan moveStop({
    required int fromDay,
    required int fromIndex,
    required int toDay,
    required int toIndex,
  }) {
    if (fromDay < 0 || fromDay >= days.length) return this;
    if (toDay < 0 || toDay >= days.length) return this;
    if (fromIndex < 0 || fromIndex >= days[fromDay].length) return this;
    final updated = [
      for (final day in days) [...day],
    ];
    final stop = updated[fromDay].removeAt(fromIndex);
    updated[toDay].insert(toIndex.clamp(0, updated[toDay].length), stop);
    return _with(days: updated);
  }

  /// Takes stop [index] of day [dayIndex] off the plan into [unplaced].
  TripPlan removeStop(int dayIndex, int index) {
    if (dayIndex < 0 || dayIndex >= days.length) return this;
    if (index < 0 || index >= days[dayIndex].length) return this;
    final updated = [
      for (final day in days) [...day],
    ];
    final stop = updated[dayIndex].removeAt(index);
    return _with(days: updated, unplaced: [...unplaced, stop.placeId]);
  }

  /// Puts unplaced [placeId] at the end of day [dayIndex].
  TripPlan addToDay(String placeId, int dayIndex, {TimeSlot? slot}) {
    if (dayIndex < 0 || dayIndex >= days.length) return this;
    if (!unplaced.contains(placeId)) return this;
    final updated = [
      for (final day in days) [...day],
    ];
    updated[dayIndex].add(
      TripStop(
        placeId: placeId,
        slot: slot ?? (updated[dayIndex].lastOrNull?.slot ?? TimeSlot.morning),
      ),
    );
    return _with(
      days: updated,
      unplaced: [
        for (final id in unplaced)
          if (id != placeId) id,
      ],
    );
  }

  /// This plan against the board's current places: stops whose place is
  /// gone are dropped, duplicates removed, and any [placeIds] the plan
  /// doesn't mention land in [unplaced] — so a saved plan never shows a
  /// deleted place or hides a newly added one.
  TripPlan reconciledWith(Iterable<String> placeIds) {
    final valid = placeIds.toSet();
    final seen = <String>{};
    final updated = [
      for (final day in days)
        [
          for (final stop in day)
            if (valid.contains(stop.placeId) && seen.add(stop.placeId)) stop,
        ],
    ];
    final rest = [
      for (final id in unplaced)
        if (valid.contains(id) && seen.add(id)) id,
      for (final id in valid)
        if (seen.add(id)) id,
    ];
    return _with(days: updated, unplaced: rest);
  }

  Map<String, dynamic> toJson() => {
    'days': [
      for (final day in days) {'stops': day.map((s) => s.toJson()).toList()},
    ],
    'unplaced': unplaced,
    'options': options.toJson(),
    'source': source.name,
  };

  /// Lenient parse counterpart to [toJson]; malformed stops are skipped.
  /// `null` when [raw] isn't a map.
  static TripPlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final daysJson = raw['days'];
    final optionsJson = raw['options'];
    return TripPlan(
      days: [
        if (daysJson is List)
          for (final day in daysJson)
            [
              if (day is Map && day['stops'] is List)
                for (final stop in day['stops'] as List)
                  ?TripStop.fromJson(stop),
            ],
      ],
      unplaced: [
        if (raw['unplaced'] is List)
          for (final id in raw['unplaced'] as List)
            if (id is String) id,
      ],
      options: optionsJson is Map
          ? TripPlanOptions.fromJson(Map<String, dynamic>.from(optionsJson))
          : const TripPlanOptions(),
      source: raw['source'] == TripPlanSource.ai.name
          ? TripPlanSource.ai
          : TripPlanSource.local,
    );
  }
}
