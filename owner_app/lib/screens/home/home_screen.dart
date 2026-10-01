import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../../widgets/week_timeline.dart';
import '../history/history_screen.dart';
import '../holidays/holidays_screen.dart';
import '../leave/leave_screen.dart';
import '../menu/bookings.dart';
import '../qr_views.dart';
import '../shell.dart';

/// Dashboard (reference: Lloyds net-worth card + Cash App earnings card).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Last saved dashboard: shown at once, then refreshed in the background.
  Map<String, dynamic>? _d = Api.cached('get_dashboard');
  Object? _error;
  int _seenVersion = -1;

  /// [_d] came from the server in this session (not only the saved copy), so
  /// the salary due can be acted on.
  bool _fresh = false;

  /// Today's `get_menu` (the same saved copy as the Menu tab's): the dashboard
  /// has no family bookings, so the preview's counts come from here.
  Map<String, dynamic>? _todayMenu = Api.cached('get_menu', body: {'date': ymd(istToday())});

  /// When the other tabs' data was last fetched ahead of time.
  static DateTime? _prefetchedAt;

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
    _loadTodayMenu();
    try {
      final d = await Api.read('get_dashboard');
      if (mounted) setState(() {
        _d = d;
        _error = null;
        _fresh = true;
      });
      _prefetch();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Refreshes today's bookings for the menu preview. A failure keeps the
  /// saved counts (the preview works without them).
  Future<void> _loadTodayMenu() async {
    final date = ymd(istToday());
    try {
      final r = await Api.read('get_menu', body: {'date': date});
      if (mounted) setState(() => _todayMenu = r);
    } catch (_) {}
  }

  /// Fetches what the other tabs show first, in the background, so they open
  /// instantly. At most every 10 minutes (e.g. again when the app comes back
  /// the next day); failures are ignored.
  void _prefetch() {
    final now = DateTime.now();
    if (_prefetchedAt != null && now.difference(_prefetchedAt!) < const Duration(minutes: 10)) return;
    _prefetchedAt = now;
    final today = istToday();
    Api.prefetch([
      ('get_month_summary', {'month': ym(today)}),
      ('get_menu', {'date': ymd(today)}),
      ('get_menu', {'date': ymd(today.add(const Duration(days: 1)))}),
      ('list_months', {}),
      ('get_activity', activityFirstPage),
      ('list_leave', {}),
    ]);
  }

  Future<void> _markPaid(Map due) async {
    final ok = await confirm(
      context,
      'Mark ${monthName(due['month'])} as paid?',
      '${rupees(due['total'])} will be recorded as paid today. The month summary and slip will be frozen '
          'and the cook will be notified.',
      ok: 'Mark as paid',
    );
    if (!ok || !mounted) return;
    final r = await busy(context, () => Api.call('mark_paid', {'month': due['month']}), success: 'Marked as paid');
    if (r != null) AppState.i.changed();
  }

  Future<void> _decide(Map l, String decision) async {
    final r = await busy(context, () => Api.call('decide_leave', {'id': l['id'], 'decision': decision}),
        success: decision == 'rejected' ? 'Leave rejected' : 'Leave approved');
    if (r != null) AppState.i.changed();
  }

  @override
  Widget build(BuildContext context) {
    if (_d == null) {
      return _error != null ? ErrorRetry(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    final d = _d!;
    final s = Map<String, dynamic>.from(d['salary']);
    final today = d['today'] as Map?;
    final due = d['salary_due'] as Map?;
    final pending = (d['pending_leaves'] as List?) ?? [];
    final cook = d['cook'] as Map?;

    final sections = <Widget>[
      // "Mark as paid" waits for the server's figure: the saved one may be out of date.
      if (due != null) _DueBanner(due: due, onPaid: _fresh ? () => _markPaid(due) : null),
      if (cook == null)
        SectionCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PairScreen())),
          child: const Row(children: [
            Icon(Icons.phonelink_ring_rounded, color: accent),
            SizedBox(width: 12),
            Expanded(child: Text('No maid phone paired yet. Tap to pair.')),
            Icon(Icons.chevron_right),
          ]),
        ),
      _SalaryCard(s: s),
      if (today != null) _TodayCard(today: today, cookName: cook?['name']),
      const WeekTimeline(),
      if (today != null)
        _MenuPreview(today: today, menu: _todayMenu?['date'] == today['date'] ? _todayMenu : null),
      _CountsCard(counts: Map<String, dynamic>.from(s['counts'])),
      if (pending.isNotEmpty)
        SectionCard(
          title: 'Leave requests (${pending.length})',
          trailing: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaveScreen())),
            child: const Text('See all'),
          ),
          child: Column(children: [
            for (final l in pending) LeaveRequestTile(leave: Map<String, dynamic>.from(l), onDecide: _decide),
          ]),
        ),
      Row(children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.beach_access_rounded,
            label: 'Holidays',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HolidaysScreen())),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.event_busy_rounded,
            label: 'Leave',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaveScreen())),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.qr_code_2_rounded,
            label: 'House QR',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HouseQrScreen())),
          ),
        ),
      ]),
    ];

    final list = RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        // Bottom padding keeps the last card clear of the floating tab bar.
        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => EntryAnimation(index: i, child: sections[i]),
      ),
    );
    // The note sits outside the list so it does not shift the cards' slots
    // (which would rebuild the week timeline and fetch it again).
    return Column(children: [
      if (_error != null) StaleNote(error: _error!, onRetry: _load),
      Expanded(child: list),
    ]);
  }
}

