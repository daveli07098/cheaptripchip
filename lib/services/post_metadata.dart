import 'dart:async';

import 'package:http/http.dart' as http;

/// True when compiled for web — same check as Flutter's `foundation.kIsWeb`
/// (`bool.fromEnvironment('dart.library.js_interop')`, true whenever the web
/// compiler defines that library, for both dart2js/dartdevc and dart2wasm),
/// duplicated here so this file stays pure Dart with no Flutter import. That
/// matters twice: [fetchPostMetadata] is called from web builds too (where it
/// must no-op, see below) and this file needs to be plain-`dart run`-able for
/// manual checks against real posts.
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Crawler UA that Instagram/TikTok serve public og:meta tags to, instead of
/// the login-wall shell a normal browser UA gets. Verified with curl against
/// public IG posts (see place_extractor.dart doc comment).
const _crawlerUserAgent =
    'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';

/// Metadata scraped from an Instagram/TikTok post's `<meta>` tags.
class PostMetadata {
  const PostMetadata({this.title, this.description, this.author});

  /// Raw `og:title`, e.g. `Name on Instagram: "caption text"`.
  final String? title;

  /// Raw `og:description` (falls back to `<meta name="description">`), e.g.
  /// `123 likes, 4 comments - handle on Month Day, Year: "caption…"`.
  final String? description;

  /// Author handle parsed from [description], e.g. `@handle`. Null if it
  /// couldn't be parsed (TikTok's description doesn't carry one reliably).
  final String? author;

  /// Best-effort caption text: the untruncated text inside [title]'s quotes
  /// when present (Instagram), else the text after [description]'s
  /// `"<handle> on <date>: "` prefix (also Instagram, but truncated), else
  /// [description] verbatim (TikTok, which has no such prefix).
  String? get caption {
    final fromTitle = _captionFromTitle(title);
    if (fromTitle != null && fromTitle.isNotEmpty) return fromTitle;
    final fromDescription = _captionFromDescription(description);
    if (fromDescription != null && fromDescription.isNotEmpty) {
      return fromDescription;
    }
    final raw = description?.trim();
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }
}

final RegExp _igTitleMarker = RegExp(
  r'on Instagram:\s*"',
  caseSensitive: false,
);

String? _captionFromTitle(String? title) {
  if (title == null) return null;
  final marker = _igTitleMarker.firstMatch(title);
  if (marker == null) return null;
  final afterMarker = title.substring(marker.end);
  final lastQuote = afterMarker.lastIndexOf('"');
  return (lastQuote == -1 ? afterMarker : afterMarker.substring(0, lastQuote))
      .trim();
}

// e.g. "123 likes, 4 comments - rame.nbon on March 3, 2024: \"caption…"
final RegExp _descAuthorMarker = RegExp(
  r'-\s*(\S+)\s+on\s+\w+\s+\d{1,2},\s+\d{4}:\s*"',
);

String? _captionFromDescription(String? description) {
  if (description == null) return null;
  final m = _descAuthorMarker.firstMatch(description);
  if (m == null) return null;
  var rest = description.substring(m.end).trim();
  if (rest.endsWith('"')) rest = rest.substring(0, rest.length - 1);
  return rest.replaceAll(RegExp(r'…+$'), '').trim();
}

String? _authorFromDescription(String? description) {
  if (description == null) return null;
  final handle = _descAuthorMarker.firstMatch(description)?.group(1);
  if (handle == null || handle.isEmpty) return null;
  return handle.startsWith('@') ? handle : '@$handle';
}

/// Whether [uri] is a post page these crawler-UA fetches are meaningful for:
/// Instagram post/reel/tv permalinks, or any TikTok URL (including the
/// vm./vt. short-link hosts, which redirect to the real video page — the
/// `http` client follows redirects by default).
bool isSupportedPostUrl(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host == 'instagram.com' || host.endsWith('.instagram.com')) {
    return RegExp(r'^/(p|reel|reels|tv)/[^/]+/?').hasMatch(uri.path);
  }
  return host == 'tiktok.com' ||
      host.endsWith('.tiktok.com') ||
      host == 'vm.tiktok.com' ||
      host == 'vt.tiktok.com';
}

