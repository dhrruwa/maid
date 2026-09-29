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

/// Floating tab bar (Blinkit / iOS Liquid Glass style): a compact dark frosted
/// glass capsule, centred near the bottom, with a lighter glass "lens" behind
/// the selected tab. The lens follows [position] continuously (it tracks a
/// page swipe and stretches a little mid-slide) and can itself be dragged
/// along the bar. Selected tab: two-tone icon (light saffron fill, saffron
/// outline) and a bold label. The capsule stays dark in light and dark mode.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.position,
    required this.onTap,
    required this.items,
    this.onDrag,
    this.onDragEnd,
  });

  /// Fractional selected index, e.g. 1.4 while swiping from tab 1 to tab 2.
  final double position;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;
  final ValueChanged<double>? onDrag;
  final VoidCallback? onDragEnd;

  static const _capsule = Color(0xDB1C1613); // warm near-black glass
  static const _label = Color(0xFFF6EFE9);
  static const _itemWidth = 72.0;
  static const _pad = 4.0;

  @override
  Widget build(BuildContext context) {
    const radius = 30.0;
    final selected = position.round().clamp(0, items.length - 1);
    // Sits just above the iPhone home indicator (lower than a full safe area).
    final bottom = (MediaQuery.paddingOf(context).bottom - 4).clamp(6.0, 60.0);
    final width = items.length * _itemWidth + _pad * 2;
    // Liquid stretch: the lens widens a little half-way between two tabs.
    final frac = position - position.floorToDouble();
    final stretch = 1 + 0.18 * (frac < 0.5 ? frac : 1 - frac) * 2;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        heightFactor: 1,
        child: SizedBox(
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 9))],
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
                    padding: const EdgeInsets.all(_pad),
                    child: SizedBox(
                      height: 52,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: onDrag == null
                            ? null
                            : (d) => onDrag!((d.localPosition.dx - _itemWidth / 2) / _itemWidth),
                        onHorizontalDragEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
                        child: Stack(children: [
                          // The lens: a lighter glass pill behind the selected tab.
                          Positioned(
                            left: position * _itemWidth - (_itemWidth * (stretch - 1)) / 2,
                            width: _itemWidth * stretch,
                            top: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(radius - _pad),
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
                              SizedBox(
                                width: _itemWidth,
                                child: Semantics(
                                  button: true,
                                  selected: i == selected,
                                  label: items[i].label,
                                  excludeSemantics: true,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => onTap(i),
                                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      AnimatedScale(
                                        scale: i == selected ? 1.08 : 1,
                                        duration: const Duration(milliseconds: 200),
                                        curve: Curves.easeOutBack,
                                        child: i == selected
                                            ? _TwoToneIcon(fill: items[i].selectedIcon, outline: items[i].icon)
                                            : Icon(items[i].icon, color: _label, size: 24),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        items[i].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.fade,
                                        softWrap: false,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: i == selected ? FontWeight.w800 : FontWeight.w500,
                                          color: _label,
                                        ),
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                          ]),
                        ]),
                      ),
                    ),
                  ),
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
      Icon(fill, color: const Color(0xFFFFC08A), size: 24),
      Icon(outline, color: accent, size: 24),
    ]);
  }
}
