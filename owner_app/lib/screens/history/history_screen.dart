import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/export.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../leave/leave_screen.dart';
import 'slip_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 4,
      child: Column(children: [
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [Tab(text: 'Activity'), Tab(text: 'Payments'), Tab(text: 'Menu'), Tab(text: 'Leave')],
        ),
        Expanded(
          child: TabBarView(children: [
            ActivityTab(),
            PaymentsTab(),
            MenuHistoryTab(),
            LeaveScreen(embedded: true),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity (reference: LinkedIn notifications with filter chips, Fresha activity)
// ---------------------------------------------------------------------------

const _types = {
  'attendance': ('Attendance', Icons.how_to_reg_rounded),
  'menu': ('Menu', Icons.restaurant_menu_rounded),
  'leave': ('Leave', Icons.event_busy_rounded),
  'holiday': ('Holiday', Icons.beach_access_rounded),
  'payment': ('Payment', Icons.payments_rounded),
  'settings': ('Settings', Icons.settings_rounded),
};

IconData _iconFor(String entity) => switch (entity) {
      'attendance' => Icons.how_to_reg_rounded,
      'menu' || 'dishes' => Icons.restaurant_menu_rounded,
      'leave_requests' => Icons.event_busy_rounded,
      'holidays' => Icons.beach_access_rounded,
      'payments' || 'monthly_snapshots' => Icons.payments_rounded,
      'cook_device' || 'pairing_tokens' => Icons.phonelink_ring_rounded,
      _ => Icons.settings_rounded,
    };

/// Body of the Activity tab's first page with no filters: saved on the phone
/// and fetched ahead of time from Home.
const Map<String, dynamic> activityFirstPage = {'limit': 50};

class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key});

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> with AutomaticKeepAliveClientMixin {
  final _selected = <String>{};
  String? _actor;
  DateTimeRange? _range;
  String _search = '';
  final _events = <Map<String, dynamic>>[];
  int? _next;
  bool _loading = false;
  Object? _error;
  int _seenVersion = -1;
  int _request = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _showSaved();
    AppState.i.addListener(_onState);
    _load(reset: true);
  }

  @override
  void dispose() {
    AppState.i.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (AppState.i.version != _seenVersion) _load(reset: true);
  }

  bool get _unfiltered => _selected.isEmpty && _actor == null && _range == null && _search.isEmpty;

  /// Shows the saved first page (no filters) at once, if there is one.
  void _showSaved() {
    if (!_unfiltered) return;
    final c = Api.cached('get_activity', body: activityFirstPage);
    if (c == null) return;
    _events
      ..clear()
      ..addAll((c['events'] as List).map((e) => Map<String, dynamic>.from(e)));
    _next = c['next_before_id'] as int?;
  }

  /// Filters changed: start again from the first page. The list under the old
  /// filters is not left on screen (under the new chips) while the new one loads.
  void _refilter() {
    setState(() {
      _events.clear();
      _next = null;
      _error = null;
      _showSaved();
    });
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    _seenVersion = AppState.i.version;
    // "Load more" waits for the page on its way; a new first page replaces it.
    if (_loading && !reset) return;
    final req = ++_request;
    final body = <String, dynamic>{
      if (_selected.isNotEmpty) 'types': _selected.toList(),
      if (_actor != null) 'actor': _actor,
      if (_range != null) 'from': ymd(_range!.start),
      if (_range != null) 'to': ymd(_range!.end),
      if (_search.isNotEmpty) 'search': _search,
      if (!reset && _next != null) 'before_id': _next,
      'limit': activityFirstPage['limit'],
    };
    setState(() => _loading = true);
    try {
      // Only the first page without filters is saved for next time.
      final r = reset && _unfiltered
          ? await Api.read('get_activity', body: body)
          : await Api.call('get_activity', body);
      if (!mounted || req != _request) return;
      setState(() {
        if (reset) _events.clear();
        _events.addAll((r['events'] as List).map((e) => Map<String, dynamic>.from(e)));
        _next = r['next_before_id'] as int?;
        _error = null;
      });
    } catch (e) {
      if (mounted && req == _request) setState(() => _error = e);
    }
    if (mounted && req == _request) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search dish name or note',
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(_range == null ? Icons.date_range_outlined : Icons.event_available_rounded,
                  color: _range == null ? null : accent),
              tooltip: 'Date range',
              onPressed: () async {
                final t = istToday();
                final r = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: t,
                  initialDateRange: _range,
                );
                setState(() => _range = r);
                _refilter();
              },
            ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            _search = v.trim();
            _refilter();
          },
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final e in _types.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(e.value.$2, size: 16),
                label: Text(e.value.$1),
                selected: _selected.contains(e.key),
                onSelected: (v) {
                  setState(() => v ? _selected.add(e.key) : _selected.remove(e.key));
                  _refilter();
                },
              ),
            ),
          const VerticalDivider(),
          for (final a in ['owner', 'maid', 'system'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(a[0].toUpperCase() + a.substring(1)),
                selected: _actor == a,
                onSelected: (v) {
                  setState(() => _actor = v ? a : null);
                  _refilter();
                },
              ),
            ),
        ]),
      ),
      if (_range != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InputChip(
            label: Text('${shortDate(ymd(_range!.start))} – ${shortDate(ymd(_range!.end))}'),
            onDeleted: () {
              setState(() => _range = null);
              _refilter();
            },
          ),
        ),
      if (_loading && _events.isEmpty) const LinearProgressIndicator(),
      if (_error != null && _events.isNotEmpty) StaleNote(error: _error!, onRetry: () => _load(reset: true)),
      Expanded(
        child: _error != null && _events.isEmpty
            ? ErrorRetry(error: _error!, onRetry: () => _load(reset: true))
            : RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: _events.isEmpty && !_loading
                    ? ListView(children: const [
                        Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nothing here yet'))),
                      ])
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
                        itemCount: _events.length + (_next != null ? 1 : 0),
                        itemBuilder: (c, i) {
                          if (i == _events.length) {
                            return Padding(
                              padding: const EdgeInsets.all(8),
                              child: OutlinedButton(
                                onPressed: _loading ? null : () => _load(),
                                child: const Text('Load more'),
                              ),
                            );
                          }
                          final e = _events[i];
                          return EntryAnimation(index: i, child: _EventTile(e: e, onChanged: () => AppState.i.changed()));
                        },
                      ),
              ),
      ),
    ]);
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.e, required this.onChanged});
  final Map<String, dynamic> e;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final actor = '${e['actor']}';
    final color = actor == 'maid' ? StatusColors.done : actor == 'owner' ? accent : StatusColors.future;
    final deleted = e['action'] == 'delete';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showEvent(context, e, onChanged),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(_iconFor('${e['entity_type']}'), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['text']}',
                  style: TextStyle(decoration: deleted ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w500)),
              if ((e['note'] ?? '').toString().isNotEmpty && e['entity_type'] == 'attendance')
                Text('Note: ${e['note']}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(istDateTime(e['created_at']), style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (e['can_restore'] == true) const Icon(Icons.restore_rounded, size: 18, color: accent),
        ]),
      ),
    );
  }
}

