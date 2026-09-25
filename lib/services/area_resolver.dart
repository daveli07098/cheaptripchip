import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../data/guest_storage.dart';
import '../data/place_store.dart';
import '../models/place.dart';
import '../models/place_area.dart';

/// Background backfill of city → district for saved places, via OSM
/// Nominatim reverse geocoding (the same provider as [GeocodingService]).
///
/// Nominatim usage policy (operations.osmfoundation.org/policies/nominatim):
/// an absolute maximum of 1 request/second, an identifying User-Agent with
/// contact details, and results must be cached. So this runs strictly
/// sequentially with [minInterval] (1.1 s) between requests, caches every
/// answer (including "nothing here") per coordinate rounded to 4 decimals
/// (~11 m) in memory and on disk, backs off on 429/5xx (honouring
/// Retry-After) and gives up for the session after
/// [maxConsecutiveFailures] failures in a row, or at once on any other
/// 4xx (e.g. 403 = blocked). A ~1,650-place backfill takes ~30 minutes of
/// foreground time once, resumable across launches — resolved places are
/// written back and skipped next time.
///
/// Results are written through [PlaceStore.updateAreas] in batches (every
/// [flushInterval] or [flushSize] results, and at the end), so Firestore
/// sees a few small batched writes instead of one per place. Places that
/// already have a city/district (e.g. from Gemini extraction) keep them;
/// only empty fields are filled.
class AreaResolver with WidgetsBindingObserver {
  AreaResolver({
    http.Client? client,
    GuestSnapshotStore? cacheStore,
    ValueListenable<List<Place>>? places,
    Future<void> Function(Map<String, PlaceArea> areas)? applyUpdates,
    DateTime Function()? now,
    Future<void> Function(Duration duration)? wait,
    this.minInterval = const Duration(milliseconds: 1100),
    this.flushInterval = const Duration(seconds: 20),
    this.flushSize = PlaceStore.areaWriteChunk,
    this.maxConsecutiveFailures = 5,
    this.startDelay = const Duration(seconds: 5),
  }) : _client = client ?? http.Client(),
       _cacheStore = cacheStore,
       _placesOverride = places,
       _applyOverride = applyUpdates,
       _now = now ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed;

  static final AreaResolver instance = AreaResolver(
    cacheStore: GuestSnapshotStore.forCollection('area_cache'),
  );

  static const userAgent =
      'CheapTripChip/0.1 (area reverse-geocode; contact: dev@cheaptripchip.app)';

  final http.Client _client;
  final GuestSnapshotStore? _cacheStore;
  final ValueListenable<List<Place>>? _placesOverride;
  final Future<void> Function(Map<String, PlaceArea>)? _applyOverride;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;

  /// Gap enforced between two Nominatim requests (policy: ≥ 1 s).
  final Duration minInterval;

  /// Results are written to the store at least this often while running.
  final Duration flushInterval;

  /// ...or as soon as this many results are pending.
  final int flushSize;

  /// Failed requests in a row (429/5xx/network) before giving up.
  final int maxConsecutiveFailures;

  /// Quiet time after launch / places changing / app resuming before a run.
  final Duration startDelay;

  ValueListenable<List<Place>> get _places =>
      _placesOverride ?? PlaceStore.instance.places;

  Future<void> _apply(Map<String, PlaceArea> areas) =>
      (_applyOverride ?? PlaceStore.instance.updateAreas)(areas);

  final ValueNotifier<AreaProgress> _progress = ValueNotifier(
    const AreaProgress(),
  );

  /// {done, total, running} for the drawer's "Finding areas…" line.
  ValueListenable<AreaProgress> get progress => _progress;

  /// Rounded "lat,lng" → area, or null when Nominatim had nothing there.
  final Map<String, PlaceArea?> _cache = {};
  bool _cacheLoaded = false;
  bool _cacheDirty = false;

  final Map<String, PlaceArea> _pending = {};
  DateTime? _lastRequestAt;
  DateTime? _lastFlushAt;
  int _consecutiveFailures = 0;

  bool _running = false;
  bool _paused = false;

