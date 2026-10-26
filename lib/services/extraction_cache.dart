import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A cached AI extraction for one post: the raw model JSON (before
/// geocoding — place ids are timestamped, so [Place]s aren't cached) plus
/// the caption/author the post page yielded, which fill in fields AI
/// left blank.
class CachedExtraction {
  const CachedExtraction({required this.json, this.caption, this.author});

  final Map<String, dynamic> json;
  final String? caption;
  final String? author;
}

/// On-device cache of extractions keyed by normalized post URL (see
/// `normalizePostUrl`), so sharing the same reel twice costs one AI
/// call. Implementations must never throw — a cache failure just means a
/// fresh extraction.
abstract class ExtractionCache {
  Future<CachedExtraction?> read(String key);
  Future<void> write(String key, CachedExtraction value);
}

/// In-memory [ExtractionCache] (tests, or a session-only cache).
class MemoryExtractionCache implements ExtractionCache {
  final entries = <String, CachedExtraction>{};

  @override
  Future<CachedExtraction?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, CachedExtraction value) async =>
      entries[key] = value;
}

/// [ExtractionCache] in shared_preferences: one JSON map under [prefsKey],
/// at most [maxEntries] (oldest dropped first), entries older than [ttl]
/// ignored. Plugin errors (e.g. no platform channel in a test harness) are
/// swallowed.
class SharedPrefsExtractionCache implements ExtractionCache {
  SharedPrefsExtractionCache({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const prefsKey = 'extraction_cache_v1';
  static const maxEntries = 100;
  static const ttl = Duration(days: 30);

  final DateTime Function() _now;

  Future<Map<String, dynamic>> _load(SharedPreferences prefs) async {
    final raw = prefs.getString(prefsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {}; // corrupt — start over rather than never caching again
    }
  }

  @override
  Future<CachedExtraction?> read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entry = (await _load(prefs))[key];
      if (entry is! Map) return null;
      final at = DateTime.tryParse('${entry['at']}');
      if (at == null || _now().difference(at) > ttl) return null;
      final json = entry['json'];
      if (json is! Map) return null;
      return CachedExtraction(
        json: Map<String, dynamic>.from(json),
        caption: entry['caption'] as String?,
        author: entry['author'] as String?,
      );
    } catch (e) {
      debugPrint('extraction cache read failed: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, CachedExtraction value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = await _load(prefs)
        ..remove(key); // re-insert last = newest
      all[key] = {
        'at': _now().toIso8601String(),
        'json': value.json,
        'caption': value.caption,
        'author': value.author,
      };
      while (all.length > maxEntries) {
        all.remove(all.keys.first);
      }
      await prefs.setString(prefsKey, jsonEncode(all));
    } catch (e) {
      debugPrint('extraction cache write failed: $e');
    }
  }
}