void _showEvent(BuildContext context, Map<String, dynamic> e, VoidCallback onChanged) {
  final oldV = Map<String, dynamic>.from(e['old_value'] ?? {});
  final newV = Map<String, dynamic>.from(e['new_value'] ?? {});
  const hidden = {'id', 'house_id', 'created_at', 'updated_at', 'device_id'};
  final keys = {...oldV.keys, ...newV.keys}.where((k) => !hidden.contains(k)).toList();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text('${e['text']}', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text('${istDateTime(e['created_at'])} · by ${e['actor']}', style: Theme.of(c).textTheme.bodySmall),
        const SizedBox(height: 16),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
          border: TableBorder(horizontalInside: BorderSide(color: Theme.of(c).dividerColor)),
          children: [
            const TableRow(children: [
              Padding(padding: EdgeInsets.all(6), child: Text('Field', style: TextStyle(fontWeight: FontWeight.w700))),
              Padding(padding: EdgeInsets.all(6), child: Text('Old', style: TextStyle(fontWeight: FontWeight.w700))),
              Padding(padding: EdgeInsets.all(6), child: Text('New', style: TextStyle(fontWeight: FontWeight.w700))),
            ]),
            for (final k in keys)
              TableRow(
                decoration: BoxDecoration(
                  color: '${oldV[k]}' != '${newV[k]}' && oldV.isNotEmpty ? accent.withValues(alpha: 0.08) : null,
                ),
                children: [
                  Padding(padding: const EdgeInsets.all(6), child: Text(k.replaceAll('_', ' '))),
                  Padding(padding: const EdgeInsets.all(6), child: Text(oldV.isEmpty ? '—' : '${oldV[k] ?? '—'}')),
                  Padding(padding: const EdgeInsets.all(6), child: Text('${newV[k] ?? '—'}')),
                ],
              ),
          ],
        ),
        if (e['can_restore'] == true) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Restore'),
            onPressed: () async {
              final r = await busy(c, () => Api.call('restore_item', {
                    'entity_type': e['entity_type'],
                    'id': e['entity_id'],
                  }), success: 'Restored');
              if (r != null && c.mounted) {
                Navigator.pop(c);
                onChanged();
              }
            },
          ),
        ],
      ]),
    ),
  );
}

