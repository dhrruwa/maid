import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/i18n.dart';
import '../core/offline_queue.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/video.dart';
import 'history_screen.dart';
import 'leave_screen.dart';
import 'pairing_screen.dart';
import 'scan_flow.dart';

/// Home: salary card → today → big Scan QR → what to cook → Request leave / My history.
/// (Reference: Sweatcoin home – one big number, one dominant action.)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static final _tick = ValueNotifier<int>(0);

  /// Ask Home to reload (after a scan, a push, an upload…).
  static void refreshAll() => _tick.value++;

  /// Set after a successful scan so Home shows "+₹100".
  static int? justEarned;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _salary;
  Map<String, dynamic>? _menuToday;
  Map<String, dynamic>? _menuTomorrow;
  bool _fromCache = false;
  bool _loading = false;
  String? _error;
  int? _bump;
  late int _tab = istNow().hour >= 21 ? 1 : 0; // after 9 PM show tomorrow
  StreamSubscription? _uploads;
  StreamSubscription? _pendingSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeScreen._tick.addListener(_load);
    _uploads = OfflineQueue.results.listen(_showUploads);
    _pendingSub = OfflineQueue.changes.listen((_) => mounted ? setState(() {}) : null);
    _readCache();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HomeScreen._tick.removeListener(_load);
    _uploads?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      OfflineQueue.sync();
      _load();
    }
  }

  void _readCache() {
    final raw = Device.prefs.getString('home_cache');
    if (raw == null) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    _salary = m['salary'];
    _menuToday = m['today'];
    _menuTomorrow = m['tomorrow'];
    _fromCache = true;
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final res = await Future.wait([
        Api.call('get_live_salary'),
        Api.call('get_menu', {'date': istDate()}),
        Api.call('get_menu', {'date': istDate(1)}),
      ]);
      final salary = Map<String, dynamic>.from(res[0]['salary']);
      final old = (_salary?['earned'] as num?)?.toInt();
      final now = (salary['earned'] as num).toInt();
      final bump = HomeScreen.justEarned ?? (old != null && now > old && !_fromCache ? now - old : null);
      HomeScreen.justEarned = null;
      if (!mounted) return;
      setState(() {
        _salary = salary;
        _menuToday = res[1];
        _menuTomorrow = res[2];
        _fromCache = false;
        _error = null;
        _bump = bump;
      });
      Device.prefs.setString('home_cache', jsonEncode({'salary': salary, 'today': res[1], 'tomorrow': res[2]}));
    } on ApiError catch (e) {
      if (e.code == 'NOT_PAIRED' && mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const PairingScreen()), (_) => false);
        return;
      }
      if (mounted) setState(() => _error = e.friendly);
    } finally {
      _loading = false;
    }
  }

  void _showUploads(List<UploadResult> results) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in results)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(r.error == null ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: r.error == null ? StatusColors.done : StatusColors.missed, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.error == null ? L.t('uploaded_ok') : L.t('uploaded_fail'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(
                      r.error == null
                          ? '${L.slot('${r.attendance!['slot']}')} · ${L.time('${r.attendance!['scanned_at']}')} · +${rupees(r.attendance!['amount'])}'
                          : r.error!.friendly,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ]),
                ),
              ]),
            ),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(L.t('ok')))],
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final name = Device.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? L.t('app_title') : L.t('hello', {'name': name})),
        actions: [LangButton(onChanged: () => setState(() {}))],
      ),
      body: _salary == null
          ? (_error != null
              ? ErrorBox(text: _error!, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: () async {
                await OfflineQueue.sync();
                await _load();
              },
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
                if (OfflineQueue.count > 0) ...[
                  _Banner(
                    icon: Icons.cloud_upload_rounded,
                    color: StatusColors.wait,
                    text: L.t('offline_pending', {'count': OfflineQueue.count}),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_fromCache || _error != null) ...[
                  _Banner(icon: Icons.wifi_off_rounded, color: StatusColors.grey, text: L.t('showing_saved')),
                  const SizedBox(height: 10),
                ],
                _SalaryCard(s: _salary!, bump: _bump),
                const SizedBox(height: 14),
                if (_salary!['today_info'] != null) ...[
                  _TodayCard(day: Map<String, dynamic>.from(_salary!['today_info'])),
                  const SizedBox(height: 16),
                ],
                BigButton(
                  icon: Icons.qr_code_scanner_rounded,
                  label: L.t('scan_qr'),
                  height: 92,
                  iconColor: accent,
                  onPressed: () => startScan(context),
                ),
                const SizedBox(height: 16),
                _CookCard(
                  tab: _tab,
                  onTab: (t) => setState(() => _tab = t),
                  today: _menuToday,
                  tomorrow: _menuTomorrow,
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: BigButton(
                      icon: Icons.event_busy_rounded,
                      label: L.t('request_leave'),
                      filled: false,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaveScreen())),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BigButton(
                      icon: Icons.history_rounded,
                      label: L.t('my_history'),
                      filled: false,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
                    ),
                  ),
                ]),
              ]),
            ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _SalaryCard extends StatelessWidget {
  const _SalaryCard({required this.s, this.bump});
  final Map<String, dynamic> s;
  final int? bump;

  void _details(BuildContext context) {
    final b = Map<String, dynamic>.from(s['breakdown']);
    Widget row(IconData i, String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(i, size: 28, color: accent),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 18, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: bold ? FontWeight.w900 : FontWeight.w700)),
          ]),
        );
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(L.t('breakdown_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          row(Icons.work_rounded, L.t('weekday_visits'),
              '${b['weekday_visits']} × ${rupees(b['weekday_rate'])} = ${rupees(b['weekday_amount'])}'),
          row(Icons.weekend_rounded, L.t('weekend_visits'),
              '${b['weekend_visits']} × ${rupees(b['weekend_rate'])} = ${rupees(b['weekend_amount'])}'),
          row(Icons.beach_access_rounded, L.t('paid_off'), rupees(b['paid_off_amount'])),
          const Divider(height: 20),
          row(Icons.account_balance_wallet_rounded, L.t('total'), rupees(b['total']), bold: true),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final earned = (s['earned'] as num).toInt();
    final possible = (s['expected_total'] as num).toInt();
    final progress = possible == 0 ? 0.0 : (earned / possible).clamp(0.0, 1.0);
    final last = s['last_payment'] as Map?;
    final lastMonthPaid = last != null && '${last['month']}' == _prevMonth('${s['month']}');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _details(context),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.account_balance_wallet_rounded, color: accent, size: 26),
              const SizedBox(width: 8),
              Expanded(child: Text(L.t('earned_so_far'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
            ]),
            Text(L.t('earned_period', {'from': L.shortDate('${s['from']}')}), style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: (earned - (bump ?? 0)).toDouble(), end: earned.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOut,
                builder: (_, v, _) => Text(rupees(v.round()),
                    style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900, height: 1.1)),
              ),
              const SizedBox(width: 10),
              if (bump != null && bump! > 0) _BumpChip(key: ValueKey(earned), amount: bump!),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(value: progress, minHeight: 14, color: StatusColors.done),
            ),
            const SizedBox(height: 12),
            Text(L.t('can_earn', {'amount': rupees(possible)}), style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.event_available_rounded, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  L.t('salary_on', {'date': L.shortDate('${s['payday']}'), 'days': s['days_to_payday']}),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
            if (lastMonthPaid) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: StatusColors.done.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  L.t('salary_paid', {
                    'month': L.monthName('${last['month']}'),
                    'amount': rupees(last['total_amount']),
                    'date': L.shortDate('${last['paid_on']}'),
                  }),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: StatusColors.done),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(L.t('tap_details'), style: const TextStyle(fontSize: 14, color: StatusColors.grey)),
              const Icon(Icons.chevron_right_rounded, color: StatusColors.grey),
            ]),
          ]),
        ),
      ),
    );
  }

  static String _prevMonth(String ym) {
    final d = DateTime.parse('$ym-01');
    final p = DateTime(d.year, d.month - 1, 1);
    return '${p.year}-${p.month.toString().padLeft(2, '0')}';
  }
}

