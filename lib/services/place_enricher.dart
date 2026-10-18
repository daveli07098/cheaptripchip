import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/place_store.dart';
import '../models/place.dart';
import '../models/place_details.dart';
import 'gemini_service.dart';

/// Auto-fills [Place.details] (must-try, price level, tags, opening hours,
/// native name, summaries and caption translations) with one Gemini JSON
/// call per place — see [enrich].
///
/// Runs in the background like AreaResolver (lib/services/area_resolver.dart):
/// after launch / whenever [PlaceStore.places] changes (e.g. a new find was
/// saved) and the app has been quiet for [startDelay], it walks every place
/// whose details are still null, strictly one request at a time with at
/// least [minInterval] (2 s) between requests, and at most
/// [maxPerSession] requests per app session so a big backfill spreads over
/// several launches. Skipped entirely when Gemini isn't configured; gives up
/// for the session after [maxConsecutiveFailures] failures in a row
/// (offline, quota), retried on the next app resume.
///
/// Results go through [PlaceStore.updateDetails] in batches (every
/// [flushSize] results or [flushInterval], and at the end) with
/// `onlyMissing: true`, so a manual "Refresh details" that landed meanwhile
/// wins. Only the details object is ever written — category, type and the
/// user's notes are untouched.
class PlaceEnricher with WidgetsBindingObserver {
  PlaceEnricher({
    Future<Map<String, dynamic>> Function(String prompt)? extractJson,
    bool Function()? isConfigured,
    ValueListenable<List<Place>>? places,
    Future<int> Function(Map<String, PlaceDetails> details, {bool onlyMissing})?
    applyUpdates,
    Future<void> Function()? ready,
    DateTime Function()? now,
    Future<void> Function(Duration duration)? wait,
    this.minInterval = const Duration(seconds: 2),
    this.maxPerSession = 150,
    this.flushSize = 10,
    this.flushInterval = const Duration(seconds: 20),
    this.maxConsecutiveFailures = 3,
    this.startDelay = const Duration(seconds: 8),
  }) : _extractOverride = extractJson,
       _configuredOverride = isConfigured,
       _placesOverride = places,
       _applyOverride = applyUpdates,
       _readyOverride = ready,
       _now = now ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed;

  /// The app-wide enricher (started from main.dart, used by the detail
  /// sheet's "Refresh details"). Not final so widget tests can swap in one
  /// with a fake Gemini.
  static PlaceEnricher instance = PlaceEnricher();

  final Future<Map<String, dynamic>> Function(String)? _extractOverride;
  final bool Function()? _configuredOverride;
  final ValueListenable<List<Place>>? _placesOverride;
  final Future<int> Function(Map<String, PlaceDetails>, {bool onlyMissing})?
  _applyOverride;
  final Future<void> Function()? _readyOverride;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;

  /// Gap enforced between two background Gemini requests.
  final Duration minInterval;

  /// Background requests allowed per app session (manual refreshes don't
  /// count).
  final int maxPerSession;

  /// Results are written once this many are pending...
  final int flushSize;

  /// ...or at least this often while running.
  final Duration flushInterval;

  /// Failed requests in a row before giving up for the session.
  final int maxConsecutiveFailures;

  /// Quiet time after launch / places changing / app resuming before a run.
  final Duration startDelay;

  GeminiService? _gemini;
  GeminiService get _service => _gemini ??= GeminiService();

  bool get _configured =>
      (_configuredOverride ?? () => _service.isConfigured)();

  Future<Map<String, dynamic>> _extract(String prompt) =>
      (_extractOverride ?? _service.extractJson)(prompt);

  ValueListenable<List<Place>> get _places =>
      _placesOverride ?? PlaceStore.instance.places;

  Future<int> _apply(
    Map<String, PlaceDetails> details, {
    bool onlyMissing = false,
  }) => _applyOverride != null
      ? _applyOverride(details, onlyMissing: onlyMissing)
      : PlaceStore.instance.updateDetails(details, onlyMissing: onlyMissing);

