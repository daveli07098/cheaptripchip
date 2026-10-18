import 'package:cheaptripchip/services/extraction_cache.dart';
import 'package:cheaptripchip/services/post_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizePostUrl', () {
    test('drops query, fragment, www./m. and trailing slashes', () {
      expect(
        normalizePostUrl('https://www.instagram.com/p/abc123/?igsh=xyz#c'),
        'https://instagram.com/p/abc123',
      );
      expect(
        normalizePostUrl('http://m.tiktok.com/@a/video/42?is_from_webapp=1'),
        'https://tiktok.com/@a/video/42',
      );
    });
    test('maps Instagram /reel/, /reels/ and /tv/ to /p/', () {
      for (final path in ['reel', 'reels', 'tv', 'p']) {
        expect(
          normalizePostUrl('https://instagram.com/$path/abc123'),
          'https://instagram.com/p/abc123',
        );
      }
    });
    test('host case is ignored, shortcode case is kept', () {
      expect(
        normalizePostUrl('https://WWW.Instagram.COM/p/AbC/'),
        'https://instagram.com/p/AbC',
      );
    });
  });

  group('SharedPrefsExtractionCache', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips an entry', () async {
      final cache = SharedPrefsExtractionCache();
      await cache.write(
        'k',
        const CachedExtraction(
          json: {
            'places': [
              {'name': 'A'},
            ],
          },
          caption: 'cap',
          author: '@a',
        ),
      );
      final hit = await SharedPrefsExtractionCache().read('k');
      expect(hit!.json['places'], [
        {'name': 'A'},
      ]);
      expect(hit.caption, 'cap');
      expect(hit.author, '@a');
      expect(await cache.read('missing'), isNull);
    });

    test('ignores entries older than the TTL', () async {
      var now = DateTime(2026, 1, 1);
      final cache = SharedPrefsExtractionCache(now: () => now);
      await cache.write('k', const CachedExtraction(json: {'name': 'A'}));
      now = now.add(SharedPrefsExtractionCache.ttl + const Duration(hours: 1));
      expect(await cache.read('k'), isNull);
    });

    test('keeps at most maxEntries, dropping the oldest', () async {
      final cache = SharedPrefsExtractionCache();
      for (var i = 0; i <= SharedPrefsExtractionCache.maxEntries; i++) {
        await cache.write('k$i', CachedExtraction(json: {'i': i}));
      }
      expect(await cache.read('k0'), isNull);
      expect(await cache.read('k1'), isNotNull);
      expect(
        await cache.read('k${SharedPrefsExtractionCache.maxEntries}'),
        isNotNull,
      );
    });

    test('a corrupt stored value reads as a miss, not an error', () async {
      SharedPreferences.setMockInitialValues({
        SharedPrefsExtractionCache.prefsKey: 'not json',
      });
      expect(await SharedPrefsExtractionCache().read('k'), isNull);
    });
  });
}
