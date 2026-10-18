// Add-a-find error wording: developer hints only in debug builds, the
// caption/screenshot guidance for everyone.
import 'dart:async';

import 'package:cheaptripchip/services/place_extractor.dart';
import 'package:cheaptripchip/widgets/add_find_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlyExtractionMessage', () {
    const devHints = ['--dart-define', 'Cloud Console', 'Exception', 'Bad'];

    void expectNoDevHints(String message) {
      for (final hint in devHints) {
        expect(message, isNot(contains(hint)), reason: message);
      }
    }

    test('release: a missing key reads as "not available", no flags', () {
      final message = friendlyExtractionMessage(
        StateError('GEMINI_API_KEY is not set'),
        debug: false,
      );
      expectNoDevHints(message);
      expect(message, contains('try again later'));
    });

    test('release: a blocked key (403) has no Cloud Console steps', () {
      final message = friendlyExtractionMessage(
        Exception('Gemini 403: API_KEY_SERVICE_BLOCKED'),
        debug: false,
      );
      expectNoDevHints(message);
    });

    test('release: an unknown failure hides the raw exception text and '
        'suggests the caption/screenshot route', () {
      final message = friendlyExtractionMessage(
        Exception('Bad state: unexpected token'),
        debug: false,
      );
      expectNoDevHints(message);
      expect(message, contains('paste the caption'));
      expect(message, contains('screenshot'));
    });

    test('a timeout reads as a connection problem', () {
      final message = friendlyExtractionMessage(
        TimeoutException('slow'),
        debug: false,
      );
      expect(message, contains('connection'));
    });

    test('caption-unavailable guidance is kept in release', () {
      final message = friendlyExtractionMessage(
        const CaptionUnavailableException('https://instagram.com/p/x'),
        debug: false,
      );
      expect(message, contains('Paste the caption'));
      expect(message, contains('screenshot'));
    });

    test('debug keeps the developer hints', () {
      expect(
        friendlyExtractionMessage(
          StateError('GEMINI_API_KEY is not set'),
          debug: true,
        ),
        contains('--dart-define=GEMINI_API_KEY'),
      );
      expect(
        friendlyExtractionMessage(Exception('Gemini 403'), debug: true),
        contains('Cloud Console'),
      );
      expect(
        friendlyExtractionMessage(Exception('boom'), debug: true),
        'Extraction failed: boom',
      );
    });
  });
}