  /// Waits for the bound repository's first snapshot, so the [MockData]
  /// seed is never enriched.
  Future<void> _ready() =>
      (_readyOverride ?? () => PlaceStore.instance.loaded)();

  final Map<String, PlaceDetails> _pending = {};

  /// Place ids tried this session (success or failure) — never retried
  /// until the next launch.
  final Set<String> _attempted = {};
  int _requests = 0;
  int _consecutiveFailures = 0;
  DateTime? _lastRequestAt;
  DateTime? _lastFlushAt;

  bool _running = false;
  bool _paused = false;
  bool _stopped = false;
  bool _started = false;
  Timer? _startTimer;

  /// Whether Gemini is configured — "Refresh details" hides otherwise.
  bool get isConfigured => _configured;

  /// Background requests made this session.
  @visibleForTesting
  int get requestCount => _requests;

  /// Whether [place] still needs the background enrichment.
  static bool needsDetails(Place place) =>
      place.details == null && place.name.trim().isNotEmpty;

  /// Longest caption excerpt sent to Gemini.
  static const maxCaptionChars = 4000;

  /// The single enrichment prompt for [place].
  static String buildPrompt(Place place) {
    final type = place.effectiveRestaurantType;
    var caption = place.originalCaption.trim();
    if (caption.length > maxCaptionChars) {
      caption = caption.substring(0, maxCaptionChars);
    }
    final facts = <String>[
      'Name: ${place.name.trim()}',
      'Category: ${place.category.labelEn}'
          '${type != null && type != RestaurantType.other ? ' (${type.labelEn})' : ''}',
      if (place.areaDisplay.isNotEmpty) 'Area: ${place.areaDisplay}',
      if (place.countryCode.isNotEmpty) 'Country code: ${place.countryCode}',
      if (place.address.trim().isNotEmpty) 'Address: ${place.address.trim()}',
      if (place.hours.trim().isNotEmpty)
        'Hours from the post: ${place.hours.trim()}',
    ];
    return '''
You add practical details to a saved travel place for a travel-planning app.

PLACE
${facts.join('\n')}

ORIGINAL POST CAPTION (may be empty; any language)
"""
$caption
"""

RULES
- Use ONLY the caption above plus widely known, well-established facts about this exact place. Do not guess or invent.
- If you are not confident about a field, set it to null (or [] for lists). Empty is better than wrong.
- Never invent opening hours or prices; only give them if the caption states them or they are well known for this place.

Return ONLY a JSON object with these keys:
{
  "mustTry": [string],      // up to 5 signature dishes/items/things to do, short, English
  "priceLevel": 1|2|3|4|null, // 1 cheap, 2 moderate, 3 expensive, 4 very expensive (local standards)
  "nativeName": string|null,  // the name in the local language/script, null if same as Name or unknown
  "tags": [string],         // up to 6 short lowercase English tags, e.g. "late-night", "solo-friendly", "cash-only", "reservation", "queue", "view", "kid-friendly"
  "openingHours": string|null, // human-readable, e.g. "Daily 11:00–23:00"
  "summaryEn": string|null,   // 1–2 sentence English summary
  "summaryZh": string|null,   // same summary in Traditional Chinese (繁體中文)
  "captionEn": string|null,   // the caption translated to English; null if the caption is empty
  "captionZh": string|null    // the caption translated to Traditional Chinese; null if the caption is empty
}
''';
  }

