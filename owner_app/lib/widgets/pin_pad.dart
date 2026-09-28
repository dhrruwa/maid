import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Four dots + round number keys (reference: Jomo / Klarna passcode screens).
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.title, this.subtitle, required this.onCompleted});
  final String title;
  final String? subtitle;

  /// Return false to shake and clear (wrong PIN).
  final Future<bool> Function(String pin) onCompleted;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _error = false;
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _tap(String d) async {
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == 4) {
      final ok = await widget.onCompleted(_pin);
      if (!mounted) return;
      if (!ok) {
        HapticFeedback.heavyImpact();
        _shake.forward(from: 0);
        setState(() {
          _error = true;
          _pin = '';
        });
      } else {
        setState(() => _pin = '');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, {IconData? icon, VoidCallback? onTap}) => SizedBox(
          width: 76,
          height: 76,
          child: Material(
            color: icon == null ? scheme.surfaceContainerHighest.withValues(alpha: 0.6) : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap ?? () => _tap(label),
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 28)
                    : Text(label, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        );

    return Column(children: [
      const SizedBox(height: 24),
      Text(widget.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      if (widget.subtitle != null) ...[
        const SizedBox(height: 6),
        Text(widget.subtitle!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ],
      const SizedBox(height: 32),
      AnimatedBuilder(
        animation: _shake,
        builder: (_, child) => Transform.translate(
          offset: Offset(sin(_shake.value * pi * 6) * 12 * (1 - _shake.value), 0),
          child: child,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            final filled = i < _pin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _error ? Colors.red : filled ? scheme.primary : scheme.outlineVariant,
              ),
            );
          }),
        ),
      ),
      SizedBox(
        height: 28,
        child: _error
            ? const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Wrong PIN, try again', style: TextStyle(color: Colors.red)),
              )
            : null,
      ),
      const Spacer(),
      for (final row in [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: row.map((d) => key(d)).toList()),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          const SizedBox(width: 76),
          key('0'),
          key('', icon: Icons.backspace_outlined, onTap: () {
            if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
          }),
        ]),
      ),
      const SizedBox(height: 32),
    ]);
  }
}
