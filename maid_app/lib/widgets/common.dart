import 'package:flutter/material.dart';

import '../core/device.dart';
import '../core/i18n.dart';
import '../core/push.dart';
import '../core/theme.dart';

/// Language toggle – always visible in the top bar.
class LangButton extends StatelessWidget {
  const LangButton({super.key, this.onChanged});
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: const BorderSide(color: accent, width: 1.5),
          foregroundColor: espresso,
          backgroundColor: Colors.white.withValues(alpha: 0.6),
          iconColor: accent,
        ),
        onPressed: () async {
          await L.setLang(L.isKannada ? 'en' : 'kn');
          onChanged?.call();
          if (Device.paired) Push.syncDevice();
        },
        icon: const Icon(Icons.translate_rounded, size: 20),
        label: Text(L.t('lang_switch'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Full-width big button with an icon (min 56 px tall).
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.height = 64,
    this.filled = true,
    this.color,
    this.iconColor,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double height;
  final bool filled;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: height > 70 ? 34 : 26, color: iconColor),
      const SizedBox(width: 12),
      Flexible(child: Text(label, textAlign: TextAlign.center)),
    ]);
    final size = Size(double.infinity, height);
    return filled
        ? FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: size,
              backgroundColor: color,
              textStyle: TextStyle(fontSize: height > 70 ? 24 : 19, fontWeight: FontWeight.w800),
            ),
            onPressed: onPressed,
            child: child,
          )
        : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: size), onPressed: onPressed, child: child);
  }
}

/// Colour + icon + text for a visit state.
class SlotLook {
  const SlotLook(this.text, this.icon, this.color);
  final String text;
  final IconData icon;
  final Color color;

  static SlotLook of(String state) => switch (state) {
        'done' => SlotLook(L.t('st_done'), Icons.check_circle_rounded, StatusColors.done),
        'missed' => SlotLook(L.t('st_missed'), Icons.cancel_rounded, StatusColors.missed),
        'pending' => SlotLook(L.t('st_pending'), Icons.hourglass_top_rounded, StatusColors.wait),
        'upcoming' => SlotLook(L.t('st_upcoming'), Icons.schedule_rounded, StatusColors.grey),
        'holiday_paid' || 'holiday_unpaid' => SlotLook(L.t('st_holiday'), Icons.beach_access_rounded, StatusColors.holiday),
        'leave_paid' || 'leave_unpaid' => SlotLook(L.t('st_leave'), Icons.event_busy_rounded, StatusColors.leave),
        'not_needed' => SlotLook(L.t('st_not_needed'), Icons.remove_circle_outline_rounded, StatusColors.grey),
        _ => const SlotLook('—', Icons.remove_rounded, StatusColors.grey),
      };

  /// Short label for tight rows (history).
  static SlotLook short(String state) => switch (state) {
        'holiday_paid' || 'holiday_unpaid' => SlotLook(L.t('st_holiday_short'), Icons.beach_access_rounded, StatusColors.holiday),
        'leave_paid' || 'leave_unpaid' => SlotLook(L.t('st_leave_short'), Icons.event_busy_rounded, StatusColors.leave),
        'not_needed' => const SlotLook('—', Icons.remove_rounded, StatusColors.grey),
        _ => of(state),
      };
}

class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded, size: 56, color: StatusColors.grey),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          BigButton(icon: Icons.refresh_rounded, label: L.t('retry'), onPressed: onRetry, filled: false),
        ]),
      ),
    );
  }
}

void showMsg(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: error ? StatusColors.missed : StatusColors.done,
    content: Text(msg, style: const TextStyle(fontSize: 17)),
  ));
}
