import 'dart:convert';
import 'dart:typed_data';

import 'package:cheaptripchip/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _ok(String content, {String finish = 'stop'}) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content, 'reasoning_content': 'ignored'},
        'finish_reason': finish,
      },
    ],
  }),
  200,
);

http.Response _truncated() => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': null, 'reasoning_content': 'thinking'},
        'finish_reason': 'length',
      },
    ],
  }),
  200,
);

void main() {
  group('AiService', () {
    test(
      'sends an OpenAI chat-completions request with session header',
      () async {
        late http.Request seen;
        final ai = AiService(
          apiKey: 'k',
          baseUrl: 'https://example.test/go/',
          models: ['m1'],
          client: MockClient((req) async {
            seen = req;
            return _ok('{"a":1}');
          }),
        );
        final json = await ai.extractJson('hello');

        expect(json, {'a': 1});
        expect(
          seen.url.toString(),
          'https://example.test/go/v1/chat/completions',
        );
        expect(seen.headers['Authorization'], 'Bearer k');
        expect(
          seen.headers['x-opencode-session'],
          startsWith('cheaptripchip-'),
        );
        final body = jsonDecode(seen.body) as Map<String, dynamic>;
        expect(body['model'], 'm1');
        expect(body['temperature'], 0);
        expect(body['response_format'], {'type': 'json_object'});
        expect(body['messages'], [
          {'role': 'user', 'content': 'hello'},
        ]);
      },
    );

    test('image request carries an image_url data URL', () async {
      late Map<String, dynamic> body;
      final ai = AiService(
        apiKey: 'k',
        models: ['m1'],
        client: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok('{}');
        }),
      );
      await ai.extractJsonFromImage(
        'read this',
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );
      final content =
          ((body['messages'] as List).first as Map)['content'] as List;
      expect(content[0], {'type': 'text', 'text': 'read this'});
      expect(content[1], {
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/png;base64,${base64Encode([1, 2, 3])}',
        },
      });
    });

    test('429 on the first model falls through to the second', () async {
      final tried = <String>[];
      final ai = AiService(
        apiKey: 'k',
        models: ['m1', 'm2'],
        client: MockClient((req) async {
          final model = (jsonDecode(req.body) as Map)['model'] as String;
          tried.add(model);
          return model == 'm1'
              ? http.Response('{"error":{"message":"slow down"}}', 429)
              : _ok('{"ok":true}');
        }),
      );
      expect(await ai.extractJson('p'), {'ok': true});
      expect(tried, ['m1', 'm2']);
    });

    test('empty content with finish_reason=length falls through', () async {
      final tried = <String>[];
      final ai = AiService(
        apiKey: 'k',
        models: ['m1', 'm2'],
        client: MockClient((req) async {
          final model = (jsonDecode(req.body) as Map)['model'] as String;
          tried.add(model);
          return model == 'm1' ? _truncated() : _ok('{"ok":true}');
        }),
      );
      expect(await ai.extractJson('p'), {'ok': true});
      expect(tried, ['m1', 'm2']);
    });

    test('a 401 is a hard error and stops the cascade', () async {
      var calls = 0;
      final ai = AiService(
        apiKey: 'bad',
        models: ['m1', 'm2'],
        client: MockClient((req) async {
          calls++;
          return http.Response(
            '{"type":"error","error":{"type":"auth","message":"Invalid key"}}',
            401,
          );
        }),
      );
      await expectLater(
        ai.extractJson('p'),
        throwsA(
          predicate(
            (e) => e.toString().contains('AI API error: 401 — Invalid key'),
          ),
        ),
      );
      expect(calls, 1);
    });

    test('unconfigured throws a StateError naming AI_API_KEY', () {
      final ai = AiService(apiKey: '', models: ['m1']);
      expect(ai.isConfigured, isFalse);
      expect(
        ai.extractJson('p'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('AI_API_KEY'),
          ),
        ),
      );
    });
  });
}
