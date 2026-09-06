import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime store for the user's chosen [ThemeMode], persisted via
/// `shared_preferences`.
///
/// This is runtime STATE (so the app re-themes immediately without a
/// restart) that is also write-through persisted: [set]/[toggle] save the
/// choice under [_prefsKey] (fire-and-forget), and [load] restores it on
/// startup before the first frame. The screens listen via
/// [ValueListenableBuilder] and don't need to change.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);
  static final ThemeController instance = ThemeController._();

  static const _prefsKey = 'theme_mode';

  /// Reads the persisted theme mode (if any) and applies it without writing
  /// it straight back out again — call once at startup, before [runApp].
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored == null) return;
      final mode = ThemeMode.values.asNameMap()[stored];
      if (mode != null && mode != value) {
        value = mode;
      }
    } catch (e) {
      debugPrint('ThemeController.load failed: $e');
    }
  }

  /// Cycles system → light → dark → system.
  void toggle() {
    set(switch (value) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    });
  }

  /// Sets the theme mode directly and persists the choice.
  void set(ThemeMode mode) {
    value = mode;
    _save(mode);
  }

  Future<void> _save(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (e) {
      debugPrint('ThemeController._save failed: $e');
    }
  }
}
