import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// AI client for OpenCode Go's OpenAI-compatible chat-completions API
/// (ported from the event-calendar client, `src/lib/ai/client.ts`).
///
/// Same shape: direct REST calls, JSON mode with temperature 0 for
/// deterministic extraction, a model cascade that falls through on transient
/// errors, and lenient JSON parsing of the model output.
///
/// Config is read from compile-time `--dart-define`s so no key is hard-coded:
///   flutter run --dart-define=AI_API_KEY=xxx
///   flutter run --dart-define=AI_API_KEY=xxx \
///               --dart-define=AI_BASE_URL=https://your-proxy.example.com
///   flutter run --dart-define=AI_MODELS=glm-5.3-flash,mimo-v2.6-flash
///
/// SECURITY NOTE: shipping an OpenCode Go key inside a client app exposes it.
/// For production, point [baseUrl] at YOUR backend/proxy (docs/ai-proxy.md) and
/// let the server hold the real key (AI_API_KEY is then the proxy's APP_TOKEN).
/// This client is wired so that swap is config-only.
class AiService {
  AiService({
    String? apiKey,
    String? baseUrl,
    List<String>? models,
    http.Client? client,
  }) : apiKey = apiKey ?? _envApiKey,
       baseUrl = _trimSlashes(baseUrl ?? _envBaseUrl),
       models = models ?? _envModelPool(),
       _client = client ?? http.Client();

  static const _envApiKey = String.fromEnvironment('AI_API_KEY');
  static const _envBaseUrl = String.fromEnvironment(
    'AI_BASE_URL',
    defaultValue: 'https://opencode.ai/inference/go',
  );
  static const _envModels = String.fromEnvironment('AI_MODELS');

  /// Comma-separated `AI_MODELS` override, or [defaultModels] when empty.
  static List<String> _envModelPool() {
    final custom = _envModels
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    return custom.isEmpty ? defaultModels : custom;
  }

  /// Cascade priority order (most-available first). All verified live
  /// 2026-10-27 for JSON text + image input on OpenCode Go.
  ///
  /// deepseek-v4.1-flash also works, but only after enabling the "Global"
  /// region in the OpenCode workspace privacy settings — opt in via AI_MODELS.
  static const List<String> defaultModels = [
    'glm-5.3-flash',
    'minimax-m3.1-flash',
    'mimo-v2.6-flash',
  ];

  /// OpenCode Go rejects requests without `x-opencode-session` (400
  /// MissingSessionID), so every request carries one id, random per process.
  static final String _sessionId = () {
    final rng = Random.secure();
    final hex = List.generate(
      16,
      (_) => rng.nextInt(16).toRadixString(16),
    ).join();
    return 'cheaptripchip-$hex';
  }();

  final String apiKey;
  final String baseUrl;
  final List<String> models;
  final http.Client _client;

  bool get isConfigured => apiKey.isNotEmpty;

  /// Run a JSON-extraction prompt through the model cascade. Tries each model in
  /// order; transient failures (429/503/network) fall through to the next.
  /// Throws if nothing is configured or every model fails.
  Future<Map<String, dynamic>> extractJson(String prompt) => _cascade(prompt);

  /// [extractJson] with an image attached (vision): the prompt plus one
  /// `image_url` part carrying [imageBytes] as a base64 data URL. Keep the
  /// image small (see image_prep.dart) — the proxy caps image requests at
  /// 4 MB, and a 413 is a hard error, not a cascade fall-through.
  Future<Map<String, dynamic>> extractJsonFromImage(
    String prompt,
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) => _cascade([
    {'type': 'text', 'text': prompt},
    {
      'type': 'image_url',
      'image_url': {'url': 'data:$mimeType;base64,${base64Encode(imageBytes)}'},
    },
  ]);