/// "+₹100" that floats up and fades after a scan.
class _BumpChip extends StatelessWidget {
  const _BumpChip({super.key, required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2600),
      builder: (_, t, child) => Opacity(
        opacity: t < 0.7 ? 1 : (1 - (t - 0.7) / 0.3),
        child: Transform.translate(offset: Offset(0, -14 * t), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: StatusColors.done, borderRadius: BorderRadius.circular(20)),
        child: Text('+${rupees(amount)}',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.day});
  final Map<String, dynamic> day;

  @override
  Widget build(BuildContext context) {
    final slots = day['slots'] as Map;
    Widget row(String slot) {
      final info = slots[slot] as Map;
      final look = SlotLook.of('${info['state']}');
      final att = info['attendance'] as Map?;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(slot == 'morning' ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded, size: 28),
          const SizedBox(width: 10),
          SizedBox(width: 96, child: Text(L.slot(slot), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          Icon(look.icon, color: look.color, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              att != null ? '${look.text} · ${L.time('${att['scanned_at']}')}' : look.text,
              style: TextStyle(fontSize: 17, color: look.color, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${L.t('today')} · ${L.longDate('${day['date']}')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          row('morning'),
          row('evening'),
        ]),
      ),
    );
  }
}

class _CookCard extends StatelessWidget {
  const _CookCard({required this.tab, required this.onTab, required this.today, required this.tomorrow});
  final int tab;
  final ValueChanged<int> onTab;
  final Map<String, dynamic>? today;
  final Map<String, dynamic>? tomorrow;

  @override
  Widget build(BuildContext context) {
    final hour = istNow().hour;
    final List<Widget> cards;
    if (tab == 0) {
      // Morning card until noon, evening card from noon.
      final slot = hour < 12 ? 'morning' : 'evening';
      cards = [_SlotMenu(slot: slot, data: today?[slot] as Map?)];
    } else {
      cards = [
        _SlotMenu(slot: 'morning', data: tomorrow?['morning'] as Map?),
        const SizedBox(height: 12),
        _SlotMenu(slot: 'evening', data: tomorrow?['evening'] as Map?),
      ];
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.restaurant_menu_rounded, color: accent, size: 28),
            const SizedBox(width: 8),
            Text(L.t('what_to_cook'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(48, 52),
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            segments: [
              ButtonSegment(value: 0, label: Text(L.t('today')), icon: const Icon(Icons.today_rounded)),
              ButtonSegment(value: 1, label: Text(L.t('tomorrow')), icon: const Icon(Icons.event_rounded)),
            ],
            selected: {tab},
            onSelectionChanged: (s) => onTab(s.first),
          ),
          const SizedBox(height: 14),
          ...cards,
        ]),
      ),
    );
  }
}

