import 'package:flutter/material.dart';

/// In-memory runtime store for the user's chosen [ThemeMode].
///
/// This is runtime STATE (so the app re-themes immediately without a
/// restart), not persistence. The choice does not survive an app restart
/// yet — that's a job for `shared_preferences` (planned; not a dependency
/// yet). When that lands, read the saved mode on startup and write it in
/// [set]/[toggle]; the screens listen via [ValueListenableBuilder] and
/// won't change.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);
  static final ThemeController instance = ThemeController._();

  /// Cycles system → light → dark → system.
  void toggle() {
    value = switch (value) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
  }

  /// Sets the theme mode directly.
  void set(ThemeMode mode) {
    value = mode;
  }
}
