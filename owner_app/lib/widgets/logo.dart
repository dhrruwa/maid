import 'package:flutter/material.dart';

/// The app's logo (rounded app icon), e.g. on the first screen.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 120});
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.2237),
        boxShadow: [BoxShadow(color: const Color(0xFF7A3E12).withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      child: Image.asset('assets/icon/logo.png', width: size, height: size, filterQuality: FilterQuality.medium),
    );
  }
}
