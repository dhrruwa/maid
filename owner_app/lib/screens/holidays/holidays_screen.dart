import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Upcoming and recent holidays + "Add holiday".
class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  List<Map<String, dynamic>>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final now = istToday();
      final months = [
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
        DateTime(now.year, now.month + 2),
      ];
      final res = await Future.wait(months.map((m) => Api.call('get_month_summary', {'month': ym(m)})));
      final all = <Map<String, dynamic>>[];
      for (final r in res) {
        for (final h in (r['summary']['holidays'] as List)) {
          all.add(Map<String, dynamic>.from(h));
        }
      }
      all.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
      if (mounted) setState(() {
        _items = all;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _remove(Map h) async {
    final ok = await confirm(context, 'Remove holiday?',
        '${longDate(h['date'])} (${slotLabel(h['slot'])}). The cook will be told to come.', ok: 'Remove', danger: true);
    if (!ok || !mounted) return;
    final r = await busy(context, () => Api.call('delete_item', {'entity_type': 'holidays', 'id': h['id']}),
        success: 'Holiday removed');
    if (r != null) {
      AppState.i.changed();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ymd(istToday());
    return Scaffold(
      appBar: AppBar(title: const Text('Holidays')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (await showAddHoliday(context)) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add holiday'),
      ),
      body: _items == null
          ? (_error != null ? ErrorRetry(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : _items!.isEmpty
              ? const Center(child: Text('No holidays set'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    for (final h in _items!)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.beach_access_rounded, color: StatusColors.holiday),
                          title: Text('${longDate(h['date'])} · ${slotLabel(h['slot'])}'),
                          subtitle: Text([
                            h['paid'] == true ? 'Paid' : 'Unpaid',
                            if ((h['note'] ?? '').toString().isNotEmpty) '${h['note']}',
                          ].join(' · ')),
                          trailing: '${h['date']}'.compareTo(today) >= 0
                              ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _remove(h))
                              : null,
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// Bottom sheet: date / range, Morning/Evening/Full, Paid/Unpaid, note.
/// (Reference: CLEAR date sheet – quick chips above the picker.)
Future<bool> showAddHoliday(BuildContext context, {DateTime? initial}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddHolidaySheet(initial: initial),
  );
  return r ?? false;
}

class _AddHolidaySheet extends StatefulWidget {
  const _AddHolidaySheet({this.initial});
  final DateTime? initial;

  @override
  State<_AddHolidaySheet> createState() => _AddHolidaySheetState();
}

class _AddHolidaySheetState extends State<_AddHolidaySheet> {
  late DateTimeRange _range;
  String _slot = 'full';
  bool _paid = true;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = widget.initial ?? istToday();
    _range = DateTimeRange(start: d, end: d);
  }

  Future<void> _pick() async {
    final t = istToday();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(t.year - 1),
      lastDate: DateTime(t.year + 1, 12, 31),
      initialDateRange: _range,
    );
    if (r != null) setState(() => _range = r);
  }

  Future<void> _save() async {
    final r = await busy(context, () => Api.call('set_holiday', {
          'from': ymd(_range.start),
          'to': ymd(_range.end),
          'slot': _slot,
          'paid': _paid,
          'note': _note.text.trim(),
        }), success: 'Holiday saved – the cook has been notified');
    if (r != null && mounted) {
      AppState.i.changed();
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = istToday();
    final one = _range.start == _range.end;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Add holiday', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [
          ChoiceChip(
            label: const Text('Today'),
            selected: one && _range.start == t,
            onSelected: (_) => setState(() => _range = DateTimeRange(start: t, end: t)),
          ),
          ChoiceChip(
            label: const Text('Tomorrow'),
            selected: one && _range.start == t.add(const Duration(days: 1)),
            onSelected: (_) {
              final d = t.add(const Duration(days: 1));
              setState(() => _range = DateTimeRange(start: d, end: d));
            },
          ),
          ActionChip(avatar: const Icon(Icons.date_range, size: 18), label: const Text('Pick dates'), onPressed: _pick),
        ]),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: Text(one
              ? longDate(ymd(_range.start))
              : '${shortDate(ymd(_range.start))} – ${shortDate(ymd(_range.end))} (${_range.duration.inDays + 1} days)'),
          onTap: _pick,
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'morning', label: Text('Morning'), icon: Icon(Icons.wb_sunny_outlined)),
            ButtonSegment(value: 'evening', label: Text('Evening'), icon: Icon(Icons.nights_stay_outlined)),
            ButtonSegment(value: 'full', label: Text('Full day'), icon: Icon(Icons.today_rounded)),
          ],
          selected: {_slot},
          onSelectionChanged: (s) => setState(() => _slot = s.first),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Paid'), icon: Icon(Icons.currency_rupee_rounded)),
            ButtonSegment(value: false, label: Text('Unpaid'), icon: Icon(Icons.money_off_rounded)),
          ],
          selected: {_paid},
          onSelectionChanged: (s) => setState(() => _paid = s.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. We are travelling'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save holiday')),
      ]),
    );
  }
}
