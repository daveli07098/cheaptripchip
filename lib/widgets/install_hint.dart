import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../utils/browser_env.dart';

/// Whether to show the one-time "Add to Home Screen" hint: only in the web
/// build, only in iPhone/iPad Safari (the one browser that can install the
/// web app there — Chrome/Firefox/Edge on iOS and in-app browsers such as
/// Instagram's can't), only when not already running installed
/// (standalone), and only until dismissed. Pure, so it's unit-testable.
bool shouldShowInstallHint({
  required bool isWeb,
  required String userAgent,
  int maxTouchPoints = 0,
  bool? navigatorStandalone,
  bool displayModeStandalone = false,
  required bool dismissed,
}) {
  if (!isWeb || dismissed) return false;
  if (navigatorStandalone == true || displayModeStandalone) return false;
  return isIosSafari(userAgent, maxTouchPoints: maxTouchPoints);
}

/// iPhone/iPod/iPad Safari. iPadOS Safari sends a desktop ("Macintosh") user
/// agent, told apart from a Mac by its touch points. Safari's UA carries a
/// `Safari/` token, which in-app browsers lack; other iOS browsers add their
/// own token.
bool isIosSafari(String userAgent, {int maxTouchPoints = 0}) {
  final ios =
      RegExp(r'iPhone|iPad|iPod').hasMatch(userAgent) ||
      (userAgent.contains('Macintosh') && maxTouchPoints > 1);
  if (!ios || !userAgent.contains('Safari/')) return false;
  return !RegExp(r'CriOS|FxiOS|EdgiOS|OPiOS|GSA/').hasMatch(userAgent);
}

/// Persists the hint's dismissal under [_prefsKey].
abstract final class InstallHintPrefs {
  static const _prefsKey = 'install_hint_dismissed';

  /// Unreadable prefs count as dismissed — the hint is optional.
  static Future<bool> dismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> dismiss() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
    } catch (_) {
      // Shown again next launch — harmless.
    }
  }
}

/// Decides, once, whether this browser should see the hint. Fails silently
/// (false) when the browser can't be read.
Future<bool> installHintWanted() async {
  if (!kIsWeb) return false;
  final env = readBrowserEnv();
  if (env == null) return false;
  return shouldShowInstallHint(
    isWeb: kIsWeb,
    userAgent: env.userAgent,
    maxTouchPoints: env.maxTouchPoints,
    navigatorStandalone: env.navigatorStandalone,
    displayModeStandalone: env.displayModeStandalone,
    dismissed: await InstallHintPrefs.dismissed(),
  );
}

/// Slim dismissible banner, shown above the bottom navigation in iPhone
/// Safari: how to install the web app (Share → Add to Home Screen).
class InstallHintBanner extends StatelessWidget {
  const InstallHintBanner({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: [
            const Icon(Icons.ios_share, size: 20, color: AppTheme.coral),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Install the app: tap Share, then "Add to Home Screen".',
                style: TextStyle(fontSize: 13.5, height: 1.3),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close, size: 20),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
