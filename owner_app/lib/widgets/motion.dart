import 'package:flutter/material.dart';

/// Entries fade in and rise a little, one after another (staggered by [index]).
/// Items beyond the first screen appear without a delay, and nothing moves when
/// the phone's "reduce motion" setting is on.
class EntryAnimation extends StatelessWidget {
  const EntryAnimation({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  static const _stepMs = 55;
  static const _durationMs = 420;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final delay = index < 10 ? index * _stepMs : 0;
    final total = delay + _durationMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
        ),
      ),
    );
  }
}
