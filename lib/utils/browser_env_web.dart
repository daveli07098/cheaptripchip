import 'dart:js_interop';

import 'package:flutter/widgets.dart';

import 'browser_env_stub.dart' show BrowserEnv;

export 'browser_env_stub.dart' show BrowserEnv;

@JS('window.navigator.userAgent')
external JSString? get _userAgent;

@JS('window.navigator.maxTouchPoints')
external JSNumber? get _maxTouchPoints;

// Undefined outside iOS Safari, which reads as null here.
@JS('window.navigator.standalone')
external JSBoolean? get _standalone;

@JS('window.matchMedia')
external _MediaQueryList _matchMedia(JSString query);

extension type _MediaQueryList._(JSObject _) implements JSObject {
  external bool get matches;
}

@JS('document.getElementById')
external JSObject? _getElementById(JSString id);

@JS('window.getComputedStyle')
external _CssStyle _getComputedStyle(JSObject element);

extension type _CssStyle._(JSObject _) implements JSObject {
  external JSString getPropertyValue(JSString name);
}

/// Reads the browser's user agent and install state. Never throws — a
/// missing API reads as "not standalone".
BrowserEnv? readBrowserEnv() {
  try {
    bool displayMode;
    try {
      displayMode = _matchMedia('(display-mode: standalone)'.toJS).matches;
    } catch (_) {
      displayMode = false;
    }
    return BrowserEnv(
      userAgent: _userAgent?.toDart ?? '',
      maxTouchPoints: _maxTouchPoints?.toDartInt ?? 0,
      navigatorStandalone: _standalone?.toDart,
      displayModeStandalone: displayMode,
    );
  } catch (_) {
    return null;
  }
}

/// The CSS `env(safe-area-inset-*)` values, read from the hidden
/// `#safe-area-probe` element in web/index.html (its padding is set to those
/// insets). Flutter web always reports zero [MediaQuery.padding], so with
/// `viewport-fit=cover` an installed iPhone web app would otherwise draw
/// under the notch and home indicator. Zero when the probe is missing.
EdgeInsets readCssSafeAreaInsets() {
  try {
    final probe = _getElementById('safe-area-probe'.toJS);
    if (probe == null) return EdgeInsets.zero;
    final style = _getComputedStyle(probe);
    double px(String side) =>
        double.tryParse(
          style
              .getPropertyValue('padding-$side'.toJS)
              .toDart
              .replaceAll('px', '')
              .trim(),
        ) ??
        0;
    return EdgeInsets.fromLTRB(
      px('left'),
      px('top'),
      px('right'),
      px('bottom'),
    );
  } catch (_) {
    return EdgeInsets.zero;
  }
}