class _DueBanner extends StatelessWidget {
  const _DueBanner({required this.due, required this.onPaid});
  final Map due;
  final VoidCallback? onPaid;

  @override
  Widget build(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.all(16),
      tintColor: accent.withValues(alpha: 0.14),
      child: Row(children: [
        const Icon(Icons.payments_rounded, color: accent, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Salary due', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('${rupees(due['total'])} for ${monthName(due['month'])}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ),
        FilledButton(onPressed: onPaid, child: const Text('Mark as paid')),
      ]),
    );
  }
}

class _SalaryCard extends StatefulWidget {
  const _SalaryCard({required this.s});
  final Map<String, dynamic> s;

  @override
  State<_SalaryCard> createState() => _SalaryCardState();
}

class _SalaryCardState extends State<_SalaryCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final earned = (s['earned'] as num).toInt();
    final expected = (s['expected_total'] as num).toInt();
    final b = Map<String, dynamic>.from(s['breakdown']);
    final progress = expected == 0 ? 0.0 : (earned / expected).clamp(0.0, 1.0);
    final days = s['days_to_payday'];
    final tt = Theme.of(context).textTheme;

    return SectionCard(
      onTap: () => setState(() => _open = !_open),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Earned so far (${shortDate(s['from'])} – today)', style: tt.bodyMedium),
        const SizedBox(height: 4),
        Text(rupees(earned), style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: progress, minHeight: 10),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.trending_up_rounded, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Expected by ${shortDate(s['cycle_end'])}: ${rupees(expected)}')),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.event_available_rounded, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Payday: ${shortDate(s['payday'])} (in $days day${days == 1 ? '' : 's'})')),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.trending_down_rounded, size: 18, color: StatusColors.missed),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Lost this month: ${rupees(s['lost'])}',
                style: const TextStyle(color: StatusColors.missed, fontWeight: FontWeight.w600)),
          ),
          Icon(_open ? Icons.expand_less : Icons.expand_more),
        ]),
        if (_open) ...[
          const Divider(height: 24),
          _line('Weekday visits', '${b['weekday_visits']} × ${rupees(b['weekday_rate'])}', b['weekday_amount']),
          _line('Weekend visits', '${b['weekend_visits']} × ${rupees(b['weekend_rate'])}', b['weekend_amount']),
          _line(
            'Paid holidays / leave',
            b['paid_off_rate'] == null
                ? '${b['paid_off_slots']} meal(s)'
                : '${b['paid_off_slots']} × ${rupees(b['paid_off_rate'])}',
            b['paid_off_amount'],
          ),
          const Divider(height: 16),
          _line('Total', '', b['total'], bold: true),
        ],
      ]),
    );
  }

  Widget _line(String a, String b, num amount, {bool bold = false}) {
    final st = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(a, style: st)),
        Text(b, style: const TextStyle(color: Colors.grey)),
        const SizedBox(width: 12),
        SizedBox(width: 80, child: Text(rupees(amount), textAlign: TextAlign.right, style: st)),
      ]),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today, this.cookName});
  final Map today;
  final String? cookName;

  @override
  Widget build(BuildContext context) {
    Widget slot(String name, Map info) {
      final att = info['attendance'] as Map?;
      String? detail;
      if (att != null) {
        detail = '${istTime(att['scanned_at'])}'
            '${att['is_offline'] == true ? ' · offline' : ''}${att['is_manual'] == true ? ' · manual' : ''}';
      }
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SlotStyle.of('${info['state']}').color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            StatusPill('${info['state']}', dense: true),
            if (detail != null) ...[const SizedBox(height: 6), Text(detail, style: const TextStyle(fontSize: 12))],
          ]),
        ),
      );
    }

    final slots = today['slots'] as Map;
    return SectionCard(
      title: 'Today · ${longDate(today['date'])}',
      child: Row(children: [
        slot('Morning', slots['morning']),
        const SizedBox(width: 10),
        slot('Evening', slots['evening']),
      ]),
    );
  }
}