// ---------------------------------------------------------------------------
// Payments (reference: Lloyds statements list)
// ---------------------------------------------------------------------------

class PaymentsTab extends StatefulWidget {
  const PaymentsTab({super.key});

  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<PaymentsTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _months = _parse(Api.cached('list_months'));
  Object? _error;
  int _seenVersion = -1;

  static List<Map<String, dynamic>>? _parse(Map<String, dynamic>? r) =>
      r == null ? null : (r['months'] as List).map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  bool get wantKeepAlive => true;

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
      final r = await Api.read('list_months');
      if (mounted) {
        setState(() {
          _months = _parse(r);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_months == null) {
      return _error != null ? ErrorRetry(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom), children: [
        if (_error != null) StaleNote(error: _error!, onRetry: _load),
        for (final (i, m) in _months!.indexed)
          EntryAnimation(index: i, child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Icon(
                m['paid'] == true ? Icons.check_circle_rounded : m['is_current'] == true ? Icons.timelapse_rounded : Icons.pending_actions_rounded,
                color: m['paid'] == true ? StatusColors.done : m['is_current'] == true ? StatusColors.future : StatusColors.partial,
              ),
              title: Text(monthLabel(m['month']), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                m['paid'] == true
                    ? 'Paid on ${longDate(m['paid_on'])} · ${m['visits']} visits'
                    : m['is_current'] == true
                        ? 'In progress · ${m['visits']} visits'
                        : 'Not paid yet · ${m['visits']} visits',
              ),
              trailing: Text(rupees(m['paid'] == true ? m['paid_amount'] : m['total']),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SlipScreen(month: m['month']))),
            ),
          )),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => busy(context, exportAllData),
          icon: const Icon(Icons.table_view_rounded),
          label: const Text('Export all data (Excel)'),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Menu history + most cooked dishes
// ---------------------------------------------------------------------------

class MenuHistoryTab extends StatefulWidget {
  const MenuHistoryTab({super.key});

  @override
  State<MenuHistoryTab> createState() => _MenuHistoryTabState();
}

class _MenuHistoryTabState extends State<MenuHistoryTab> with AutomaticKeepAliveClientMixin {
  int _daysBack = 60;
  Map<String, dynamic>? _d;
  Object? _error;
  int _seenVersion = -1;
  int _request = 0;

  @override
  bool get wantKeepAlive => true;

  /// Saved per period length ("last 60 days"), so yesterday's copy still shows today.
  String get _key => 'last$_daysBack';

  @override
  void initState() {
    super.initState();
    _d = Api.cached('get_menu_history', key: _key);
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
    final req = ++_request;
    final t = istToday();
    try {
      final r = await Api.read('get_menu_history', key: _key, body: {
        'from': ymd(t.subtract(Duration(days: _daysBack))),
        'to': ymd(t),
      });
      if (mounted && req == _request) {
        setState(() {
          _d = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && req == _request) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_d == null) {
      return _error != null ? ErrorRetry(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    final top = (_d!['top_dishes'] as List);
    final days = (_d!['days'] as List);
    String names(List l) => l.isEmpty ? '—' : l.map((e) => e['name']).join(', ');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom), children: [
        if (_error != null) StaleNote(error: _error!, onRetry: _load),
        if (top.isNotEmpty)
          SectionCard(
            title: 'Most cooked dishes',
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in top) Chip(label: Text('${t['name']} · ${t['count']}')),
            ]),
          ),
        const SizedBox(height: 12),
        if (days.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No menus in this period'))),
        for (final d in days)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(longDate(d['date']), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Morning: ${names(d['morning'])}\nEvening: ${names(d['evening'])}'),
            ),
          ),
        OutlinedButton(
          onPressed: () {
            setState(() => _daysBack += 90);
            _load();
          },
          child: const Text('Show older'),
        ),
      ]),
    );
  }
}
