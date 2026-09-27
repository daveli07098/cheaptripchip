import 'package:cheaptripchip/services/web_share_intake.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sharedTextFromQuery', () {
    test('no share params → null', () {
      expect(sharedTextFromQuery({}), isNull);
      expect(sharedTextFromQuery({'foo': 'bar'}), isNull);
      expect(sharedTextFromQuery({'add': '  ', 'text': ''}), isNull);
    });

    test('add (Apple Shortcut) wins and is trimmed', () {
      expect(
        sharedTextFromQuery({
          'add': ' https://www.instagram.com/reel/abc/ ',
          'url': 'https://other.example',
        }),
        'https://www.instagram.com/reel/abc/',
      );
    });

    test('Uri.base decoding of an encoded add link round-trips', () {
      const link = 'https://www.instagram.com/reel/abc/?igsh=x1&utm=y';
      final uri = Uri.parse(
        'https://cheaptripchip.vercel.app/?add=${Uri.encodeComponent(link)}',
      );
      expect(sharedTextFromQuery(uri.queryParameters), link);
    });

    test('Android share target: url only', () {
      expect(
        sharedTextFromQuery({'title': 'Instagram', 'url': 'https://x.test/p'}),
        'https://x.test/p',
      );
    });

    test('Android share target: text containing the url is not doubled', () {
      expect(
        sharedTextFromQuery({
          'text': 'Best noodles https://vt.tiktok.com/abc/',
          'url': 'https://vt.tiktok.com/abc/',
        }),
        'Best noodles https://vt.tiktok.com/abc/',
      );
    });

    test('Android share target: text and a different url are combined', () {
      expect(
        sharedTextFromQuery({'text': 'Cafe in Kyoto', 'url': 'https://x.test'}),
        'Cafe in Kyoto\nhttps://x.test',
      );
    });

    test('title only when nothing else is shared', () {
      expect(
        sharedTextFromQuery({'title': 'Ichiran Shibuya'}),
        'Ichiran Shibuya',
      );
    });
  });

  group('withoutShareParams', () {
    test('drops share params, keeps others and the fragment', () {
      expect(
        withoutShareParams(
          Uri.parse('https://a.test/?add=x&keep=1&title=t#/route'),
        ),
        '/?keep=1#/route',
      );
    });

    test('leaves a bare root when only share params were present', () {
      expect(
        withoutShareParams(Uri.parse('https://a.test/?text=a&url=b')),
        '/',
      );
      expect(withoutShareParams(Uri.parse('https://a.test?add=x')), '/');
    });
  });
}