  /// Set when Nominatim refused us (4xx) or failed too often; no more
  /// requests this session (cached answers still apply).
  bool _stopped = false;
  bool _started = false;
  Timer? _startTimer;

  /// Whether [place] still lacks a city, district or country and has
  /// coordinates worth looking up.
  static bool needsArea(Place place) {
    final lat = place.location.latitude;
    final lng = place.location.longitude;
    if (!lat.isFinite || !lng.isFinite || (lat == 0 && lng == 0)) {
      return false;
    }
    return place.city.isEmpty ||
        place.district.isEmpty ||
        place.countryCode.isEmpty;
  }

  /// Cache key: coordinates rounded to 4 decimals (~11 m), so duplicate
  /// and near-identical pins share one lookup.
  static String cacheKey(LatLng location) =>
      '${location.latitude.toStringAsFixed(4)},'
      '${location.longitude.toStringAsFixed(4)}';

  /// What to write for [place] given a looked-up [area]: existing non-empty
  /// fields win; null when nothing would change.
  static PlaceArea? merge(Place place, PlaceArea area) {
    final city = place.city.isNotEmpty || area.city.isEmpty
        ? place.region
        : area.city;
    final district = place.district.isNotEmpty || area.district.isEmpty
        ? place.areaLabel
        : area.district;
    final countryCode = place.countryCode.isNotEmpty
        ? place.countryCode
        : area.countryCode;
    if (city == place.region &&
        district == place.areaLabel &&
        countryCode == place.countryCode) {
      return null;
    }
    return PlaceArea(city: city, district: district, countryCode: countryCode);
  }

