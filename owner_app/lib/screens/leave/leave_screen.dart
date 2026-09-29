import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Pending requests with Paid / Unpaid / Reject (reference: Stardust follow requests).
class LeaveRequestTile extends StatelessWidget {
  const LeaveRequestTile({super.key, required this.leave, required this.onDecide});
  final Map<String, dynamic> leave;
  final Future<void> Function(Map l, String decision) onDecide;

  @override
  Widget build(BuildContext context) {
    final l = leave;
    final pending = l['status'] == 'pending';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.event_busy_rounded, color: StatusColors.leave),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${longDate(l['date'])} · ${slotLabel(l['slot'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if ((l['reason'] ?? '').toString().isNotEmpty) Text('"${l['reason']}"'),
              Text('Asked ${istDateTime(l['created_at'])}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (!pending) LeaveStatusChip(status: '${l['status']}'),
        ]),
        if (pending) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () => onDecide(l, 'approved_paid'),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Approve · Paid'),
            ),
            OutlinedButton.icon(
              onPressed: () => onDecide(l, 'approved_unpaid'),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Approve · Unpaid'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: StatusColors.missed),
              onPressed: () => onDecide(l, 'rejected'),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Reject'),
            ),
          ]),
        ],
      ]),
    );
  }
}

class LeaveStatusChip extends StatelessWidget {
  const LeaveStatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      'approved_paid' => ('Approved · paid', Icons.check_circle_rounded, StatusColors.done),
      'approved_unpaid' => ('Approved · unpaid', Icons.check_circle_outline_rounded, StatusColors.done),
      'rejected' => ('Rejected', Icons.cancel_rounded, StatusColors.missed),
      _ => ('Waiting', Icons.hourglass_top_rounded, StatusColors.partial),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// All leave requests: pending first, then history with decision dates.
class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  List<Map<String, dynamic>>? _leaves = _parse(Api.cached('list_leave'));
  Object? _error;
  int _seenVersion = -1;

  static List<Map<String, dynamic>>? _parse(Map<String, dynamic>? r) =>
      r == null ? null : (r['leaves'] as List).map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  void initState() {
    super.initState();
    AppState.i.addListener(_onState);
    _load();
  }

  @override
  void dispose() {
    AppState.i.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (AppState.i.version != _seenVersion) _load();
  }

  Future<void> _load() async {
    _seenVersion = AppState.i.version;
    try {
      final r = await Api.read('list_leave');
      if (mounted) {
        setState(() {
          _leaves = _parse(r);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _decide(Map l, String decision) async {
    final r = await busy(context, () => Api.call('decide_leave', {'id': l['id'], 'decision': decision}),
        success: 'Saved – the cook has been notified');
    // Reloads this list (and the other screens) through the AppState listener.
    if (r != null) AppState.i.changed();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_leaves == null) {
      body = _error != null ? ErrorRetry(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    } else if (_leaves!.isEmpty) {
      body = const Center(child: Text('No leave requests yet'));
    } else {
      final pending = _leaves!.where((l) => l['status'] == 'pending').toList();
      final done = _leaves!.where((l) => l['status'] != 'pending').toList();
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom), children: [
          if (_error != null) StaleNote(error: _error!, onRetry: _load),
          if (pending.isNotEmpty)
            SectionCard(
              title: 'Waiting for you',
              child: Column(children: [for (final l in pending) LeaveRequestTile(leave: l, onDecide: _decide)]),
            ),
          if (pending.isNotEmpty) const SizedBox(height: 12),
          if (done.isNotEmpty)
            SectionCard(
              title: 'History',
              child: Column(children: [
                for (final l in done)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${longDate(l['date'])} · ${slotLabel(l['slot'])}'),
                    subtitle: Text([
                      if ((l['reason'] ?? '').toString().isNotEmpty) '"${l['reason']}"',
                      if (l['decided_at'] != null) 'Decided ${istDateTime(l['decided_at'])}',
                    ].join('\n')),
                    trailing: LeaveStatusChip(status: '${l['status']}'),
                  ),
              ]),
            ),
        ]),
      );
    }
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Leave requests')), body: body);
  }
}
