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

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: coral,
      onPrimary: Colors.white,
      secondary: coralDeep,
      surface: surface,
      onSurface: Color(0xFFF2F3F5),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: ink,
      fontFamily: null, // system font — renders JP/CN/EN cleanly
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFFF2F3F5),
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceAlt,
        selectedColor: coral,
        side: BorderSide.none,
        labelStyle: const TextStyle(
          color: Color(0xFFCED2DA),
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: coral.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Each category gets a stable colour for pins, chips, and icons.
  static Color categoryColor(PlaceCategory category) => switch (category) {
        PlaceCategory.restaurant => coral,
        PlaceCategory.food => const Color(0xFFFFA23E),
        PlaceCategory.sightseeing => const Color(0xFF4FC3F7),
        PlaceCategory.shopping => const Color(0xFFB388FF),
        PlaceCategory.stay => const Color(0xFF66BB6A),
        PlaceCategory.nightlife => const Color(0xFFEC6CD6),
      };

  static IconData categoryIcon(PlaceCategory category) => switch (category) {
        PlaceCategory.restaurant => Icons.ramen_dining,
        PlaceCategory.food => Icons.local_cafe,
        PlaceCategory.sightseeing => Icons.photo_camera,
        PlaceCategory.shopping => Icons.shopping_bag,
        PlaceCategory.stay => Icons.hotel,
        PlaceCategory.nightlife => Icons.nightlife,
      };
}