  /// Lenient parse of Gemini's answer into [PlaceDetails] stamped [at]:
  /// unknown/garbage fields become null/empty (see [PlaceDetails.fromJson]),
  /// lists are capped (5 must-try, 6 tags), and translations of an empty
  /// caption are dropped.
  static PlaceDetails parse(
    Map<String, dynamic> json, {
    required Place place,
    required DateTime at,
  }) {
    final parsed = PlaceDetails.fromJson({...json, 'enrichedAt': null})!;
    final hasCaption = place.originalCaption.trim().isNotEmpty;
    final nativeName = parsed.nativeName;
    return PlaceDetails(
      mustTry: parsed.mustTry.take(5).toList(),
      priceLevel: parsed.priceLevel,
      nativeName: nativeName != null && nativeName != place.name.trim()
          ? nativeName
          : null,
      tags: parsed.tags.take(6).toList(),
      openingHours: parsed.openingHours,
      summaryEn: parsed.summaryEn,
      summaryZh: parsed.summaryZh,
      captionEn: hasCaption ? parsed.captionEn : null,
      captionZh: hasCaption ? parsed.captionZh : null,
      enrichedAt: at,
    );
  }

  /// One Gemini call for [place] → its details. Throws when Gemini isn't
  /// configured or the call fails.
  Future<PlaceDetails> enrich(Place place) async {
    final json = await _extract(buildPrompt(place));
    return parse(json, place: place, at: _now());
  }

  /// The detail sheet's "Refresh details": enriches [place] now (no
  /// throttle, not counted against [maxPerSession]) and replaces its
  /// details. Throws on failure so the caller can show it.
  Future<PlaceDetails> refresh(Place place) async {
    final details = await enrich(place);
    await _apply({place.id: details});
    return details;
  }

  /// Starts watching the app lifecycle and [PlaceStore]. Idempotent; a
  /// no-op when Gemini isn't configured. Called from main.dart (never from
  /// widgets, so widget tests don't get live timers).
  void start() {
    if (_started || !_configured) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _places.addListener(_schedule);
    _schedule();
  }

  void _schedule() {
    if (_paused || _running || _stopped || _requests >= maxPerSession) return;
    _startTimer?.cancel();
    _startTimer = Timer(startDelay, () => unawaited(run()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _paused = false;
        // Coming back is a fresh chance: e.g. we gave up while offline.
        _stopped = false;
        _consecutiveFailures = 0;
        _schedule();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _paused = true;
        _startTimer?.cancel();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Enriches every place that [needsDetails], one at a time, until done,
  /// paused, stopped or out of the session budget. Safe to call
  /// repeatedly; a second call while one is running is a no-op.
  Future<void> run() async {
    if (_running || _paused || _stopped || !_configured) return;
    _running = true;
    try {
      await _ready();
      _lastFlushAt = _now();
      while (!_paused && !_stopped && _requests < maxPerSession) {
        final queue = [
          for (final p in _places.value)
            if (needsDetails(p) && !_attempted.contains(p.id)) p,
        ];
        if (queue.isEmpty) break;
        for (final place in queue) {
          if (_paused || _stopped || _requests >= maxPerSession) break;
          _attempted.add(place.id);
          await _throttle();
          _requests++;
          try {
            _pending[place.id] = await enrich(place);
            _consecutiveFailures = 0;
          } catch (e) {
            debugPrint('PlaceEnricher: ${place.id} failed: $e');
            _consecutiveFailures++;
            if (e is StateError ||
                _consecutiveFailures >= maxConsecutiveFailures) {
              debugPrint('PlaceEnricher: giving up for this session');
              _stopped = true;
            }
          }
          if (_pending.length >= flushSize ||
              _now().difference(_lastFlushAt!) >= flushInterval) {
            await _flush();
          }
        }
      }
    } finally {
      await _flush();
      _running = false;
    }
  }

  Future<void> _flush() async {
    _lastFlushAt = _now();
    if (_pending.isEmpty) return;
    final batch = Map.of(_pending);
    _pending.clear();
    try {
      await _apply(batch, onlyMissing: true);
    } catch (e) {
      debugPrint('PlaceEnricher: saving details failed: $e');
    }
  }

  /// Waits until [minInterval] has passed since the previous request.
  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = _now().difference(last);
      if (elapsed < minInterval) await _wait(minInterval - elapsed);
    }
    _lastRequestAt = _now();
  }
}
