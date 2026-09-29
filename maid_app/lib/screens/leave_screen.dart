import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Pick date → Morning / Evening / Full day → optional reason → Send.
/// Below: her requests with status. (Reference: Bumble date details form.)
class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  DateTime _date = DateTime.parse(istDate(1));
  String _slot = 'full';
  final _reason = TextEditingController();
  bool _sending = false;
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    try {
      final r = await Api.call('list_leave');
      if (mounted) setState(() => _list = (r['leaves'] as List).map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {
      if (mounted) setState(() => _list ??= []);
    }
  }

  Future<void> _pickDate() async {
    final today = DateTime.parse(istDate());
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      locale: Locale(L.code),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await Api.call('request_leave', {'date': ymd(_date), 'slot': _slot, 'reason': _reason.text.trim()});
      if (!mounted) return;
      showMsg(context, L.t('leave_sent'));
      _reason.clear();
      _loadList();
    } on ApiError catch (e) {
      if (mounted) showMsg(context, e.friendly, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget slotButton(String slot, IconData icon) {
      final sel = _slot == slot;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: sel ? saffronFill : Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _slot = slot),
              child: Container(
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: sel ? saffronRim : Colors.white, width: 2),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 30, color: espresso),
                  const SizedBox(height: 4),
                  Text(L.slot(slot),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: espresso)),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(L.t('leave_title'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(L.t('leave_date'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Material(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _pickDate,
            child: Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_month_rounded, size: 30, color: accent),
                const SizedBox(width: 12),
                Expanded(child: Text(L.longDate(ymd(_date)), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                const Icon(Icons.edit_calendar_rounded),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(L.t('leave_which'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(children: [
          slotButton('morning', Icons.wb_sunny_rounded),
          slotButton('evening', Icons.nights_stay_rounded),
          slotButton('full', Icons.today_rounded),
        ]),
        const SizedBox(height: 20),
        TextField(
          controller: _reason,
          maxLength: 200,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(labelText: L.t('leave_reason'), prefixIcon: const Icon(Icons.edit_note_rounded)),
        ),
        const SizedBox(height: 8),
        _sending
            ? const Center(child: CircularProgressIndicator())
            : BigButton(icon: Icons.send_rounded, label: L.t('send'), onPressed: _send),
        const SizedBox(height: 28),
        Text(L.t('my_requests'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_list == null)
          const Center(child: CircularProgressIndicator())
        else if (_list!.isEmpty)
          Text(L.t('no_requests'), style: const TextStyle(fontSize: 17))
        else
          for (final l in _list!) LeaveTile(leave: l),
      ]),
    );
  }
}

class LeaveTile extends StatelessWidget {
  const LeaveTile({super.key, required this.leave});
  final Map<String, dynamic> leave;

  @override
  Widget build(BuildContext context) {
    final status = '${leave['status']}';
    final (icon, color) = switch (status) {
      'approved_paid' || 'approved_unpaid' => (Icons.check_circle_rounded, StatusColors.done),
      'rejected' => (Icons.cancel_rounded, StatusColors.missed),
      _ => (Icons.hourglass_top_rounded, StatusColors.wait),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${L.longDate('${leave['date']}')} · ${L.slot('${leave['slot']}')}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(L.t('ls_$status'), style: TextStyle(fontSize: 17, color: color, fontWeight: FontWeight.w700)),
              if ((leave['reason'] ?? '').toString().isNotEmpty)
                Text('${leave['reason']}', style: const TextStyle(fontSize: 15)),
            ]),
          ),
        ]),
      ),
    );
  }
}
