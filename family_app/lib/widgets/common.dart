import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'glass.dart';

/// Short message at the bottom of the screen.
void showMsg(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: error ? StatusColors.missed : StatusColors.done,
    content: Text(msg, style: const TextStyle(fontSize: 16, color: Colors.white)),
  ));
}

/// Yes/no question. True only when the member taps [yes].
Future<bool> confirm(BuildContext context, {required String title, String? body, required String yes}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body, style: const TextStyle(fontSize: 16)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 46)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// One line of text (e.g. a note for the cook). Null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String save = 'Save',
  int maxLength = 120,
}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: maxLength,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 46)),
          onPressed: () => Navigator.pop(c, ctl.text.trim()),
          child: Text(save),
        ),
      ],
    ),
  );
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
        child: Glass(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 52, color: StatusColors.grey),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Coloured strip, e.g. "Showing saved menu" when a refresh failed.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
