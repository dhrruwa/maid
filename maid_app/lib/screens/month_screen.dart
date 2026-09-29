import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../core/api.dart';
import '../core/cached_load.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// One month: totals, every day's attendance, and the payment slip.
class MonthScreen extends StatefulWidget {
  const MonthScreen({super.key, required this.month});
  final String month;

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> with CachedLoad {
  bool _slipBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => load('get_month_summary', {'month': widget.month});

  Future<Uint8List> _pdf() async {
    final r = await Api.call('generate_slip', {'month': widget.month});
    final res = await http.get(Uri.parse('${r['url']}'));
    if (res.statusCode != 200) throw ApiError('GENERIC', '');
    return res.bodyBytes;
  }

  Future<void> _slip({required bool share}) async {
    setState(() => _slipBusy = true);
    try {
      final bytes = await _pdf();
      final name = 'payslip-${widget.month}.pdf';
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: name);
      } else {
        // Opens the system viewer with Print and "Save as PDF" (download).
        await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
      }
    } on ApiError catch (e) {
      if (mounted) showMsg(context, e.friendly, error: true);
    } catch (_) {
      if (mounted) showMsg(context, L.t('err_GENERIC'), error: true);
    } finally {
      if (mounted) setState(() => _slipBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.monthYear(widget.month))),
      body: data == null
          ? (error != null ? ErrorBox(text: error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final s = Map<String, dynamic>.from(data!['summary']);
    final t = s['totals'] as Map;
    final c = s['counts'] as Map;
    final p = s['payment'] as Map?;
    final days = (s['days'] as List)
        .map((d) => Map<String, dynamic>.from(d))
        .where((d) =>
            d['slots']['morning']['state'] != 'none' &&
            d['date'].toString().compareTo(istDate()) <= 0)
        .toList()
        .reversed
        .toList();

    Widget slotIcon(Map slot) {
      final look = SlotLook.short('${slot['state']}');
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(look.icon, color: look.color, size: 22),
        const SizedBox(width: 3),
        Flexible(child: Text(look.text, style: TextStyle(fontSize: 13, color: look.color, fontWeight: FontWeight.w700))),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (stale) const SavedNote(),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rupees(p != null ? p['total_amount'] : t['earned']),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
            Text(
              p != null ? L.t('paid_on', {'date': L.shortDate('${p['paid_on']}')}) : L.t('not_paid'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: p != null ? StatusColors.done : StatusColors.wait,
              ),
            ),
            const SizedBox(height: 10),
            Text(L.t('visits', {'count': c['visits_done']}), style: const TextStyle(fontSize: 17)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (_slipBusy)
        const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
      else ...[
        BigButton(icon: Icons.receipt_long_rounded, label: L.t('view_slip'), onPressed: () => _slip(share: false)),
        const SizedBox(height: 10),
        BigButton(icon: Icons.share_rounded, label: L.t('share_slip'), filled: false, onPressed: () => _slip(share: true)),
      ],
      const SizedBox(height: 20),
      Text(L.t('day_by_day'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      for (final d in days)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(L.longDate('${d['date']}'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                Text(rupees(d['amount']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Row(children: [
                  Text('${L.t('morning')}: ', style: const TextStyle(fontSize: 13)),
                  Flexible(child: slotIcon(d['slots']['morning'])),
                ])),
                Expanded(child: Row(children: [
                  Text('${L.t('evening')}: ', style: const TextStyle(fontSize: 13)),
                  Flexible(child: slotIcon(d['slots']['evening'])),
                ])),
              ]),
              if (d['has_menu'] == true) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    ...(d['menu']['morning'] as List).map((e) => e['name']),
                    ...(d['menu']['evening'] as List).map((e) => e['name']),
                  ].join(', '),
                  style: const TextStyle(fontSize: 13, color: StatusColors.grey),
                ),
              ],
            ]),
          ),
        ),
    ]);
  }
}
