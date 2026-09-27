/// Link intake for the web build, which can't receive native shares.
///
/// Two ways a post link reaches the web app through its URL:
/// - iPhone: an Apple Shortcut in the share sheet opens
///   `https://cheaptripchip.vercel.app/?add=<url-encoded post link>`.
/// - Android: the installed web app's Web Share Target (`share_target` in
///   web/manifest.json) opens `/?title=…&text=…&url=…`.
///
/// Pure Dart (no Flutter/web imports) so it's unit-testable on the VM.
library;

/// Query parameters this intake consumes (and strips from the address bar).
const webShareParams = {'add', 'url', 'text', 'title'};

/// The text to prefill "Add a find" with, from a start URL's query
/// parameters, or null when the URL carries no share.
///
/// `add` wins when present. Otherwise `text` and `url` are combined (Android
/// apps put the link in either, often in `text` along with a caption),
/// dropping `url` when `text` already contains it. `title` is only used when
/// it's all there is — it's usually the app's name, not the post.
String? sharedTextFromQuery(Map<String, String> params) {
  String clean(String? v) => (v ?? '').trim();

  final add = clean(params['add']);
  if (add.isNotEmpty) return add;

  final text = clean(params['text']);
  final url = clean(params['url']);
  final parts = [
    if (text.isNotEmpty) text,
    if (url.isNotEmpty && !text.contains(url)) url,
  ];
  if (parts.isNotEmpty) return parts.join('\n');

  final title = clean(params['title']);
  return title.isEmpty ? null : title;
}

/// [uri] without the share parameters, as a same-origin path for
/// `history.replaceState` — so a reload doesn't add the same find again.
/// Other query parameters and the fragment are kept.
String withoutShareParams(Uri uri) {
  final kept = Map.of(uri.queryParameters)
    ..removeWhere((key, _) => webShareParams.contains(key));
  final query = kept.isEmpty ? '' : '?${Uri(queryParameters: kept).query}';
  final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
  final path = uri.path.isEmpty ? '/' : uri.path;
  return '$path$query$fragment';
}
