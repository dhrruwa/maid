import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Palette "Espresso & Saffron", same as the owner app (see docs/COLOR_PALETTE.md):
// espresso for buttons and text, saffron only for icons, borders and tints.
const brand = Color(0xFF3A2A22); // espresso
const accent = Color(0xFFE8731F); // saffron
const appBackground = Color(0xFFFBF6F0);

class StatusColors {
  static const done = Color(0xFF2E9E5B);
  static const wait = Color(0xFFE0A100);
  static const missed = Color(0xFFD64545);
  static const holiday = Color(0xFF3B7DDD);
  static const leave = Color(0xFF8E5BD8);
  static const grey = Color(0xFF8A8A8A);
}

/// Big text and big touch targets for a simple, easy app. Light mode.
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light).copyWith(
    primary: brand,
    onPrimary: Colors.white,
    secondaryContainer: const Color(0xFFFCE3CF),
    onSecondaryContainer: brand,
    surface: appBackground,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final tt = base.textTheme.apply(fontSizeFactor: 1.12);
  return base.copyWith(
    textTheme: tt,
    scaffoldBackgroundColor: appBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: appBackground,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.black87),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(56, 60),
        textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 58),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String rupees(num? v) => _rupee.format(v ?? 0);

DateTime istNow() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
String istDate([int addDays = 0]) {
  final n = istNow().add(Duration(days: addDays));
  return DateFormat('yyyy-MM-dd').format(n);
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
