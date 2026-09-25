import 'dart:convert';
import 'dart:io';

import 'package:cheaptripchip/data/guest_storage.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/data/repositories.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_area.dart';
import 'package:cheaptripchip/services/area_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

Place _place(
  String id,
  double lat,
  double lng, {
  String region = '',
  String areaLabel = '',
  String countryCode = '',
}) => Place(
  id: id,
  name: 'Place $id',
  areaLabel: areaLabel,
  region: region,
  category: PlaceCategory.restaurant,
  location: LatLng(lat, lng),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.googleMyMaps,
  countryCode: countryCode,
);

final _shibuyaJson = File(
  'test/fixtures/reverse_geocode/shibuya.json',
).readAsStringSync();

/// Nominatim answers in UTF-8 ("Dōgenzaka"); `http.Response(String)`
/// would encode as Latin-1 and throw.
http.Response _ok(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A resolver wired to a fake clock (advanced only by `wait`, so no real
/// sleeps), an in-memory place list and a recording [MockClient].
class _Harness {
  _Harness(
    List<Place> places, {
    http.Response Function(http.Request request)? respond,
    GuestSnapshotStore? cache,
    Duration flushInterval = const Duration(seconds: 20),
  }) : places = ValueNotifier(places) {
    resolver = AreaResolver(
      client: MockClient((request) async {
        requestTimes.add(now);
        requests.add(request);
        return (respond ?? (_) => _ok(_shibuyaJson))(request);
      }),
      cacheStore: cache ?? MemorySnapshotStore(),
      places: this.places,
      applyUpdates: (areas) async {
        flushes.add(Map.of(areas));
        this.places.value = [
          for (final p in this.places.value)
            if (areas[p.id] case final a?)
              p.copyWith(
                region: a.city,
                areaLabel: a.district,
                countryCode: a.countryCode,
              )
            else
              p,
        ];
      },
      now: () => now,
      wait: (d) async {
        waits.add(d);
        now = now.add(d);
      },
      flushInterval: flushInterval,
    );
  }

  final ValueNotifier<List<Place>> places;
  late final AreaResolver resolver;
  DateTime now = DateTime.utc(2026, 9, 26);
  final requests = <http.Request>[];
  final requestTimes = <DateTime>[];
  final waits = <Duration>[];
  final flushes = <Map<String, PlaceArea>>[];
}

void main() {
  test(
    'requests are sequential and at least 1.1 s apart (fake clock)',
    () async {
      final h = _Harness([
        _place('a', 35.1, 139.1),
        _place('b', 35.2, 139.2),
        _place('c', 35.3, 139.3),
      ]);
      await h.resolver.run();

      expect(h.requests, hasLength(3));
      for (var i = 1; i < h.requestTimes.length; i++) {
        expect(
          h.requestTimes[i].difference(h.requestTimes[i - 1]),
          greaterThanOrEqualTo(const Duration(milliseconds: 1100)),
        );
      }
      final uri = h.requests.first.url;
      expect(uri.host, 'nominatim.openstreetmap.org');
      expect(uri.path, '/reverse');
      expect(uri.queryParameters['accept-language'], 'en');
      expect(uri.queryParameters['zoom'], '14');
      expect(h.requests.first.headers['User-Agent'], AreaResolver.userAgent);

      for (final p in h.places.value) {
        expect(p.city, 'Tokyo');
        expect(p.district, 'Shibuya');
        expect(p.countryCode, 'JP');
      }
      expect(h.resolver.progress.value, const AreaProgress(done: 3, total: 3));
    },
  );

  test(
    'coordinates equal to 4 decimals share one lookup; cache persists',
    () async {
      final cache = MemorySnapshotStore();
      final h = _Harness([
        _place('a', 35.65951, 139.70051),
        _place('b', 35.65949, 139.70049),
      ], cache: cache);
      await h.resolver.run();
      expect(h.requests, hasLength(1));
      expect(h.places.value.every((p) => p.district == 'Shibuya'), isTrue);

      // A fresh resolver (next launch) with a new place at the same spot
      // answers from the persisted cache — no network.
      final h2 = _Harness([_place('c', 35.6595, 139.7005)], cache: cache);
      await h2.resolver.run();
      expect(h2.requests, isEmpty);
      expect(h2.places.value.single.district, 'Shibuya');
    },
  );

  test('skips resolved places and keeps existing Gemini fields', () async {
    final h = _Harness([
      _place(
        'done',
        35.1,
        139.1,
        region: 'Tokyo',
        areaLabel: 'Ginza',
        countryCode: 'JP',
      ),
      _place('gemini', 35.2, 139.2, region: 'Tokyo, Japan', areaLabel: '池袋'),
      _place('nan', double.nan, 139.0),
    ]);
    await h.resolver.run();

    expect(h.requests, hasLength(1)); // only 'gemini', for its country
    final gemini = h.places.value.firstWhere((p) => p.id == 'gemini');
    expect(gemini.region, 'Tokyo, Japan');
    expect(gemini.areaLabel, '池袋');
    expect(gemini.countryCode, 'JP');
  });

  test('"nothing here" is cached and not re-queried', () async {
    final cache = MemorySnapshotStore();
    final h = _Harness(
      [_place('sea', 30.0, 150.0)],
      cache: cache,
      respond: (_) => _ok('{"error":"Unable to geocode"}'),
    );
    await h.resolver.run();
    await h.resolver.run();
    expect(h.requests, hasLength(1));
    expect(h.flushes, isEmpty);

    final h2 = _Harness([_place('sea', 30.0, 150.0)], cache: cache);
    await h2.resolver.run();
    expect(h2.requests, isEmpty);
  });

  test('flushes in batches every ~20 s and at the end', () async {
    final h = _Harness([
      for (var i = 0; i < 30; i++) _place('p$i', 35 + i / 100, 139),
    ]);
    await h.resolver.run();

    expect(h.requests, hasLength(30));
    expect(h.flushes.length, greaterThanOrEqualTo(2));
    expect(h.flushes.first.length, lessThan(30));
    expect(h.flushes.fold<int>(0, (sum, f) => sum + f.length), 30);
    expect(
      h.flushes.every((f) => f.length <= PlaceStore.areaWriteChunk),
      isTrue,
    );
  });

  test('backs off on 429 (honouring Retry-After) then continues', () async {
    var calls = 0;
    final h = _Harness(
      [_place('a', 35.1, 139.1)],
      respond: (_) => ++calls == 1
          ? http.Response('slow down', 429, headers: {'retry-after': '7'})
          : _ok(_shibuyaJson),
    );
    await h.resolver.run();
    expect(h.requests, hasLength(2));
    expect(h.waits, contains(const Duration(seconds: 7)));
    expect(h.places.value.single.district, 'Shibuya');
  });

  test('stops after repeated server errors', () async {
    final h = _Harness([
      for (var i = 0; i < 10; i++) _place('p$i', 35 + i / 100, 139),
    ], respond: (_) => http.Response('down', 503));
    await h.resolver.run();
    expect(h.requests, hasLength(5));
    expect(h.resolver.progress.value.running, isFalse);
    expect(h.flushes, isEmpty);
  });

  test('stops at once on 403 (blocked)', () async {
    final h = _Harness([
      for (var i = 0; i < 3; i++) _place('p$i', 35 + i / 100, 139),
    ], respond: (_) => http.Response('blocked', 403));
    await h.resolver.run();
    expect(h.requests, hasLength(1));
  });

  group('PlaceStore.updateAreas', () {
    test('one notifier update, writes via updateAll in chunks of 50', () async {
      final repo = _RecordingRepository([
        for (var i = 0; i < 120; i++) _place('p$i', 35, 139),
      ]);
      PlaceStore.instance.bindRepository(repo);
      await Future<void>.delayed(Duration.zero);

      var notifications = 0;
      void listener() => notifications++;
      PlaceStore.instance.places.addListener(listener);
      await PlaceStore.instance.updateAreas({
        for (var i = 0; i < 120; i++)
          'p$i': const PlaceArea(
            city: 'Tokyo',
            district: 'Shibuya',
            countryCode: 'JP',
          ),
        'missing': const PlaceArea(city: 'X', district: 'Y', countryCode: 'ZZ'),
      });
      PlaceStore.instance.places.removeListener(listener);

      expect(notifications, 1);
      expect(repo.updateAllSizes, [50, 50, 20]);
      expect(repo.upsertAllCalls, 0);
      expect(
        PlaceStore.instance.places.value.every((p) => p.district == 'Shibuya'),
        isTrue,
      );
    });
  });
}

class _RecordingRepository implements PlaceRepository {
  _RecordingRepository(this._seed);

  final List<Place> _seed;
  final updateAllSizes = <int>[];
  int upsertAllCalls = 0;

  @override
  Stream<List<Place>> watch() => Stream.value(_seed);

  @override
  Future<void> upsert(Place place) async {}

  @override
  Future<void> upsertAll(List<Place> places) async => upsertAllCalls++;

  @override
  Future<void> updateAll(List<Place> places) async =>
      updateAllSizes.add(places.length);

  @override
  Future<void> delete(String id) async {}
}