  /// Starts watching the app lifecycle and [PlaceStore]; the first run
  /// begins after [startDelay] of quiet. Idempotent. Called from main.dart
  /// (never from widgets, so widget tests don't get live timers).
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _places.addListener(_schedule);
    _schedule();
  }

  void _schedule() {
    if (_paused || _running) return;
    _startTimer?.cancel();
    _startTimer = Timer(startDelay, () {
      if (_places.value.any(needsArea)) unawaited(run());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _paused = false;
        // Coming back is a fresh chance: e.g. we gave up while offline.
        resetFailures();
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

  /// Resolves every place that [needsArea], one at a time, until done,
  /// paused or stopped. Safe to call repeatedly; a second call while one
  /// is running is a no-op.
  Future<void> run() async {
    if (_running || _paused) return;
    _running = true;
    try {
      await _loadCache();
      _lastFlushAt = _now();
      var done = 0;
      final attempted = <String>{};
      outer:
      while (!_paused) {
        final queue = [
          for (final p in _places.value)
            if (needsArea(p) && !attempted.contains(p.id)) p,
        ];
        if (queue.isEmpty) break;
        _progress.value = AreaProgress(
          done: done,
          total: done + queue.length,
          running: true,
        );
        for (final place in queue) {
          if (_paused) break outer;
          attempted.add(place.id);
          final key = cacheKey(place.location);
          PlaceArea? area;
          if (_cache.containsKey(key)) {
            area = _cache[key];
          } else {
            if (_stopped) continue;
            final result = await _lookup(place.location);
            if (result == null) continue; // gave up — _stopped is set
            area = result.area;
            _cache[key] = area;
            _cacheDirty = true;
          }
          if (area != null) {
            final merged = merge(place, area);
            if (merged != null) _pending[place.id] = merged;
          }
          done++;
          _progress.value = AreaProgress(
            done: done,
            total: _progress.value.total,
            running: true,
          );
          if (_pending.length >= flushSize ||
              _now().difference(_lastFlushAt!) >= flushInterval) {
            await _flush();
          }
        }
      }
    } finally {
      await _flush();
      _running = false;
      _progress.value = AreaProgress(
        done: _progress.value.done,
        total: _progress.value.total,
      );
    }
  }

  Future<void> _flush() async {
    _lastFlushAt = _now();
    if (_pending.isNotEmpty) {
      final batch = Map.of(_pending);
      _pending.clear();
      try {
        await _apply(batch);
      } catch (e) {
        debugPrint('AreaResolver: saving areas failed: $e');
      }
    }
    if (_cacheDirty && _cacheStore != null) {
      _cacheDirty = false;
      try {
        await _cacheStore.write(
          jsonEncode({
            for (final entry in _cache.entries)
              entry.key: entry.value?.toJson(),
          }),
        );
      } catch (e) {
        debugPrint('AreaResolver: saving cache failed: $e');
      }
    }
  }

  Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    final store = _cacheStore;
    if (store == null) return;
    try {
      final raw = await store.read();
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final value = entry.value;
        _cache['${entry.key}'] = value is Map
            ? PlaceArea.fromJson(Map<String, dynamic>.from(value))
            : null;
      }
    } catch (e) {
      debugPrint('AreaResolver: cache unreadable, starting fresh: $e');
    }
  }

  /// One reverse lookup, rate-limited, with backoff. Null means give up
  /// (and [_stopped] is set); otherwise the area (null inside = nothing
  /// found there).
  Future<_Lookup?> _lookup(LatLng location) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': location.latitude.toStringAsFixed(6),
      'lon': location.longitude.toStringAsFixed(6),
      'zoom': '14',
      'accept-language': 'en',
      'addressdetails': '1',
    });
    while (true) {
      if (_paused) return null;
      await _throttle();
      Duration? retryAfter;
      try {
        final res = await _client
            .get(uri, headers: {'User-Agent': userAgent})
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          _consecutiveFailures = 0;
          final decoded = jsonDecode(utf8.decode(res.bodyBytes));
          return _Lookup(
            decoded is Map<String, dynamic> ? areaFromNominatim(decoded) : null,
          );
        }
        if (res.statusCode != 429 && res.statusCode < 500) {
          debugPrint('AreaResolver: Nominatim ${res.statusCode}, stopping');
          _stopped = true;
          return null;
        }
        final header = int.tryParse(res.headers['retry-after'] ?? '');
        if (header != null) retryAfter = Duration(seconds: header);
      } catch (e) {
        debugPrint('AreaResolver: lookup failed: $e');
      }
      _consecutiveFailures++;
      if (_consecutiveFailures >= maxConsecutiveFailures) {
        debugPrint('AreaResolver: $_consecutiveFailures failures, stopping');
        _stopped = true;
        return null;
      }
      // 2 s, 4 s, 8 s … capped at a minute (or the server's Retry-After).
      final backoff = Duration(
        seconds: (1 << _consecutiveFailures).clamp(2, 60),
      );
      await _wait(
        retryAfter != null && retryAfter > backoff ? retryAfter : backoff,
      );
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

  /// Forgets a previous give-up (not the persisted cache), so the next
  /// [run] talks to Nominatim again.
  void resetFailures() {
    _stopped = false;
    _consecutiveFailures = 0;
  }
}

class _Lookup {
  const _Lookup(this.area);
  final PlaceArea? area;
}

/// Backfill progress for the drawer.
@immutable
class AreaProgress {
  const AreaProgress({this.done = 0, this.total = 0, this.running = false});

  final int done;
  final int total;
  final bool running;

  @override
  bool operator ==(Object other) =>
      other is AreaProgress &&
      other.done == done &&
      other.total == total &&
      other.running == running;

  @override
  int get hashCode => Object.hash(done, total, running);
}

