import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../utils/browser_env.dart';

/// Feeds the browser's CSS safe-area insets into [MediaQuery.padding] on the
/// web build, so [SafeArea], `NavigationBar` and every widget that reads
/// `MediaQuery.padding` keep clear of an iPhone's notch and home indicator
/// in an installed (standalone) web app. Flutter web itself always reports
/// zero padding. A pass-through on every other platform.
class WebSafeArea extends StatefulWidget {
  const WebSafeArea({super.key, required this.child});

  final Widget child;

  @override
  State<WebSafeArea> createState() => _WebSafeAreaState();
}

class _WebSafeAreaState extends State<WebSafeArea> with WidgetsBindingObserver {
  EdgeInsets _insets = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    _insets = readCssSafeAreaInsets();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Rotation or entering/leaving standalone changes the insets.
  @override
  void didChangeMetrics() {
    final insets = readCssSafeAreaInsets();
    if (insets != _insets && mounted) setState(() => _insets = insets);
  }

  @override
  void dispose() {
    if (kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _insets == EdgeInsets.zero) return widget.child;
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: withSafeAreaInsets(data, _insets),
      child: widget.child,
    );
  }
}

/// [data] with its view padding raised to at least [insets]; the padding is
/// that minus the keyboard ([MediaQueryData.viewInsets]), as Flutter defines
/// it, so the home-indicator gap isn't added on top of an open keyboard.
MediaQueryData withSafeAreaInsets(MediaQueryData data, EdgeInsets insets) {
  final view = data.viewPadding;
  final viewPadding = EdgeInsets.fromLTRB(
    math.max(view.left, insets.left),
    math.max(view.top, insets.top),
    math.max(view.right, insets.right),
    math.max(view.bottom, insets.bottom),
  );
  final keyboard = data.viewInsets;
  return data.copyWith(
    viewPadding: viewPadding,
    padding: EdgeInsets.fromLTRB(
      math.max(0, viewPadding.left - keyboard.left),
      math.max(0, viewPadding.top - keyboard.top),
      math.max(0, viewPadding.right - keyboard.right),
      math.max(0, viewPadding.bottom - keyboard.bottom),
    ),
  );
}
