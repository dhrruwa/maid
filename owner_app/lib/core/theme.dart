import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../widgets/glass.dart';

// Palette "Saffron Glass" (docs/COLOR_PALETTE.md): frosted glass over a warm
// saffron glow. Main buttons are saffron-tinted glass with dark espresso text
// (6.4:1). Plain saffron is never used for text – `ink` (burnt saffron) is.
const accent = Color(0xFFE8731F); // saffron: icons, rims, progress, glow
const ink = Color(0xFF9A4A12); // burnt saffron: text buttons, links, selection (5.8:1)
const espresso = Color(0xFF2A1B12); // body text, and text on saffron buttons
const saffronFill = Color(0xFFEB873E); // saffron glass button
const saffronPressed = Color(0xFFE27A2F);
const saffronRim = Color(0xFFC9621A);
const tint = Color(0xFFFFE0C7); // selected chips, tonal buttons, nav lens
const glowBase = Color(0xFFFFF6EE);

const inkDark = Color(0xFFFFB27A);
const glowBaseDark = Color(0xFF140E0B);
const tintDark = Color(0xFF5A3420);

/// Saffron glass button: warm tinted fill, darker rim, soft top highlight.
ButtonStyle saffronGlassButton({double radius = 16, Size minimumSize = const Size(48, 52), TextStyle? textStyle}) {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled)
        ? saffronFill.withValues(alpha: 0.35)
        : s.contains(WidgetState.pressed)
            ? saffronPressed
            : saffronFill),
    foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? espresso.withValues(alpha: 0.45) : espresso),
    overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.14)),
    side: WidgetStatePropertyAll(BorderSide(color: saffronRim.withValues(alpha: 0.85))),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius))),
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: WidgetStatePropertyAll(minimumSize),
    textStyle: WidgetStatePropertyAll(textStyle ?? const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    foregroundBuilder: (context, states, child) => GlassHighlight(radius: radius, child: child!),
  );
}

ThemeData buildTheme(Brightness b) {
  final light = b == Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
    primary: light ? ink : inkDark,
    onPrimary: light ? Colors.white : espresso,
    secondaryContainer: light ? tint : tintDark,
    onSecondaryContainer: light ? espresso : const Color(0xFFFFE6D3),
    surface: light ? glowBase : glowBaseDark,
    onSurface: light ? espresso : const Color(0xFFF3E9E1),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  final glassFill = light ? Colors.white.withValues(alpha: 0.62) : Colors.white.withValues(alpha: 0.07);
  final glassEdge = Colors.white.withValues(alpha: light ? 0.8 : 0.12);
  return base.copyWith(
    // Every page paints the saffron glow itself (GlassPageTransitionsBuilder).
    scaffoldBackgroundColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: GlassPageTransitionsBuilder(PredictiveBackPageTransitionsBuilder()),
      TargetPlatform.iOS: GlassPageTransitionsBuilder(CupertinoPageTransitionsBuilder()),
    }),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: accent.withValues(alpha: 0.18),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: glassFill,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: glassEdge)),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(style: saffronGlassButton()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        foregroundColor: scheme.onSurface,
        backgroundColor: glassFill,
        side: BorderSide(color: light ? saffronRim.withValues(alpha: 0.35) : glassEdge),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: light ? const Color(0xF7FFF8F2) : const Color(0xF21E1510),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: light ? const Color(0xFAFFF8F2) : const Color(0xFA1E1510),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: light ? Colors.white.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.08),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: glassFill,
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
