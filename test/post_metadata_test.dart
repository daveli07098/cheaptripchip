import 'package:cheaptripchip/services/post_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('isSupportedPostUrl', () {
    test('accepts Instagram post/reel/reels/tv permalinks', () {
      for (final path in [
        '/p/BsOGulcndj-/',
        '/reel/abc123/',
        '/reels/abc/',
        '/tv/abc/',
      ]) {
        expect(
          isSupportedPostUrl(Uri.parse('https://www.instagram.com$path')),
          isTrue,
          reason: path,
        );
      }
    });

    test('rejects an Instagram profile page', () {
      expect(
        isSupportedPostUrl(Uri.parse('https://www.instagram.com/rame.nbon/')),
        isFalse,
      );
    });

    test('accepts any TikTok URL including short-link hosts', () {
      for (final url in [
        'https://www.tiktok.com/@user/video/123',
        'https://vm.tiktok.com/ZM123abc/',
        'https://vt.tiktok.com/ZM123abc/',
      ]) {
        expect(isSupportedPostUrl(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('rejects an unrelated host', () {
      expect(isSupportedPostUrl(Uri.parse('https://example.com/p/1')), isFalse);
    });
  });

  group('extractFirstPostUrl', () {
    test('finds the URL inside messy share text', () {
      expect(
        extractFirstPostUrl(
          'check this out! https://www.instagram.com/reel/abc123/?igsh=xyz cool right',
        ),
        'https://www.instagram.com/reel/abc123/?igsh=xyz',
      );
    });

    test('trims trailing sentence punctuation', () {
      expect(
        extractFirstPostUrl('link: https://www.instagram.com/p/abc123/.'),
        'https://www.instagram.com/p/abc123/',
      );
      expect(
        extractFirstPostUrl('(see https://vm.tiktok.com/ZM123abc/)'),
        'https://vm.tiktok.com/ZM123abc/',
      );
    });

    test('ignores an unsupported URL and returns null', () {
      expect(extractFirstPostUrl('see https://example.com/foo'), isNull);
    });

    test('returns null when there is no URL at all', () {
      expect(extractFirstPostUrl('just a caption, no link'), isNull);
    });
  });

  group('PostMetadata.caption', () {
    test('derives full caption from og:title, stripping the IG prefix', () {
      const meta = PostMetadata(
        title: 'Ramen Bon on Instagram: "Best tonkotsu in Ikebukuro 🍜"',
      );
      expect(meta.caption, 'Best tonkotsu in Ikebukuro 🍜');
    });

    test('handles quotes inside the caption itself (uses the LAST quote)', () {
      const meta = PostMetadata(
        title: 'Ramen Bon on Instagram: "He said “so good”, truly"',
      );
      expect(meta.caption, 'He said “so good”, truly');
    });

    test(
      'falls back to og:description after the "<handle> on <date>: " prefix',
      () {
        const meta = PostMetadata(
          description:
              '123 likes, 4 comments - rame.nbon on March 3, 2024: '
              '"Best tonkotsu in town, come early…"',
        );
        expect(meta.caption, 'Best tonkotsu in town, come early');
      },
    );

    test('TikTok-shaped description with no IG prefix is used verbatim', () {
      const meta = PostMetadata(
        description: '12.3K Likes, 456 Comments. TikTok video from user.',
      );
      expect(
        meta.caption,
        '12.3K Likes, 456 Comments. TikTok video from user.',
      );
    });

    test('prefers the title-derived caption over the description', () {
      const meta = PostMetadata(
        title: 'Name on Instagram: "full untruncated caption"',
        description: '1 like - name on Jan 1, 2024: "trunc…',
      );
      expect(meta.caption, 'full untruncated caption');
    });

    test('null when neither field is present', () {
      const meta = PostMetadata();
      expect(meta.caption, isNull);
    });
  });

  group('PostMetadata.author (derived by fetchPostMetadata)', () {
    test('parses the handle out of a description and prefixes @', () async {
      final client = MockClient((req) async {
        return http.Response(
          '<html><head>'
          '<meta property="og:description" '
          'content="123 likes, 4 comments - rame.nbon on March 3, 2024: '
          '&quot;caption&quot;">'
          '</head></html>',
          200,
        );
      });
      final meta = await fetchPostMetadata(
        Uri.parse('https://www.instagram.com/p/abc/'),
        client: client,
      );
      expect(meta?.author, '@rame.nbon');
    });
  });

  group('fetchPostMetadata', () {
    test('parses og:title/og:description regardless of attribute order', () async {
      final client = MockClient((req) async {
        return http.Response(
          '<html><head>'
          '<meta content="Name on Instagram: &quot;caption text&quot;" property="og:title">'
          '<meta property="og:description" content="123 likes - name on Jan 1, 2024: &quot;desc&quot;">'
          "</head></html>",
          200,
        );
      });
      final meta = await fetchPostMetadata(
        Uri.parse('https://www.instagram.com/p/abc/'),
        client: client,
      );
      expect(meta, isNotNull);
      expect(meta!.title, 'Name on Instagram: "caption text"');
      expect(meta.caption, 'caption text');
    });

    test('handles single-quoted attributes', () async {
      final client = MockClient((req) async {
        return http.Response(
          "<meta property='og:title' content='Name on Instagram: \"hi\"'>",
          200,
        );
      });
      final meta = await fetchPostMetadata(
        Uri.parse('https://www.instagram.com/p/abc/'),
        client: client,
      );
      expect(meta?.title, 'Name on Instagram: "hi"');
    });

    test(
      'decodes numeric entities including an astral emoji and &#064;',
      () async {
        final client = MockClient((req) async {
          return http.Response(
            '<meta property="og:title" '
            'content="Name on Instagram: &quot;craving &#x1F35C; at &#064;spot&quot;">',
            200,
          );
        });
        final meta = await fetchPostMetadata(
          Uri.parse('https://www.instagram.com/p/abc/'),
          client: client,
        );
        expect(meta?.caption, 'craving \u{1F35C} at @spot');
      },
    );

    test('falls back to <meta name="description"> when no og tags', () async {
      final client = MockClient((req) async {
        return http.Response(
          '<meta name="description" content="a plain description">',
          200,
        );
      });
      final meta = await fetchPostMetadata(
        Uri.parse('https://www.tiktok.com/@user/video/123'),
        client: client,
      );
      expect(meta?.description, 'a plain description');
    });

    test(
      'parses content that spans literal newlines (multi-line captions)',
      () async {
        final client = MockClient((req) async {
          return http.Response(
            '<meta property="og:title" content="Name on Instagram: &quot;line one\n\nline two&quot;">',
            200,
          );
        });
        final meta = await fetchPostMetadata(
          Uri.parse('https://www.instagram.com/p/abc/'),
          client: client,
        );
        expect(meta?.caption, 'line one\n\nline two');
      },
    );

    test('returns null for a non-200 response', () async {
      final client = MockClient((req) async {
        return http.Response('not found', 404);
      });
      final meta = await fetchPostMetadata(
        Uri.parse('https://www.instagram.com/p/abc/'),
        client: client,
      );
      expect(meta, isNull);
    });

    test('returns null with no og tags at all (login-wall shell)', () async {
      final client = MockClient((req) async {
        return http.Response(
          '<html><head><title>Login</title></head></html>',
          200,
        );
      });
      final meta = await fetchPostMetadata(
        Uri.parse('https://www.instagram.com/p/abc/'),
        client: client,
      );
      expect(meta, isNull);
    });

    test('returns null on timeout', () async {
      final client = MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return http.Response('<meta property="og:title" content="x">', 200);
      });
      final meta = await fetchPostMetadata(
        Uri.parse('https://www.instagram.com/p/abc/'),
        client: client,
        timeout: const Duration(milliseconds: 50),
      );
      expect(meta, isNull);
    });

    test('returns null for an unsupported URL without a request', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('<meta property="og:title" content="x">', 200);
      });
      final meta = await fetchPostMetadata(
        Uri.parse('https://example.com/p/abc/'),
        client: client,
      );
      expect(meta, isNull);
      expect(called, isFalse);
    });
  });
}
