import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/leave_screen.dart';
import '../screens/scan_flow.dart';

/// Links a server block may open. Anything else (intent:, file:, javascript:…)
/// is ignored.
const _schemes = {'https', 'tel', 'mailto', 'sms'};

/// What tapping a server block does. `action` is one of the app's own
/// screens ("scan", "leave", "history"), "refresh", or a link: https://…,
/// tel:+91…, https://wa.me/91… (WhatsApp).
Future<void> runUiAction(BuildContext context, String action) async {
  switch (action) {
    case 'scan':
      return startScan(context);
    case 'leave':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaveScreen()));
      return;
    case 'history':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
      return;
    case 'refresh':
      HomeScreen.refreshAll();
      return;
  }
  final uri = Uri.tryParse(action);
  if (uri == null || !_schemes.contains(uri.scheme)) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No app for it on this phone: nothing to do.
  }
}

/// Whether [action] is something [runUiAction] can do (checked before showing
/// a tappable block, so a typo doesn't give her a button that does nothing).
bool isUiAction(String? action) {
  if (action == null) return false;
  if (const {'scan', 'leave', 'history', 'refresh'}.contains(action)) return true;
  final uri = Uri.tryParse(action);
  return uri != null && _schemes.contains(uri.scheme) && action.length > uri.scheme.length + 1;
}