  /// [content] is the prompt string, or a list of text/image_url parts.
  Future<Map<String, dynamic>> _cascade(Object content) async {
    if (!isConfigured) {
      throw StateError(
        'No AI_API_KEY configured. Pass it via --dart-define=AI_API_KEY=...',
      );
    }

    final failures = <String>[];
    for (final model in models) {
      try {
        return await _callJson(content, model);
      } catch (e) {
        final msg = e.toString();
        failures.add(msg);
        if (!_isTransient(msg)) rethrow; // hard error — stop the cascade
        // transient → try the next model
      }
    }
    final unique = failures.toSet().take(2).join(' | ');
    throw Exception(unique.isEmpty ? 'All AI models failed' : unique);
  }

  Future<Map<String, dynamic>> _callJson(Object content, String model) async {
    final uri = Uri.parse('$baseUrl/v1/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      'x-opencode-session': _sessionId,
      // Go asks clients not to send a generic library UA; browsers forbid
      // setting it, so only on native builds.
      if (!kIsWeb) 'User-Agent': 'cheaptripchip-app',
    };
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'user', 'content': content},
      ],
      // temperature 0 → deterministic extraction (same rationale as the TS client).
      'temperature': 0,
      // A ceiling, not a cost: a multi-place post (several places, each
      // with alternatives) plus the model's reasoning tokens overran 2048,
      // and a truncated nested JSON can't be salvaged.
      'max_tokens': 8192,
      'response_format': {'type': 'json_object'},
    });

    http.Response? res;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      res = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200 || res.statusCode != 503) break;
    }

    if (res == null || res.statusCode != 200) {
      // Surface the API's own message (e.g. "MissingSessionID")
      // so cascade failures are diagnosable, not just status codes.
      var detail = '';
      try {
        final err = jsonDecode(res?.body ?? '') as Map<String, dynamic>;
        final m = (err['error'] as Map?)?['message'];
        if (m is String) detail = ' — $m';
      } catch (_) {
        /* non-JSON error body */
      }
      throw Exception('AI API error: ${res?.statusCode ?? 'unknown'}$detail');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final choice = _firstChoice(data);
    final text = (choice?['message'] as Map?)?['content'];
    if (text is! String || text.isEmpty) {
      // Reasoning models can burn the whole budget before writing any answer.
      if (choice?['finish_reason'] == 'length') {
        throw Exception(
          'AI response truncated (finish_reason=length) on $model',
        );
      }
      return parseJsonLoose('{}');
    }
    return parseJsonLoose(text);
  }

  /// `choices[0]` — the `message.content` is the answer; `reasoning_content`
  /// is ignored.
  Map<String, dynamic>? _firstChoice(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      return (choices.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  void dispose() => _client.close();

  // --- helpers (ports of parseJsonLoose / isTransientAiError) ---

  /// Lenient JSON parse for LLM output: strips code fences, extracts the
  /// outermost {...}, and salvages a truncated object.
  static Map<String, dynamic> parseJsonLoose(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'```json\n?|```'), '').trim();
    Map<String, dynamic>? tryParse(String s) {
      try {
        final v = jsonDecode(s);
        return v is Map<String, dynamic> ? v : null;
      } catch (_) {
        return null;
      }
    }

    final direct = tryParse(cleaned);
    if (direct != null) return direct;

    final first = cleaned.indexOf('{');
    final last = cleaned.lastIndexOf('}');
    if (first != -1 && last > first) {
      final block = tryParse(cleaned.substring(first, last + 1));
      if (block != null) return block;
    }

    final salvaged =
        cleaned.replaceAll(RegExp(r',\s*$'), '') +
        (cleaned.contains('{') ? '}' : '');
    return tryParse(salvaged) ?? <String, dynamic>{};
  }

  /// Transient/provider-level failures that should fall through to the next model.
  static bool _isTransient(String msg) {
    final m = msg.toLowerCase();
    return m.contains('400') ||
        m.contains('429') ||
        m.contains('503') ||
        m.contains('404') ||
        m.contains('failed') ||
        m.contains('truncated') ||
        m.contains('socket') ||
        m.contains('timeout') ||
        m.contains('timed out') ||
        m.contains('network') ||
        m.contains('connection');
  }

  static String _trimSlashes(String s) => s.replaceAll(RegExp(r'/+$'), '');
}
