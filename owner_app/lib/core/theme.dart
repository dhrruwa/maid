import 'package:flutter/material.dart';

// Palette "Espresso & Saffron" (see docs/COLOR_PALETTE.md):
// espresso for buttons and anything carrying text, saffron only for icons,
// borders, tints and progress – white text on saffron fails WCAG contrast.
const brand = Color(0xFF3A2A22); // espresso
const accent = Color(0xFFE8731F); // saffron
const brandDark = Color(0xFFF5A56B); // saffron for dark mode (8.4:1 with dark text)
const appBackground = Color(0xFFFBF6F0);
const appBackgroundDark = Color(0xFF15100D);

ThemeData buildTheme(Brightness b) {
  final light = b == Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
    primary: light ? brand : brandDark,
    onPrimary: light ? Colors.white : const Color(0xFF2A1A10),
    secondaryContainer: light ? const Color(0xFFFCE3CF) : const Color(0xFF5A3A24),
    onSecondaryContainer: light ? brand : const Color(0xFFFFE6D3),
    surface: light ? appBackground : appBackgroundDark,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: light ? appBackground : appBackgroundDark,
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: light ? accent : brandDark,
      linearTrackColor: (light ? accent : brandDark).withValues(alpha: 0.18),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: light ? Colors.white : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: light ? Colors.white : scheme.surfaceContainerHighest,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Status colours (always paired with an icon and a label in the UI).
class StatusColors {
  static const done = Color(0xFF2E9E5B);
  static const partial = Color(0xFFE0A100);
  static const missed = Color(0xFFD64545);
  static const holiday = Color(0xFF3B7DDD);
  static const leave = Color(0xFF8E5BD8);
  static const future = Color(0xFF9E9E9E);
}