/// First Instagram/TikTok post URL found in free-form [text] (share text can
/// carry extra words around the link), or null if none. Trims trailing
/// punctuation a sentence might tack on after the URL.
String? extractFirstPostUrl(String text) {
  final urlPattern = RegExp(r'''https?://[^\s<>"']+''');
  for (final m in urlPattern.allMatches(text)) {
    final candidate = m.group(0)!.replaceAll(RegExp(r'''[.,)\]]+$'''), '');
    final uri = Uri.tryParse(candidate);
    if (uri != null && isSupportedPostUrl(uri)) return candidate;
  }
  return null;
}

final RegExp _metaTagPattern = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
// dotAll: a caption embedded in `content="..."` can itself contain literal
// newlines (multi-line IG captions render that way in the raw HTML), and
// `.` doesn't match `\n` by default.
final RegExp _metaKeyPattern = RegExp(
  '''(?:property|name)\\s*=\\s*(["'])(.*?)\\1''',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _metaContentPattern = RegExp(
  '''content\\s*=\\s*(["'])(.*?)\\1''',
  caseSensitive: false,
  dotAll: true,
);

const _wantedMetaKeys = {'og:title', 'og:description', 'description'};

Map<String, String> _parseMetaTags(String html) {
  final result = <String, String>{};
  for (final tagMatch in _metaTagPattern.allMatches(html)) {
    final tag = tagMatch.group(0)!;
    final key = _metaKeyPattern.firstMatch(tag)?.group(2)?.toLowerCase();
    final content = _metaContentPattern.firstMatch(tag)?.group(2);
    if (key == null || content == null || !_wantedMetaKeys.contains(key)) {
      continue;
    }
    result.putIfAbsent(key, () => _unescapeHtml(content));
  }
  return result;
}

final RegExp _entityPattern = RegExp(r'&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);');

const Map<String, String> _namedEntities = {
  'amp': '&',
  'quot': '"',
  'apos': "'",
  'lt': '<',
  'gt': '>',
  'nbsp': ' ',
};

/// HTML-unescapes [s] in a single pass (so e.g. `&amp;quot;` correctly
/// becomes the literal text `&quot;`, not a decoded `"`). Handles named
/// entities, decimal (`&#064;`) and hex (`&#x2019;`, `&#x1F35C;`) numeric
/// refs — [String.fromCharCode] emits the right UTF-16 surrogate pair for
/// code points above the BMP (emoji), so no special-casing needed there.
String _unescapeHtml(String s) {
  return s.replaceAllMapped(_entityPattern, (m) {
    final body = m.group(1)!;
    if (body.startsWith('#x') || body.startsWith('#X')) {
      final code = int.tryParse(body.substring(2), radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    }
    if (body.startsWith('#')) {
      final code = int.tryParse(body.substring(1));
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    }
    return _namedEntities[body.toLowerCase()] ?? m.group(0)!;
  });
}

/// Fetches [url]'s og:meta tags via a crawler User-Agent and returns the
/// parsed [PostMetadata], or null when the page has no usable tags — a
/// non-200 status, a request timeout, a network error, or (on web) always,
/// since browsers can't fetch these cross-origin pages at all (CORS).
///
/// Only meaningful for [isSupportedPostUrl] URLs; returns null for anything
/// else without making a request.
Future<PostMetadata?> fetchPostMetadata(
  Uri url, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (_isWeb) return null;
  if (!isSupportedPostUrl(url)) return null;

  final ownsClient = client == null;
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(url, headers: {'User-Agent': _crawlerUserAgent})
        .timeout(timeout);
    if (res.statusCode != 200) return null;
    final tags = _parseMetaTags(res.body);
    final title = tags['og:title'];
    final description = tags['og:description'] ?? tags['description'];
    if (title == null && description == null) return null;
    return PostMetadata(
      title: title,
      description: description,
      author: _authorFromDescription(description),
    );
  } on Exception {
    // Timeout, socket error, malformed response — caller proceeds without
    // a caption rather than failing the whole extraction.
    return null;
  } finally {
    if (ownsClient) c.close();
  }
}