class _SlotMenu extends StatelessWidget {
  const _SlotMenu({required this.slot, required this.data});
  final String slot;
  final Map? data;

  @override
  Widget build(BuildContext context) {
    final items = (data?['items'] as List?) ?? [];
    final off = data?['off'] as Map?;
    Widget body;
    if (off != null) {
      final type = '${off['type']}';
      final look = type == 'holiday'
          ? SlotLook.of('holiday_paid')
          : type == 'leave'
              ? SlotLook.of('leave_paid')
              : SlotLook.of('not_needed');
      body = Row(children: [
        Icon(look.icon, color: look.color, size: 30),
        const SizedBox(width: 10),
        Expanded(child: Text(look.text, style: TextStyle(fontSize: 18, color: look.color, fontWeight: FontWeight.w700))),
      ]);
    } else if (items.isEmpty) {
      body = Row(children: [
        const Icon(Icons.help_outline_rounded, size: 28, color: StatusColors.grey),
        const SizedBox(width: 10),
        Expanded(child: Text(L.t('no_menu'), style: const TextStyle(fontSize: 17))),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final it in items) ...[
          Text('${it['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          for (final n in [it['notes'], it['dish_notes']])
            if (n != null && '$n'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.sticky_note_2_outlined, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text('$n', style: const TextStyle(fontSize: 17))),
                ]),
              ),
          if (it['youtube_url'] != null) ...[
            const SizedBox(height: 8),
            VideoThumb(url: '${it['youtube_url']}', title: '${it['name']}'),
            TextButton.icon(
              onPressed: () => openInYoutube('${it['youtube_url']}'),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(L.t('open_youtube'), style: const TextStyle(fontSize: 16)),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: appBackground,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(slot == 'morning' ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded, size: 24),
          const SizedBox(width: 8),
          Text(L.slot(slot), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        body,
      ]),
    );
  }
}