class _MenuPreview extends StatelessWidget {
  const _MenuPreview({required this.today, this.menu});
  final Map today;

  /// Today's `get_menu` reply, for the number of people eating (null until loaded).
  final Map<String, dynamic>? menu;

  @override
  Widget build(BuildContext context) {
    final dishes = today['menu'] as Map;
    String names(List l) => l.isEmpty ? 'Not set' : l.map((e) => e['name']).join(', ');
    return SectionCard(
      title: "Today's menu",
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Shell.goTo(context, 2),
      child: Column(children: [
        _row(context, Icons.wb_sunny_outlined, 'Morning', names(dishes['morning'] as List), Bookings.of(menu?['morning'])),
        const SizedBox(height: 8),
        _row(context, Icons.nights_stay_outlined, 'Evening', names(dishes['evening'] as List), Bookings.of(menu?['evening'])),
      ]),
    );
  }

  Widget _row(BuildContext context, IconData i, String label, String v, Bookings? b) => Row(children: [
        Icon(i, size: 20),
        const SizedBox(width: 8),
        // Grows with the text size so "Morning" never wraps mid-word.
        SizedBox(
          width: 70 * MediaQuery.textScalerOf(context).scale(14) / 14,
          child: Text(label, maxLines: 1, softWrap: false, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(v, maxLines: 2, overflow: TextOverflow.ellipsis)),
        if (b != null) ...[const SizedBox(width: 8), _EatingCount(b.count)],
      ]);
}

/// Small pill: people icon + how many booked the meal.
class _EatingCount extends StatelessWidget {
  const _EatingCount(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = count > 0 ? accent : StatusColors.future;
    final text = count > 0 ? Theme.of(context).colorScheme.primary : StatusColors.future;
    return Semantics(
      label: count == 1 ? '1 person eating' : '$count people eating',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.people_alt_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text('$count', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: text)),
        ]),
      ),
    );
  }
}

class _CountsCard extends StatelessWidget {
  const _CountsCard({required this.counts});
  final Map<String, dynamic> counts;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Visits done', counts['visits_done'], Icons.check_circle_rounded, StatusColors.done),
      ('Missed visits', counts['missed'], Icons.cancel_rounded, StatusColors.missed),
      ('Full days', counts['full_days'], Icons.star_rounded, StatusColors.done),
      ('Half days', counts['half_days'], Icons.star_half_rounded, StatusColors.partial),
      ('Holidays', counts['holidays'], Icons.beach_access_rounded, StatusColors.holiday),
      ('Leaves', counts['leaves'], Icons.event_busy_rounded, StatusColors.leave),
    ];
    final stats = [
      for (final (label, v, icon, color) in items) Stat(label: label, value: '$v', icon: icon, color: color),
    ];
    // Two per row, each row as tall as its content (a fixed aspect ratio
    // clipped the labels, even at the default text size).
    return SectionCard(
      title: 'This month',
      child: Column(children: [
        for (var i = 0; i < stats.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: stats[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < stats.length ? stats[i + 1] : const SizedBox()),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Center(
        child: Column(children: [
          Icon(icon, color: accent),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
