import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/glass.dart';

// Palette "Saffron Glass", same as the owner app (docs/COLOR_PALETTE.md):
// light glass over a warm saffron glow. Buttons are saffron-tinted glass with
// dark espresso text (6.4:1). Plain saffron is never used for text.
const accent = Color(0xFFE8731F); // saffron: icons, rims, glow
const espresso = Color(0xFF2A1B12); // text, and text on saffron buttons
const saffronFill = Color(0xFFEB873E);
const saffronPressed = Color(0xFFE27A2F);
const saffronRim = Color(0xFFC9621A);
const tint = Color(0xFFFFE0C7);
const appBackground = Color(0xFFFFF6EE);

class StatusColors {
  static const done = Color(0xFF2E9E5B);
  static const wait = Color(0xFFE0A100);
  static const missed = Color(0xFFD64545);
  static const holiday = Color(0xFF3B7DDD);
  static const leave = Color(0xFF8E5BD8);
  static const grey = Color(0xFF8A8A8A);
}

/// Big text and big touch targets for a simple, easy app. Light mode.
/// "Light glass": translucent surfaces with a bright rim, but no live blur,
/// so it stays smooth on low-end Android phones.
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light).copyWith(
    primary: const Color(0xFF9A4A12), // burnt saffron: readable on light (5.8:1)
    onPrimary: Colors.white,
    secondaryContainer: tint,
    onSecondaryContainer: espresso,
    surface: appBackground,
    onSurface: espresso,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  // No fontSizeFactor: the base text theme has no sizes yet (Theme.of adds
  // them later), so a factor trips an assert in debug builds (red screen for
  // the whole app) and does nothing in release. Sizes are set per widget.
  final tt = base.textTheme.apply(bodyColor: espresso, displayColor: espresso);
  return base.copyWith(
    textTheme: tt,
    // Every page paints the saffron glow itself (GlassPageTransitionsBuilder).
    scaffoldBackgroundColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: GlassPageTransitionsBuilder(PredictiveBackPageTransitionsBuilder()),
      TargetPlatform.iOS: GlassPageTransitionsBuilder(CupertinoPageTransitionsBuilder()),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: espresso),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white.withValues(alpha: 0.7),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.85)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled)
            ? saffronFill.withValues(alpha: 0.35)
            : s.contains(WidgetState.pressed)
                ? saffronPressed
                : saffronFill),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? espresso.withValues(alpha: 0.45) : espresso),
        overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.14)),
        side: WidgetStatePropertyAll(BorderSide(color: saffronRim.withValues(alpha: 0.85))),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(56, 60)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        foregroundBuilder: (context, states, child) => GlassHighlight(radius: 18, child: child!),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 58),
        foregroundColor: espresso,
        backgroundColor: Colors.white.withValues(alpha: 0.62),
        side: BorderSide(color: saffronRim.withValues(alpha: 0.35)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xF7FFF8F2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFAFFF8F2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.8),
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
