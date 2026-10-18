// The web "Add to Home Screen" hint's decision, and the safe-area padding
// fed into MediaQuery on the web build.
import 'package:cheaptripchip/widgets/install_hint.dart';
import 'package:cheaptripchip/widgets/web_safe_area.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _iphoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 '
    'Safari/604.1';
const _iphoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.54 '
    'Mobile/15E148 Safari/604.1';
const _iphoneInstagram =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram '
    '338.0.0.13.104';
const _ipadSafari =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Safari/605.1.15';
const _androidChrome =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

bool _show(
  String ua, {
  bool isWeb = true,
  int touch = 5,
  bool? standalone = false,
  bool displayMode = false,
  bool dismissed = false,
}) => shouldShowInstallHint(
  isWeb: isWeb,
  userAgent: ua,
  maxTouchPoints: touch,
  navigatorStandalone: standalone,
  displayModeStandalone: displayMode,
  dismissed: dismissed,
);

void main() {
  group('shouldShowInstallHint', () {
    test('iPhone Safari in the browser: yes', () {
      expect(_show(_iphoneSafari), isTrue);
    });

    test('already installed (either signal): no', () {
      expect(_show(_iphoneSafari, standalone: true), isFalse);
      expect(_show(_iphoneSafari, displayMode: true), isFalse);
    });

    test('dismissed or not the web build: no', () {
      expect(_show(_iphoneSafari, dismissed: true), isFalse);
      expect(_show(_iphoneSafari, isWeb: false), isFalse);
    });

    test('other iOS browsers and in-app browsers: no', () {
      expect(_show(_iphoneChrome), isFalse);
      expect(_show(_iphoneInstagram), isFalse);
    });

    test('iPadOS Safari (desktop UA + touch): yes; a Mac: no', () {
      expect(_show(_ipadSafari, standalone: null), isTrue);
      expect(_show(_ipadSafari, touch: 0, standalone: null), isFalse);
    });

    test('Android: no', () {
      expect(_show(_androidChrome, standalone: null), isFalse);
    });
  });

  group('withSafeAreaInsets', () {
    const insets = EdgeInsets.only(top: 47, bottom: 34);

    test('raises padding and view padding to the insets', () {
      final data = withSafeAreaInsets(const MediaQueryData(), insets);
      expect(data.padding, insets);
      expect(data.viewPadding, insets);
    });

    test('the keyboard swallows the home-indicator gap', () {
      final data = withSafeAreaInsets(
        const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
        insets,
      );
      expect(data.viewPadding.bottom, 34);
      expect(data.padding.bottom, 0);
      expect(data.padding.top, 47);
    });

    test('keeps a larger padding the platform already reports', () {
      final data = withSafeAreaInsets(
        const MediaQueryData(
          padding: EdgeInsets.only(top: 59),
          viewPadding: EdgeInsets.only(top: 59),
        ),
        insets,
      );
      expect(data.padding.top, 59);
    });
  });
}
