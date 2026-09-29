import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Warm saffron glow behind every page. Static, so it is painted once.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const RepaintBoundary(child: CustomPaint(painter: _GlowPainter())),
      child,
    ]);
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final all = Offset.zero & s;
    canvas.drawRect(all, Paint()..color = appBackground);
    void blob(double cx, double cy, double r, Color c) {
      final rect = Rect.fromCircle(center: Offset(s.width * cx, s.height * cy), radius: s.width * r);
      canvas.drawRect(all, Paint()..shader = RadialGradient(colors: [c, c.withValues(alpha: 0)]).createShader(rect));
    }

    blob(0.95, 0.02, 0.95, const Color(0x99F7A25B));
    blob(-0.1, 0.45, 0.85, const Color(0x99FFC9A3));
    blob(0.85, 0.75, 0.8, const Color(0x66FFD27A));
    blob(0.2, 1.05, 0.9, const Color(0x77F9B8A0));
  }

  @override
  bool shouldRepaint(_GlowPainter old) => false;
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

/// Light glass: translucent fill, a rim that catches light at the top-left and
/// a soft warm shadow. No live blur, so it stays smooth on low-end phones
/// (over the smooth glow a blur would look the same anyway).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.opacity = 0.72,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    Widget body = CustomPaint(
      foregroundPainter: _RimPainter(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: opacity), Colors.white.withValues(alpha: opacity - 0.22)],
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap != null) {
      body = Material(type: MaterialType.transparency, child: InkWell(onTap: onTap, borderRadius: r, child: body));
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [BoxShadow(color: const Color(0xFF7A3E12).withValues(alpha: 0.10), blurRadius: 22, offset: const Offset(0, 9))],
      ),
      child: ClipRRect(borderRadius: r, child: body),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [0.95, 0.35, 0.10, 0.55].map((a) => Colors.white.withValues(alpha: a)).toList(),
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.radius != radius;
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