/// Maps a Nominatim `/reverse?format=jsonv2&addressdetails=1` response to
/// city → district, or null when it has no address (e.g. `{"error": …}`).
///
/// Rules (see test/fixtures/reverse_geocode/ for real samples):
/// * Country: `country_code`, except Hong Kong / Macau, which Nominatim
///   reports as `cn` — recognised by `ISO3166-2-lvl3` CN-HK / CN-MO.
/// * Tokyo (`ISO3166-2-lvl4` JP-13): the 23 wards come back as `city`
///   ("Shibuya", "Chuo") with no prefecture, so city = "Tokyo" and district
///   = that ward/municipality. Ward level, not neighbourhood: Ginza files
///   under "Chuo", consistent with how Shibuya/Shinjuku resolve.
/// * Other Japan: city = `city`/`town`/`village` ("Osaka", "Hakone"),
///   district = `suburb` (the ward, "Chūō Ward" → "Chuo") or `quarter`.
/// * Hong Kong / Macau / Singapore: fixed city name, district = `suburb`
///   ("Mong Kok", "Wan Chai District" → "Wan Chai", "Rochor"). HK's
///   `city_district` ("Hong Kong Island") and SG's `borough` ("Central
///   Region") are too coarse and skipped.
/// * South Korea: district = `borough` (the gu, "Jung-gu"), else `suburb`.
/// * Elsewhere (Taiwan, Thailand, …): city = `city`/`town`/…, district =
///   `suburb`/`city_district`/`borough`/`quarter`/`neighbourhood`
///   ("Xinyi District" → "Xinyi", "Pathum Wan District" → "Pathum Wan").
/// Names are English (`accept-language=en`), macrons folded ("Chūō" →
/// "Chuo") and " Ward"/"-ku"/" District"/" Subdistrict"/" City" suffixes
/// stripped so the same place never appears under two spellings.
PlaceArea? areaFromNominatim(Map<String, dynamic> json) {
  final address = json['address'];
  if (address is! Map) return null;
  String field(String key) {
    final value = address[key];
    return value is String ? value.trim() : '';
  }

  String first(List<String> keys) {
    for (final key in keys) {
      final value = field(key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  var countryCode = field('country_code').toUpperCase();
  final lvl3 = field('ISO3166-2-lvl3').toUpperCase();
  if (lvl3 == 'CN-HK') countryCode = 'HK';
  if (lvl3 == 'CN-MO') countryCode = 'MO';
  final lvl4 = field('ISO3166-2-lvl4').toUpperCase();

  const municipality = ['city', 'town', 'village', 'municipality'];
  const subdivisions = [
    'suburb',
    'city_district',
    'borough',
    'quarter',
    'neighbourhood',
  ];

  String city;
  String district;
  switch (countryCode) {
    case 'HK':
      city = 'Hong Kong';
      district = first(['suburb', 'quarter', 'neighbourhood']);
    case 'MO':
      city = 'Macau';
      district = first(['suburb', 'city_district', 'quarter', 'neighbourhood']);
    case 'SG':
      city = 'Singapore';
      district = first(['suburb', 'quarter', 'neighbourhood']);
    case 'JP' when lvl4 == 'JP-13':
      city = 'Tokyo';
      district = first([...municipality, ...subdivisions]);
    case 'KR':
      city = first([...municipality, 'province', 'state']);
      district = first(['borough', ...subdivisions]);
    default:
      city = first([...municipality, 'county', 'province', 'state']);
      district = first(subdivisions);
  }

  city = cleanAreaName(city);
  district = cleanAreaName(district);
  if (district == city) district = '';
  final area = PlaceArea(
    city: city,
    district: district,
    countryCode: countryCode,
  );
  return area.isEmpty ? null : area;
}

const _macrons = {
  'ā': 'a',
  'ē': 'e',
  'ī': 'i',
  'ō': 'o',
  'ū': 'u',
  'Ā': 'A',
  'Ē': 'E',
  'Ī': 'I',
  'Ō': 'O',
  'Ū': 'U',
};

final _suffix = RegExp(
  r'(\s+(Ward|District|Subdistrict|City)|-(ku|shi))$',
  caseSensitive: false,
);

/// Folds macrons and strips administrative suffixes: "Chūō Ward" → "Chuo",
/// "Shibuya-ku" → "Shibuya", "Xinyi District" → "Xinyi". Korean "-gu"
/// stays ("Jung-gu") — without it the name is ambiguous.
@visibleForTesting
String cleanAreaName(String raw) {
  var name = raw.trim();
  for (final entry in _macrons.entries) {
    name = name.replaceAll(entry.key, entry.value);
  }
  return name.replaceFirst(_suffix, '').trim();
}

/// Regional-indicator flag for an ISO 3166-1 alpha-2 code ("JP" → 🇯🇵);
/// empty for anything else.
String flagEmoji(String countryCode) {
  final code = countryCode.toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '';
  return String.fromCharCodes([
    0x1F1E6 + code.codeUnitAt(0) - 0x41,
    0x1F1E6 + code.codeUnitAt(1) - 0x41,
  ]);
}
