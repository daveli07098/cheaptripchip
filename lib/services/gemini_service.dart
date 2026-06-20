import 'dart:convert';

import 'package:http/http.dart' as http;

/// Dart port of the event-calendar Gemini client (`src/lib/ai/client.ts`).
///
/// Same shape: direct REST calls to the Generative Language API, JSON mode with
/// temperature 0 for deterministic extraction, a model cascade that falls
/// through on transient errors, and lenient JSON parsing of the model output.
///
/// Config is read from compile-time `--dart-define`s so no key is hard-coded:
///   flutter run --dart-define=GEMINI_API_KEY=xxx
///   flutter run --dart-define=GEMINI_API_KEY=xxx \
///               --dart-define=GEMINI_BASE_URL=https://your-proxy.workers.dev
///
/// SECURITY NOTE: shipping a Gemini key inside a client app exposes it. For
/// production, point [baseUrl] at YOUR backend/proxy (the same role
/// `GEMINI_BASE_URL` plays in event-calendar to dodge the HK geo-block) and let
/// the server hold the real key. This client is wired so that swap is config-only.
class GeminiService {
  GeminiService({
    String? apiKey,
    String? baseUrl,
    List<String>? models,
    http.Client? client,
  })  : apiKey = apiKey ?? _envApiKey,
        baseUrl = _trimSlashes(baseUrl ?? _envBaseUrl),
        models = models ?? defaultModels,
        _client = client ?? http.Client();

  static const _envApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _envBaseUrl = String.fromEnvironment(
    'GEMINI_BASE_URL',
    defaultValue: 'https://generativelanguage.googleapis.com',
  );

  /// Cascade priority order, mirroring event-calendar's GEMINI_POOL
  /// (strongest / most-available first). Lite models are cheap fallbacks.
  static const List<String> defaultModels = [
    'gemini-3.5-flash',
    'gemini-3.1-flash-lite',
    'gemini-3-flash',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
  ];

  final String apiKey;
  final String baseUrl;
  final List<String> models;
  final http.Client _client;

  bool get isConfigured => apiKey.isNotEmpty;

  /// Run a JSON-extraction prompt through the model cascade. Tries each model in
  /// order; transient failures (429/503/network) fall through to the next.
  /// Throws if nothing is configured or every model fails.
  Future<Map<String, dynamic>> extractJson(String prompt) async {
    if (!isConfigured) {
      throw StateError(
        'No GEMINI_API_KEY configured. Pass it via --dart-define=GEMINI_API_KEY=...',
      );
    }

    final failures = <String>[];
    for (final model in models) {
      try {
        return await _callJson(prompt, model);
      } catch (e) {
        final msg = e.toString();
        failures.add(msg);
        if (!_isTransient(msg)) rethrow; // hard error — stop the cascade
        // transient → try the next model
      }
    }
    final unique = failures.toSet().take(2).join(' | ');
    throw Exception(unique.isEmpty ? 'All Gemini models failed' : unique);
  }

  Future<Map<String, dynamic>> _callJson(String prompt, String model) async {
    final uri = Uri.parse('$baseUrl/v1beta/models/$model:generateContent?key=$apiKey');
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      // temperature 0 → deterministic extraction (same rationale as the TS client).
      'generationConfig': {
        'responseMimeType': 'application/json',
        'maxOutputTokens': 2048,
        'temperature': 0,
      },
    });

    http.Response? res;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      res = await _client
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200 || res.statusCode != 503) break;
    }

    if (res == null || res.statusCode != 200) {
      // Surface the API's own message (e.g. "User location is not supported")
      // so cascade failures are diagnosable, not just status codes.
      var detail = '';
      try {
        final err = jsonDecode(res?.body ?? '') as Map<String, dynamic>;
        final m = (err['error'] as Map?)?['message'];
        if (m is String) detail = ' — $m';
      } catch (_) {/* non-JSON error body */}
      throw Exception('Gemini API error: ${res?.statusCode ?? 'unknown'}$detail');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = _firstText(data) ?? '{}';
    return parseJsonLoose(raw);
  }

  String? _firstText(Map<String, dynamic> data) {
    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final parts = (candidates.first as Map)['content']?['parts'];
      if (parts is List && parts.isNotEmpty) {
        return (parts.first as Map)['text'] as String?;
      }
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
        cleaned.replaceAll(RegExp(r',\s*$'), '') + (cleaned.contains('{') ? '}' : '');
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
        m.contains('socket') ||
        m.contains('timeout') ||
        m.contains('timed out') ||
        m.contains('network') ||
        m.contains('connection');
  }

  static String _trimSlashes(String s) => s.replaceAll(RegExp(r'/+$'), '');
}
