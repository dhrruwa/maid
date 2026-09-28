import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'leave_screen.dart';
import 'month_screen.dart';

/// Months (salary) · Past menus · Leave. Only her own data.
/// (Reference: Lloyds statements by month, Sweatcoin transaction history.)
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L.t('my_history')),
          bottom: TabBar(
            labelStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            tabs: [Tab(text: L.t('months')), Tab(text: L.t('past_menus')), Tab(text: L.t('leave_tab'))],
          ),
        ),
        body: const TabBarView(children: [_Months(), _PastMenus(), _Leaves()]),
      ),
    );
  }
}

class _Months extends StatefulWidget {
  const _Months();

  @override
  State<_Months> createState() => _MonthsState();
}

class _MonthsState extends State<_Months> {
  List<Map<String, dynamic>>? _months;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.call('list_months');
      if (mounted) {
        setState(() {
          _months = (r['months'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.friendly);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_months == null) {
      return _error != null ? ErrorBox(text: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        for (final m in _months!)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MonthScreen(month: '${m['month']}'))),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(
                    m['paid'] == true
                        ? Icons.check_circle_rounded
                        : m['is_current'] == true
                            ? Icons.timelapse_rounded
                            : Icons.hourglass_top_rounded,
                    size: 38,
                    color: m['paid'] == true
                        ? StatusColors.done
                        : m['is_current'] == true
                            ? StatusColors.grey
                            : StatusColors.wait,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(L.monthYear('${m['month']}'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      Text(L.t('visits', {'count': m['visits']}), style: const TextStyle(fontSize: 16)),
                      Text(
                        m['paid'] == true
                            ? L.t('paid_on', {'date': L.shortDate('${m['paid_on']}')})
                            : m['is_current'] == true
                                ? L.t('in_progress')
                                : L.t('not_paid'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: m['paid'] == true ? StatusColors.done : StatusColors.grey,
                        ),
                      ),
                    ]),
                  ),
                  Text(rupees(m['paid'] == true ? m['paid_amount'] : m['total']),
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  const Icon(Icons.chevron_right_rounded),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _PastMenus extends StatefulWidget {
  const _PastMenus();

  @override
  State<_PastMenus> createState() => _PastMenusState();
}

class _PastMenusState extends State<_PastMenus> {
  DateTime _date = DateTime.parse(istDate(-1));
  Map<String, dynamic>? _menu;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _menu = null;
      _error = null;
    });
    try {
      final r = await Api.call('get_menu', {'date': ymd(_date)});
      if (mounted) setState(() => _menu = r);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.friendly);
    }
  }

  Future<void> _pick() async {
    final today = DateTime.parse(istDate());
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 730)),
      lastDate: today,
      locale: Locale(L.code),
    );
    if (d != null) {
      _date = d;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget slot(String s) {
      final items = (_menu?[s]?['items'] as List?) ?? [];
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(s == 'morning' ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded),
              const SizedBox(width: 8),
              Text(L.slot(s), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text(L.t('nothing_cooked'), style: const TextStyle(fontSize: 16, color: StatusColors.grey))
            else
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('• ${it['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                ),
          ]),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      BigButton(icon: Icons.calendar_month_rounded, label: L.longDate(ymd(_date)), filled: false, onPressed: _pick),
      const SizedBox(height: 16),
      if (_error != null)
        ErrorBox(text: _error!, onRetry: _load)
      else if (_menu == null)
        const Center(child: CircularProgressIndicator())
      else ...[
        slot('morning'),
        slot('evening'),
      ],
    ]);
  }
}

class _Leaves extends StatefulWidget {
  const _Leaves();

  @override
  State<_Leaves> createState() => _LeavesState();
}

class _LeavesState extends State<_Leaves> {
  List<Map<String, dynamic>>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.call('list_leave');
      if (mounted) setState(() => _list = (r['leaves'] as List).map((e) => Map<String, dynamic>.from(e)).toList());
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.friendly);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_list == null) {
      return _error != null ? ErrorBox(text: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    if (_list!.isEmpty) return Center(child: Text(L.t('no_requests'), style: const TextStyle(fontSize: 18)));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [for (final l in _list!) LeaveTile(leave: l)]),
    );
  }
}
