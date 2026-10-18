import 'package:flutter/widgets.dart';

/// What the browser reports about itself — null outside the browser.
/// See browser_env_web.dart.
class BrowserEnv {
  const BrowserEnv({
    required this.userAgent,
    required this.maxTouchPoints,
    required this.navigatorStandalone,
    required this.displayModeStandalone,
  });

  final String userAgent;
  final int maxTouchPoints;

  /// iOS Safari's non-standard `navigator.standalone`; null elsewhere.
  final bool? navigatorStandalone;

  /// `matchMedia('(display-mode: standalone)').matches`.
  final bool displayModeStandalone;
}

/// No browser outside the web build.
BrowserEnv? readBrowserEnv() => null;

/// No CSS safe-area insets outside the web build — native platforms report
/// them through [MediaQuery] already.
EdgeInsets readCssSafeAreaInsets() => EdgeInsets.zero;
