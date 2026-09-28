import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/slip.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Monthly payment slip (reference: Fresha invoice / Shop receipt).
class SlipScreen extends StatefulWidget {
  const SlipScreen({super.key, required this.month});
  final String month;

  @override
  State<SlipScreen> createState() => _SlipScreenState();
}

class _SlipScreenState extends State<SlipScreen> {
  Map<String, dynamic>? _s;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.call('get_month_summary', {'month': widget.month});
      if (mounted) setState(() {
        _s = Map<String, dynamic>.from(r['summary']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _markPaid() async {
    final total = _s!['totals']['earned'];
    final ok = await confirm(context, 'Mark ${monthName(widget.month)} as paid?',
        '${rupees(total)} will be recorded as paid today and the slip will be frozen.',
        ok: 'Mark as paid');
    if (!ok || !mounted) return;
    final r = await busy(context, () => Api.call('mark_paid', {'month': widget.month}), success: 'Marked as paid');
    if (r != null) {
      AppState.i.changed();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(monthLabel(widget.month))),
      body: _s == null
          ? (_error != null ? ErrorRetry(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : _body(),
    );
  }

  Widget _body() {
    final s = _s!;
    final p = s['payment'] as Map?;
    final c = s['counts'] as Map;
    final t = s['totals'] as Map;
    final r = s['rates'] as Map;
    final monthOver = widget.month.compareTo(ym(istToday())) < 0;
    final days = (s['days'] as List)
        .where((d) => d['slots']['morning']['state'] != 'none' || d['slots']['evening']['state'] != 'none')
        .toList();
    final tt = Theme.of(context).textTheme;

    String cell(Map slot) {
      final st = '${slot['state']}';
      return switch (st) {
        'done' => '✓',
        'missed' => '✗',
        'holiday_paid' || 'holiday_unpaid' => 'H',
        'leave_paid' || 'leave_unpaid' => 'L',
        'not_needed' => '–',
        _ => '·',
      };
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Payment slip', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (p != null ? StatusColors.done : StatusColors.partial).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(p != null ? Icons.check_circle_rounded : Icons.pending_rounded,
                    size: 16, color: p != null ? StatusColors.done : StatusColors.partial),
                const SizedBox(width: 4),
                Text(p != null ? 'Paid ${shortDate(p['paid_on'])}' : 'Not paid',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: p != null ? StatusColors.done : StatusColors.partial)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Text('${s['house_name']} · ${s['maid_name'] ?? 'Cook'}'),
          Text(monthLabel(widget.month), style: tt.bodySmall),
          const Divider(height: 24),
          Text(rupees(p != null ? p['total_amount'] : t['earned']),
              style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _kv('Weekday visits', '${c['weekday_visits']} × ${rupees(r['weekday_rate'])} = ${rupees(t['weekday_amount'])}'),
          _kv('Weekend visits', '${c['weekend_visits']} × ${rupees(r['weekend_rate'])} = ${rupees(t['weekend_amount'])}'),
          _kv('Paid holidays / leave', rupees(t['paid_off_amount'])),
          _kv('Visits done / missed', '${c['visits_done']} / ${c['missed']}'),
          _kv('Full days / half days', '${c['full_days']} / ${c['half_days']}'),
          _kv('Holidays / leaves', '${c['holidays']} / ${c['leaves']}'),
        ]),
      ),
      const SizedBox(height: 12),
      if (p == null && monthOver) ...[
        FilledButton.icon(onPressed: _markPaid, icon: const Icon(Icons.payments_rounded), label: const Text('Mark as paid')),
        const SizedBox(height: 8),
      ],
      Row(children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => busy(context, () => Slips.sharePdf(widget.month)),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share on WhatsApp'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => busy(context, () => Slips.shareImage(widget.month)),
            icon: const Icon(Icons.image_outlined),
            label: const Text('As image'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => busy(context, () => Slips.printOrSave(widget.month)),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Save / Print'),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Day by day',
        child: Column(children: [
          const Row(children: [
            Expanded(flex: 3, child: Text('Date', style: TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 2, child: Text('Morning', style: TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 2, child: Text('Evening', style: TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const Divider(),
          for (final d in days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(flex: 3, child: Text(shortDate(d['date']))),
                Expanded(flex: 2, child: Text(cell(d['slots']['morning']))),
                Expanded(flex: 2, child: Text(cell(d['slots']['evening']))),
                Expanded(flex: 2, child: Text(rupees(d['amount']), textAlign: TextAlign.right)),
              ]),
            ),
          const Divider(),
          const Text('✓ done  ✗ missed  H holiday  L leave  – not needed', style: TextStyle(fontSize: 12)),
        ]),
      ),
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(k)), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}
