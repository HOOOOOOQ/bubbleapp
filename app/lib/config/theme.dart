import 'package:flutter/material.dart';

/// BubbleApp colour system, taken from the brand specification.
class BubbleColors {
  const BubbleColors._();

  // Primary palette
  static const Color blue = Color(0xFF398BFF);
  static const Color sky = Color(0xFF65C7FF);
  static const Color violet = Color(0xFF9065FF);
  static const Color indigo = Color(0xFF7055F5);

  // Light mode
  static const Color lightBackground = Color(0xFFF5F7FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF172033);
  static const Color lightSecondaryText = Color(0xFF8993A7);

  // Dark mode
  static const Color darkBackground = Color(0xFF090D18);
  static const Color darkSurface = Color(0xFF121A2A);
  static const Color darkSecondarySurface = Color(0xFF1A2437);
  static const Color darkText = Color(0xFFF5F7FF);
  static const Color darkSecondaryText = Color(0xFF929DB2);

  // Semantic
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, sky],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, indigo],
  );
}

class BubbleTheme {
  const BubbleTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? BubbleColors.darkBackground : BubbleColors.lightBackground;
    final surface = isDark ? BubbleColors.darkSurface : BubbleColors.lightSurface;
    final text = isDark ? BubbleColors.darkText : BubbleColors.lightText;
    final secondary = isDark ? BubbleColors.darkSecondaryText : BubbleColors.lightSecondaryText;

    final scheme = ColorScheme.fromSeed(
      seedColor: BubbleColors.blue,
      brightness: brightness,
      primary: BubbleColors.blue,
      secondary: BubbleColors.violet,
      surface: surface,
      onSurface: text,
      error: BubbleColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: null,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: text,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withOpacity(0.92),
        indicatorColor: BubbleColors.blue.withOpacity(0.14),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondary),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? BubbleColors.darkSecondarySurface : BubbleColors.lightBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        shape: const StadiumBorder(),
        backgroundColor: isDark ? BubbleColors.darkSecondarySurface : BubbleColors.lightBackground,
      ),
      dividerTheme: DividerThemeData(
        color: secondary.withOpacity(0.15),
        space: 1,
        thickness: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
