import 'package:flutter/material.dart';

const accent = Color(0xFFE8731F); // warm orange

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFFBF7F3) : scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: b == Brightness.light ? Colors.white : scheme.surfaceContainerHigh,
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
      fillColor: b == Brightness.light ? Colors.white : scheme.surfaceContainerHighest,
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
