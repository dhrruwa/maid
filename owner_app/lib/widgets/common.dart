import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import 'glass.dart';

/// Colour + icon + label for a visit slot state (never colour alone).
class SlotStyle {
  const SlotStyle(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  static SlotStyle of(String state) {
    switch (state) {
      case 'done':
        return const SlotStyle('Done', Icons.check_circle_rounded, StatusColors.done);
      case 'missed':
        return const SlotStyle('Missed', Icons.cancel_rounded, StatusColors.missed);
      case 'pending':
        return const SlotStyle('Waiting', Icons.hourglass_top_rounded, StatusColors.partial);
      case 'upcoming':
        return const SlotStyle('Upcoming', Icons.schedule_rounded, StatusColors.future);
      case 'holiday_paid':
        return const SlotStyle('Holiday (paid)', Icons.beach_access_rounded, StatusColors.holiday);
      case 'holiday_unpaid':
        return const SlotStyle('Holiday (unpaid)', Icons.beach_access_rounded, StatusColors.holiday);
      case 'leave_paid':
        return const SlotStyle('Leave (paid)', Icons.event_busy_rounded, StatusColors.leave);
      case 'leave_unpaid':
        return const SlotStyle('Leave (unpaid)', Icons.event_busy_rounded, StatusColors.leave);
      case 'not_needed':
        return const SlotStyle('Not needed', Icons.remove_circle_outline_rounded, StatusColors.future);
      default:
        return const SlotStyle('—', Icons.remove_rounded, StatusColors.future);
    }
  }
}

class DayStyle {
  static Color color(String status) => switch (status) {
        'green' => StatusColors.done,
        'yellow' => StatusColors.partial,
        'red' => StatusColors.missed,
        'blue' => StatusColors.holiday,
        'purple' => StatusColors.leave,
        _ => Colors.transparent,
      };
  static String label(String status) => switch (status) {
        'green' => 'All visits done',
        'yellow' => 'Partial',
        'red' => 'Missed',
        'blue' => 'Holiday',
        'purple' => 'Leave',
        'grey' => 'Upcoming',
        _ => '',
      };
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.state, {super.key, this.dense = false});
  final String state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = SlotStyle.of(state);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(s.icon, size: dense ? 14 : 16, color: s.color),
        const SizedBox(width: 4),
        Text(s.label,
            style: TextStyle(color: s.color, fontWeight: FontWeight.w600, fontSize: dense ? 12 : 13)),
      ]),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.child, this.padding, this.onTap});
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Glass(
      onTap: onTap,
      padding: padding ?? const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Expanded(
                child: Text(title!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        child,
      ]),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final net = error is ApiError && (error as ApiError).isNetwork;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(net ? Icons.wifi_off_rounded : Icons.error_outline_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ]),
      ),
    );
  }
}

/// Small line above data kept from last time when refreshing it failed.
/// Tap to try again.
class StaleNote extends StatelessWidget {
  const StaleNote({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final net = e is ApiError && e.isNetwork;
    // Not a passing failure: say why (e.g. "This phone is not the owner phone").
    final notOwner = e is ApiError && e.code == 'NOT_OWNER';
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: notOwner ? Colors.red : Colors.grey);
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(net ? Icons.wifi_off_rounded : Icons.sync_problem_rounded, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                  notOwner
                      ? '$e'
                      : net
                          ? 'Offline · showing saved data'
                          : "Couldn't refresh · showing saved data",
                  style: style),
            ),
          ]),
        ),
      ),
    );
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    backgroundColor: error ? StatusColors.missed : null,
  ));
}

/// Runs an API action with a spinner dialog; shows errors as a snackbar.
Future<T?> busy<T>(BuildContext context, Future<T> Function() fn, {String? success}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final r = await fn();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      if (success != null) toast(context, success);
    }
    return r;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      toast(context, '$e', error: true);
    }
    return null;
  }
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'OK', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: StatusColors.missed) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(BuildContext context, String title, {String hint = '', String ok = 'Save', String initial = ''}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        maxLength: 300,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

class Stat extends StatelessWidget {
  const Stat({super.key, required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}
