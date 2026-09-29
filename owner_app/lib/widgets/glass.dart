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

/// Bottom tab bar in the style of Blinkit: pinned full width, a short bar on
/// the top edge above the selected tab (it slides between tabs), a two-tone
/// selected icon (saffron fill, espresso outline) and a bold label. Frosted
/// glass, so content scrolling underneath shows through blurred.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.index, required this.onTap, required this.items});
  final int index;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = Theme.of(context).colorScheme.onSurface;
    final muted = on.withValues(alpha: 0.55);
    final reduce = MediaQuery.of(context).disableAnimations;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ColorFilter.matrix(_saturation(1.6)),
          inner: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dark ? const Color(0xB8140E0B) : Colors.white.withValues(alpha: 0.74),
            border: Border(top: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.10) : const Color(0x1F2A1B12))),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: SizedBox(
              height: 64,
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth / items.length;
                return Stack(children: [
                  AnimatedPositioned(
                    duration: reduce ? Duration.zero : const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    left: index * w + w * 0.28,
                    width: w * 0.44,
                    top: 0,
                    height: 3.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: dark ? inkDark : espresso,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
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
                                scale: i == index ? 1.1 : 1,
                                duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
                                curve: Curves.easeOutBack,
                                child: i == index
                                    ? _TwoToneIcon(
                                        fill: items[i].selectedIcon,
                                        outline: items[i].icon,
                                        outlineColor: dark ? const Color(0xFFF3E9E1) : espresso,
                                      )
                                    : Icon(items[i].icon, color: muted, size: 25),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                items[i].label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                                  color: i == index ? on : muted,
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
    );
  }
}

/// Filled icon in saffron with the outlined version drawn on top in espresso.
class _TwoToneIcon extends StatelessWidget {
  const _TwoToneIcon({required this.fill, required this.outline, required this.outlineColor});
  final IconData fill;
  final IconData outline;
  final Color outlineColor;

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      Icon(fill, color: accent, size: 25),
      Icon(outline, color: outlineColor, size: 25),
    ]);
  }
}
