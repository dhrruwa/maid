import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../holidays/holidays_screen.dart';
import 'day_sheet.dart';

/// Month calendar with coloured days (reference: Noom streak / MacroFactor weigh-in).
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = istToday();
  final Map<String, Map<String, dynamic>> _months = {};
  Object? _error;
  bool _loading = false;
  int _seenVersion = -1;

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
    if (AppState.i.version != _seenVersion) {
      _months.clear();
      _load();
    }
  }

  String get _month => ym(_focused);

  Future<void> _load() async {
    _seenVersion = AppState.i.version;
    final m = _month;
    setState(() => _loading = true);
    try {
      final r = await Api.call('get_month_summary', {'month': m});
      _months[m] = Map<String, dynamic>.from(r['summary']);
      _error = null;
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic>? _day(DateTime d) {
    final s = _months[ym(d)];
    if (s == null) return null;
    final key = ymd(d);
    for (final x in s['days'] as List) {
      if (x['date'] == key) return Map<String, dynamic>.from(x);
    }
    return null;
  }

  Widget _cell(DateTime d, {bool today = false, bool outside = false}) {
    final info = outside ? null : _day(d);
    final status = '${info?['status'] ?? 'none'}';
    final color = DayStyle.color(status);
    final filled = color != Colors.transparent;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.85) : (status == 'grey' ? scheme.surfaceContainerHighest : null),
        shape: BoxShape.circle,
        border: today ? Border.all(color: scheme.onSurface, width: 2) : null,
      ),
      child: Stack(alignment: Alignment.center, children: [
        Text(
          '${d.day}',
          style: TextStyle(
            color: outside ? Colors.grey.withValues(alpha: 0.5) : filled ? Colors.white : null,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (info?['has_menu'] == true)
          Positioned(
            bottom: 2,
            child: Icon(Icons.restaurant_rounded, size: 10, color: filled ? Colors.white : accent),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _months[_month];
    final today = istToday();
    return RefreshIndicator(
      onRefresh: () async {
        _months.remove(_month);
        await _load();
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TableCalendar(
              firstDay: DateTime(2024, 1, 1),
              lastDay: DateTime(today.year + 1, 12, 31),
              focusedDay: _focused,
              currentDay: today,
              startingDayOfWeek: StartingDayOfWeek.monday,
              availableCalendarFormats: const {CalendarFormat.month: 'Month'},
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
              rowHeight: 48,
              onPageChanged: (d) {
                setState(() => _focused = d);
                if (!_months.containsKey(ym(d))) _load();
              },
              onDaySelected: (d, focused) {
                final info = _day(d);
                if (info == null) return;
                showDaySheet(context, info, _months[ym(d)]!);
              },
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (c, d, f) => _cell(d),
                todayBuilder: (c, d, f) => _cell(d, today: true),
                outsideBuilder: (c, d, f) => _cell(d, outside: true),
                selectedBuilder: (c, d, f) => _cell(d),
              ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null && s == null) ErrorRetry(error: _error!, onRetry: _load),
        const SizedBox(height: 12),
        const _Legend(),
        const SizedBox(height: 12),
        if (s != null) _MonthTotals(s: s),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => showAddHoliday(context),
          icon: const Icon(Icons.beach_access_rounded),
          label: const Text('Add holiday'),
        ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final items = [
      ('green', Icons.check_circle_rounded),
      ('yellow', Icons.star_half_rounded),
      ('red', Icons.cancel_rounded),
      ('blue', Icons.beach_access_rounded),
      ('purple', Icons.event_busy_rounded),
    ];
    return Wrap(spacing: 14, runSpacing: 8, alignment: WrapAlignment.center, children: [
      for (final (s, icon) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: DayStyle.color(s)),
          const SizedBox(width: 4),
          Text(DayStyle.label(s), style: const TextStyle(fontSize: 12)),
        ]),
      const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 14, color: StatusColors.future),
        SizedBox(width: 4),
        Text('Upcoming', style: TextStyle(fontSize: 12)),
      ]),
      const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.restaurant_rounded, size: 14, color: accent),
        SizedBox(width: 4),
        Text('Menu set', style: TextStyle(fontSize: 12)),
      ]),
    ]);
  }
}

class _MonthTotals extends StatelessWidget {
  const _MonthTotals({required this.s});
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final t = s['totals'] as Map;
    final c = s['counts'] as Map;
    final p = s['payment'] as Map?;
    return SectionCard(
      title: monthLabel(s['month']),
      trailing: p != null
          ? const StatusPill('done', dense: true)
          : null,
      child: Column(children: [
        _row('Earned', rupees(t['earned']), bold: true),
        _row('Visits done / missed', '${c['visits_done']} / ${c['missed']}'),
        _row('Lost', rupees(t['lost'])),
        if (p != null) _row('Paid on', longDate(p['paid_on'])),
      ]),
    );
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a)),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
}
