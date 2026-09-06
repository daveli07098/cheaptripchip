import 'package:flutter/material.dart';

import '../models/place.dart';

/// Visual direction (see ANALYSIS.md → UI / Design References):
/// map-first, dark map tiles, coral/pink accent so pins pop, clean photo-led
/// cards, bilingual-friendly system typography.
class AppTheme {
  AppTheme._();

  /// Coral/pink accent — reads "travel/food", matches the map-pin colour.
  static const Color coral = Color(0xFFFF5A6E);
  static const Color coralDeep = Color(0xFFE63E55);

  static const Color ink = Color(0xFF15171C);
  static const Color surface = Color(0xFF1E2127);
  static const Color surfaceAlt = Color(0xFF272B33);
  static const Color hairline = Color(0xFF333842);

  // --- Light palette -------------------------------------------------------
  // Mirrors the dark palette above so both themes share structure (scaffold /
  // card / alt-surface / hairline), tuned to sit behind the same coral accent.

  /// Near-white scaffold background — off-white rather than pure white so
  /// coral accents and photos don't feel like they're floating on a glare.
  static const Color inkLight = Color(0xFFFAFAFB);

  /// Card / sheet surface — pure white for max contrast against [inkLight].
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Alt surface for unselected chips, input fills, etc. — a soft grey a
  /// notch below white so it reads as a distinct layer without any tint.
  static const Color surfaceAltLight = Color(0xFFF0F1F3);

  /// Divider / border colour for the light theme — subtle grey, the light
  /// counterpart to [hairline].
  static const Color hairlineLight = Color(0xFFE1E3E8);

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    scaffoldBackground: ink,
    cardSurface: surface,
    altSurface: surfaceAlt,
    hairlineColor: hairline,
    onSurfaceColor: const Color(0xFFF2F3F5),
    mutedTextColor: const Color(0xFFCED2DA),
    chipLabelColor: const Color(0xFFCED2DA),
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    scaffoldBackground: inkLight,
    cardSurface: surfaceLight,
    altSurface: surfaceAltLight,
    hairlineColor: hairlineLight,
    onSurfaceColor: ink,
    mutedTextColor: ink.withValues(alpha: 0.6),
    chipLabelColor: ink.withValues(alpha: 0.7),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffoldBackground,
    required Color cardSurface,
    required Color altSurface,
    required Color hairlineColor,
    required Color onSurfaceColor,
    required Color mutedTextColor,
    required Color chipLabelColor,
  }) {
    final scheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: coral,
            onPrimary: Colors.white,
            secondary: coralDeep,
            surface: cardSurface,
            onSurface: onSurfaceColor,
            surfaceContainerHighest: altSurface,
            outline: hairlineColor,
          )
        : ColorScheme.light(
            primary: coral,
            onPrimary: Colors.white,
            secondary: coralDeep,
            surface: cardSurface,
            onSurface: onSurfaceColor,
            surfaceContainerHighest: altSurface,
            outline: hairlineColor,
          );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      fontFamily: null, // system font — renders JP/CN/EN cleanly
    );

    final textTheme = base.textTheme.apply(
      bodyColor: onSurfaceColor,
      displayColor: onSurfaceColor,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurfaceColor,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: altSurface,
        selectedColor: coral,
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: chipLabelColor,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardSurface,
        indicatorColor: coral.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Each category gets a stable colour for pins, chips, and icons, tuned
  /// per [Brightness] so pins/chips keep enough contrast against the
  /// scaffold (the dark-tuned hues wash out on a near-white background).
  static Color categoryColor(
    PlaceCategory category, [
    Brightness b = Brightness.dark,
  ]) => b == Brightness.dark
      ? _categoryColorDark(category)
      : _categoryColorLight(category);

  static Color _categoryColorDark(PlaceCategory category) => switch (category) {
    PlaceCategory.restaurant => coral,
    PlaceCategory.cafe => const Color(0xFFC08552),
    PlaceCategory.food => const Color(0xFFFFA23E),
    PlaceCategory.sightseeing => const Color(0xFF4FC3F7),
    PlaceCategory.shopping => const Color(0xFFB388FF),
    PlaceCategory.stay => const Color(0xFF66BB6A),
    PlaceCategory.nightlife => const Color(0xFFEC6CD6),
  };

  /// Darker/more-saturated siblings of the dark-tuned hues above, chosen for
  /// AA-ish contrast against [inkLight]/[surfaceLight].
  static Color _categoryColorLight(PlaceCategory category) =>
      switch (category) {
        PlaceCategory.restaurant => coralDeep,
        PlaceCategory.cafe => const Color(0xFF8B5A2B),
        PlaceCategory.food => const Color(0xFFCC6F00),
        PlaceCategory.sightseeing => const Color(0xFF0277BD),
        PlaceCategory.shopping => const Color(0xFF6200EA),
        PlaceCategory.stay => const Color(0xFF2E7D32),
        PlaceCategory.nightlife => const Color(0xFFAD1457),
      };

  static IconData categoryIcon(PlaceCategory category) => switch (category) {
    PlaceCategory.restaurant => Icons.ramen_dining,
    PlaceCategory.cafe => Icons.local_cafe,
    PlaceCategory.food => Icons.local_cafe,
    PlaceCategory.sightseeing => Icons.photo_camera,
    PlaceCategory.shopping => Icons.shopping_bag,
    PlaceCategory.stay => Icons.hotel,
    PlaceCategory.nightlife => Icons.nightlife,
  };

  /// OSM's standard tile server, overridable via `--dart-define=MAP_TILE_URL=...`
  /// (or env/dev.json) for a keyed provider. The CartoDB Dark/Light Matter
  /// tiles this used to point at now watermark "API KEY REQUIRED" for
  /// unauthenticated use, so this falls back to OSM directly.
  ///
  /// IMPORTANT: OSM's tile usage policy (https://operations.osmfoundation.org/policies/tiles/)
  /// allows development/light use only — set `MAP_TILE_URL` to a keyed
  /// provider (Mapbox, Stadia, MapTiler, etc.) before release.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Attribution text required by the OSM tile licence; see
  /// `_AttributionBar` in map_screen.dart for where it's rendered.
  static const String mapAttribution = '© OpenStreetMap contributors';
}
