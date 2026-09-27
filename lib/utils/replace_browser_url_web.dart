import 'dart:js_interop';

@JS('window.history.state')
external JSAny? get _historyState;

@JS('window.history.replaceState')
external void _replaceState(JSAny? data, JSString unused, JSString url);

/// Rewrites the address bar to [url] (same origin) without a reload or a new
/// history entry. Keeps `history.state` as is — Flutter's router stores its
/// own state there and throws on the next navigation if it's wiped.
void replaceBrowserUrl(String url) {
  try {
    _replaceState(_historyState, ''.toJS, url.toJS);
  } catch (_) {
    // Cosmetic only — a failure just leaves the query in the address bar.
  }
}
