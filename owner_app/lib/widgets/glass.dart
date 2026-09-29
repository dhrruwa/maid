import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Warm saffron glow behind every page. Static, so it is painted once.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(child: CustomPaint(painter: _GlowPainter(dark))),
      child,
    ]);
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size s) {
    final all = Offset.zero & s;
    canvas.drawRect(all, Paint()..color = dark ? glowBaseDark : glowBase);
    void blob(double cx, double cy, double r, Color c) {
      final rect = Rect.fromCircle(center: Offset(s.width * cx, s.height * cy), radius: s.width * r);
      canvas.drawRect(all, Paint()..shader = RadialGradient(colors: [c, c.withValues(alpha: 0)]).createShader(rect));
    }

    if (dark) {
      blob(0.95, 0.04, 0.95, const Color(0x55E8731F));
      blob(0.0, 0.55, 0.85, const Color(0x668A3A12));
      blob(0.75, 1.0, 0.9, const Color(0x443A1E14));
    } else {
      blob(0.95, 0.02, 0.95, const Color(0x99F7A25B));
      blob(-0.1, 0.45, 0.85, const Color(0x99FFC9A3));
      blob(0.85, 0.75, 0.8, const Color(0x66FFD27A));
      blob(0.2, 1.05, 0.9, const Color(0x77F9B8A0));
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.dark != dark;
}

/// Wraps every page route in the glow so pages stay opaque during transitions.
class GlassPageTransitionsBuilder extends PageTransitionsBuilder {
  const GlassPageTransitionsBuilder(this.inner);
  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return inner.buildTransitions(route, context, animation, secondaryAnimation, GlassBackground(child: child));
  }
}

List<double> _saturation(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final r = (1 - s) * lr, g = (1 - s) * lg, b = (1 - s) * lb;
  return [r + s, g, b, 0, 0, r, g + s, b, 0, 0, r, g, b + s, 0, 0, 0, 0, 0, 1, 0];
}

/// Frosted glass: blurred + saturated backdrop, translucent fill, a rim that
/// catches light at the top-left, and a soft warm shadow.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(18),
    this.blur = 16,
    this.onTap,
    this.tintColor,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final VoidCallback? onTap;
  final Color? tintColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    final fill = dark
        ? [Colors.white.withValues(alpha: 0.11), Colors.white.withValues(alpha: 0.05)]
        : [Colors.white.withValues(alpha: 0.72), Colors.white.withValues(alpha: 0.46)];

    Widget body = CustomPaint(
      foregroundPainter: _RimPainter(radius: radius, dark: dark),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: fill),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (tintColor != null) {
      body = DecoratedBox(decoration: BoxDecoration(borderRadius: r, color: tintColor), child: body);
    }
    if (onTap != null) {
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: r, child: body),
      );
    }
    if (blur > 0) {
      final filter = ui.ImageFilter.compose(
        outer: ColorFilter.matrix(_saturation(1.6)),
        inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      );
      body = BackdropGroup.of(context) != null
          ? BackdropFilter.grouped(filter: filter, child: body)
          : BackdropFilter(filter: filter, child: body);
    }
    body = ClipRRect(borderRadius: r, child: body);
    if (!shadow) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: dark ? Colors.black.withValues(alpha: 0.35) : const Color(0xFF7A3E12).withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: body,
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({required this.radius, required this.dark});
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.6);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final colors = dark
        ? [0.38, 0.10, 0.03, 0.18].map((a) => Colors.white.withValues(alpha: a)).toList()
        : [0.95, 0.35, 0.10, 0.55].map((a) => Colors.white.withValues(alpha: a)).toList();
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.dark != dark || old.radius != radius;
}

/// Soft specular highlight across the top of a glass button.
class GlassHighlight extends StatelessWidget {
  const GlassHighlight({super.key, required this.radius, required this.child});
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0)],
                stops: const [0, 0.55],
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class GlassNavItem {
  const GlassNavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating tab bar (Blinkit / iOS Liquid Glass style): a dark frosted glass
/// capsule, a lighter glass "lens" that slides behind the selected tab, a
/// two-tone selected icon (light saffron fill, saffron outline) and a bold
/// label. The capsule stays dark in light and dark mode.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.index, required this.onTap, required this.items});
  final int index;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  static const _capsule = Color(0xDB1C1613); // warm near-black glass
  static const _label = Color(0xFFF6EFE9);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    const radius = 38.0;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 26, offset: const Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.compose(
              outer: ColorFilter.matrix(_saturation(1.5)),
              inner: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _capsule,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: SizedBox(
                  height: 64,
                  child: LayoutBuilder(builder: (context, c) {
                    final w = c.maxWidth / items.length;
                    return Stack(children: [
                      // The lens: a lighter glass pill behind the selected tab.
                      AnimatedPositioned(
                        duration: reduce ? Duration.zero : const Duration(milliseconds: 380),
                        curve: Curves.easeOutBack,
                        left: index * w,
                        width: w,
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(radius - 7),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.13)],
                            ),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                        ),
                      ),
                      Row(children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: i == index,
                              label: items[i].label,
                              excludeSemantics: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onTap(i),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  AnimatedScale(
                                    scale: i == index ? 1.08 : 1,
                                    duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
                                    curve: Curves.easeOutBack,
                                    child: i == index
                                        ? _TwoToneIcon(fill: items[i].selectedIcon, outline: items[i].icon)
                                        : Icon(items[i].icon, color: _label, size: 28),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    items[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                                      color: _label,
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                      ]),
                    ]);
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filled icon in light saffron with the outlined version drawn over it in
/// saffron – the two-tone "selected" look.
class _TwoToneIcon extends StatelessWidget {
  const _TwoToneIcon({required this.fill, required this.outline});
  final IconData fill;
  final IconData outline;

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      Icon(fill, color: const Color(0xFFFFC08A), size: 28),
      Icon(outline, color: accent, size: 28),
    ]);
  }
}
