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
  int _seenVersion = -1;

  @override
  void initState() {
    super.initState();
    // Saved copies of all four months (shared with the Calendar): shown at once.
    final saved = [for (final m in _months) Api.cached('get_month_summary', body: {'month': m})];
    if (!saved.contains(null)) _items = _holidays(saved.cast<Map<String, dynamic>>());
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

  /// Last month to two months ahead.
  static List<String> get _months {
    final now = istToday();
    return [for (var i = -1; i <= 2; i++) ym(DateTime(now.year, now.month + i))];
  }

  static List<Map<String, dynamic>> _holidays(List<Map<String, dynamic>> res) {
    final all = <Map<String, dynamic>>[];
    for (final r in res) {
      for (final h in (r['summary']['holidays'] as List)) {
        all.add(Map<String, dynamic>.from(h));
      }
    }
    all.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    return all;
  }

  Future<void> _load() async {
    _seenVersion = AppState.i.version;
    try {
      final res = await Future.wait(_months.map((m) => Api.read('get_month_summary', body: {'month': m})));
      if (mounted) setState(() {
        _items = _holidays(res);
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
    // Reloads this list (and the other screens) through the AppState listener.
    if (r != null) AppState.i.changed();
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
                    if (_error != null) StaleNote(error: _error!, onRetry: _load),
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
