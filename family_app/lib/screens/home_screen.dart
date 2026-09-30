import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/push.dart';
import '../core/theme.dart';
import '../core/youtube.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/motion.dart';
import '../widgets/video.dart';
import 'login_screen.dart';

/// Next 7 days: Morning and Evening cards with the menu, who's eating and a
/// Book / Booked ✓ + Cancel control. The saved reply shows at once and is
/// refreshed behind; bookings change the screen straight away and roll back
/// if the server says no.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _fn = 'member_home';
  static const _req = {'days': 7};

  Map<String, dynamic>? _data;
  String? _error;
  bool _stale = false;

  int _seq = 0;
  bool _reloadWanted = false;

  /// Slots ('date|slot') whose booking is on its way to the server.
  final _busy = <String>{};
  Timer? _clock;
  StreamSubscription<Object?>? _push;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = Api.cached(_fn, _req);
    _load();
    // Booking closes at the cook's start time: keep "Book" / "Closed" honest
    // while the app stays open.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // A menu changed while the app is open: show it.
    _push = Push.foreground.listen((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _push?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final epoch = ApiCache.epoch;
    if (_data == null && _error != null) setState(() => _error = null); // Retry: spinner again
    try {
      final fresh = await Api.fetch(_fn, _req);
      if (!mounted || seq != _seq) return;
      // A booking was made while this was loading: the reply may not have it.
      if (epoch != ApiCache.epoch || _busy.isNotEmpty) {
        _reloadWanted = true;
        if (_busy.isEmpty) _reloadAfterBookings();
        return;
      }
      // The owner may have renamed the member or the house.
      final name = (fresh['member'] as Map?)?['name'];
      if (name is String && name.isNotEmpty && name != Device.name) Device.setName(name);
      final house = fresh['house_name'];
      if (house is String && house != Device.houseName) Device.setHouseName(house);
      setState(() {
        _data = fresh;
        _error = null;
        _stale = false;
      });
    } on ApiError catch (e) {
      if (!mounted || seq != _seq || e.code == 'NOT_MEMBER') return;
      setState(() {
        if (_data == null) {
          _error = e.friendly;
        } else {
          _stale = true;
        }
      });
    }
  }

  void _reloadAfterBookings() {
    if (!_reloadWanted || _busy.isNotEmpty) return;
    _reloadWanted = false;
    _load();
  }

  // ---------- bookings (optimistic) ----------

  List<Map<String, dynamic>> get _days => [
    for (final d in (_data?['days'] is List ? _data!['days'] as List : const []))
      if (d is Map) Map<String, dynamic>.from(d),
  ];

  Map<String, dynamic>? _slot(String date, String slot) {
    for (final d in (_data?['days'] as List?) ?? const []) {
      if (d is Map && d['date'] == date) {
        final s = (d['slots'] as Map?)?[slot];
        return s is Map ? Map<String, dynamic>.from(jsonDecode(jsonEncode(s)) as Map) : null;
      }
    }
    return null;
  }

  void _putSlot(String date, String slot, Map<String, dynamic> value) {
    final data = Map<String, dynamic>.from(_data!);
    data['days'] = [
      for (final d in (data['days'] as List))
        if (d is Map && d['date'] == date)
          {
            ...Map<String, dynamic>.from(d),
            'slots': {...Map<String, dynamic>.from(d['slots'] as Map), slot: value},
          }
        else
          d,
    ];
    _data = data;
  }

  /// What the slot looks like once the server agrees.
  static Map<String, dynamic> _optimistic(Map<String, dynamic> s, {required bool book, String? note}) {
    final m = Map<String, dynamic>.from(s);
    final me = Device.name.trim().toLowerCase();
    final bookings = Map<String, dynamic>.from((m['bookings'] as Map?) ?? const {});
    final people = [
      for (final p in (bookings['people'] is List ? bookings['people'] as List : const []))
        if (p is Map) Map<String, dynamic>.from(p),
    ];
    var count = bookings['count'] is num ? (bookings['count'] as num).toInt() : people.length;
    final wasBooked = m['booked'] == true;
    final mine = people.indexWhere((p) => '${p['name']}'.trim().toLowerCase() == me);
    if (book) {
      final n = (note ?? m['note'])?.toString().trim();
      m['note'] = (n == null || n.isEmpty) ? null : n;
      m['booked'] = true;
      if (!wasBooked) {
        count++;
        if (mine < 0) people.add({'name': Device.name, 'note': m['note']});
      } else if (mine >= 0) {
        people[mine]['note'] = m['note'];
      }
    } else {
      m['booked'] = false;
      m['note'] = null;
      if (wasBooked) {
        count = count > 0 ? count - 1 : 0;
        if (mine >= 0) people.removeAt(mine);
      }
    }
    m['bookings'] = {...bookings, 'count': count, 'people': people};
    return m;
  }

  /// The SLOT in book_meal's reply (whichever way it is wrapped).
  static Map<String, dynamic>? _slotFrom(Map<String, dynamic> res, String slot) {
    for (final k in ['slot', 'data', slot]) {
      final v = res[k];
      if (v is Map && v.containsKey('booked')) return Map<String, dynamic>.from(v);
    }
    if (res.containsKey('booked') && res.containsKey('bookings')) {
      return Map<String, dynamic>.from(res)..remove('ok');
    }
    return null;
  }

  Future<void> _book(String date, String slot, {required bool book, String? note}) async {
    final key = '$date|$slot';
    if (_busy.contains(key) || _data == null) return;
    final before = _slot(date, slot);
    if (before == null) return;
    final guess = _optimistic(before, book: book, note: note);
    HapticFeedback.selectionClick();
    setState(() {
      _busy.add(key);
      _putSlot(date, slot, guess);
    });
    try {
      final res = await Api.call('book_meal', {
        'date': date,
        'slot': slot,
        'book': book,
        if (book && note != null) 'note': note,
      });
      if (!mounted) return;
      setState(() => _putSlot(date, slot, _slotFrom(res, slot) ?? guess));
      // Only this booking was on its way: what's on screen is the truth now.
      if (_busy.length == 1) ApiCache.write(_fn, _req, _data!);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _putSlot(date, slot, before));
      if (e.code == 'NOT_MEMBER') return;
      showMsg(context, e.friendly, error: true);
      // Closed / off / timed out (the server may have saved it anyway): ask
      // the server what is true now.
      _reloadWanted = true;
    } finally {
      _busy.remove(key);
      if (mounted) {
        setState(() {});
        _reloadAfterBookings();
      }
    }
  }

  Future<void> _editNote(String date, String slot, String? current) async {
    final text = await askText(
      context,
      title: current == null ? 'Add a note' : 'Your note',
      initial: current ?? '',
      hint: 'e.g. no onion, less spicy',
    );
    if (text == null || !mounted || text == (current ?? '')) return;
    await _book(date, slot, book: true, note: text);
  }

  Future<void> _logout() async {
    final ok = await confirm(
      context,
      title: 'Log out?',
      body: "You'll need your name and PIN to log in on this phone again.",
      yes: 'Log out',
    );
    if (!ok || !mounted) return;
    final name = Device.name;
    await Device.clearLogin();
    ApiCache.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => LoginScreen(name: name)), (_) => false);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final name = Device.name;
    final house = Device.houseName;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? 'Family meals' : 'Hi $name',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            if (house.isNotEmpty)
              Text(
                house,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF6B5446)),
              ),
          ],
        ),
        toolbarHeight: 68,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => v == 'logout' ? _logout() : _load(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('Refresh'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Log out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _data == null
          ? (_error != null
                ? ErrorBox(text: _error!, onRetry: _load)
                : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(onRefresh: _load, child: _list()),
    );
  }

  Widget _list() {
    // A reply saved on an earlier day (e.g. opened offline) must not call
    // yesterday "Today" or show days that are over.
    final serverToday = '${_data!['today'] ?? ''}';
    final phoneToday = istDate();
    final today = serverToday.compareTo(phoneToday) >= 0 ? serverToday : phoneToday;
    final days = [
      for (final d in _days)
        if ('${d['date']}'.compareTo(today) >= 0) d,
    ];
    final sections = <Widget>[
      if (_stale)
        const InfoBanner(
          icon: Icons.wifi_off_rounded,
          color: StatusColors.grey,
          text: "Couldn't refresh. Showing the menu saved on this phone.",
        ),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: Text(
          "Book each meal you'll eat, so the cook knows how many to cook for.",
          style: TextStyle(fontSize: 15, color: Color(0xFF6B5446)),
        ),
      ),
      for (final d in days)
        _DaySection(
          day: d,
          today: today,
          busy: _busy,
          onBook: (slot, book) => _book('${d['date']}', slot, book: book),
          onNote: (slot, current) => _editNote('${d['date']}', slot, current),
        ),
      if (days.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nothing to show yet.', textAlign: TextAlign.center, style: TextStyle(fontSize: 17)),
        ),
    ];
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) => EntryAnimation(index: i, child: sections[i]),
    );
  }
}

// ---------- one day ----------

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.today,
    required this.busy,
    required this.onBook,
    required this.onNote,
  });
  final Map<String, dynamic> day;
  final String today;
  final Set<String> busy;
  final void Function(String slot, bool book) onBook;
  final void Function(String slot, String? current) onNote;

  @override
  Widget build(BuildContext context) {
    final date = '${day['date']}';
    // UTC midnights: a phone abroad in a daylight-saving zone still counts whole days.
    final d = DateTime.tryParse('${date}T00:00:00Z');
    final t = DateTime.tryParse('${today}T00:00:00Z');
    final diff = (d == null || t == null) ? null : d.difference(t).inDays;
    final label = diff == 0
        ? 'Today'
        : diff == 1
        ? 'Tomorrow'
        : d == null
        ? date
        : DateFormat('EEEE').format(d);
    final slots = Map<String, dynamic>.from((day['slots'] as Map?) ?? const {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              if (d != null)
                Text(
                  DateFormat('d MMM').format(d),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF8A6A55)),
                ),
            ],
          ),
        ),
        for (final slot in const ['morning', 'evening'])
          if (slots[slot] is Map)
            Padding(
              padding: EdgeInsets.only(bottom: slot == 'morning' ? 10 : 0),
              child: _SlotCard(
                slot: slot,
                dayLabel: label,
                data: Map<String, dynamic>.from(slots[slot] as Map),
                busy: busy.contains('$date|$slot'),
                onBook: (book) => onBook(slot, book),
                onNote: (current) => onNote(slot, current),
              ),
            ),
      ],
    );
  }
}

// ---------- one meal ----------

const _muted = Color(0xFF6B5446);
const _bookedGreen = Color(0xFF1E7A43);

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.dayLabel,
    required this.data,
    required this.busy,
    required this.onBook,
    required this.onNote,
  });
  final String slot;
  final String dayLabel;
  final Map<String, dynamic> data;
  final bool busy;
  final ValueChanged<bool> onBook;
  final ValueChanged<String?> onNote;

  bool get _morning => slot == 'morning';
  String get _slotName => _morning ? 'Morning' : 'Evening';

  /// Book / cancel allowed: not off, the server says open and the cutoff
  /// (the cook's start time) hasn't passed on this phone's clock either.
  bool get _canChange {
    if (data['off'] != null || data['open'] != true) return false;
    final c = DateTime.tryParse('${data['cutoff'] ?? ''}');
    return c == null || DateTime.now().isBefore(c);
  }

  @override
  Widget build(BuildContext context) {
    final off = data['off'] is Map ? Map<String, dynamic>.from(data['off'] as Map) : null;
    final booked = data['booked'] == true;
    final open = _canChange;
    // "9:00 PM" never splits over two lines (the hint may wrap with large text).
    final until = istTime(data['cutoff'])?.replaceAll(' ', '\u00A0');
    final note = data['note'] is String ? (data['note'] as String).trim() : null;
    final hasNote = note != null && note.isNotEmpty;

    final String? hint = off != null
        ? null
        : open
        ? (until == null
              ? null
              : booked
              ? 'Cancel until $until'
              : 'Book until $until')
        : 'Closed';

    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      opacity: off != null ? 0.55 : 0.74,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Morning ·························· Book until 7:00 AM
          Row(
            children: [
              Icon(
                _morning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                size: 22,
                color: _morning ? const Color(0xFFE0A100) : const Color(0xFF6A5ACD),
              ),
              const SizedBox(width: 8),
              Text(_slotName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              if (busy)
                const Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 6),
                      Text(
                        'Saving…',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _muted),
                      ),
                    ],
                  ),
                )
              else if (hint != null)
                Expanded(
                  child: Text(
                    hint,
                    textAlign: TextAlign.end,
                    // Two lines, so large text shows "Book until" over the
                    // time instead of cutting the time off.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: open ? _muted : StatusColors.grey,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (off != null)
            _OffRow(off: off, slot: slot)
          else ...[
            _Dishes(items: data['items'] is List ? data['items'] as List : const []),
            const SizedBox(height: 10),
            _Eating(
              bookings: data['bookings'] is Map ? data['bookings'] as Map : null,
              title: '$dayLabel · $_slotName',
            ),
            if (booked && (hasNote || (open && !busy))) ...[
              const SizedBox(height: 6),
              _NoteRow(
                note: hasNote ? note : null,
                canEdit: open && !busy,
                onEdit: () => onNote(hasNote ? note : null),
              ),
            ],
            if (open || booked) ...[
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
                ),
                child: booked
                    ? _BookedRow(
                        key: const ValueKey('booked'),
                        canCancel: open,
                        onCancel: busy ? null : () => onBook(false),
                      )
                    : FilledButton.icon(
                        key: const ValueKey('book'),
                        style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                        onPressed: busy ? null : () => onBook(true),
                        icon: const Icon(Icons.restaurant_rounded, size: 22),
                        label: Text('Book ${_slotName.toLowerCase()}'),
                      ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Dishes extends StatelessWidget {
  const _Dishes({required this.items});
  final List items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Row(
        children: [
          Icon(Icons.hourglass_empty_rounded, size: 20, color: StatusColors.grey),
          SizedBox(width: 8),
          Expanded(
            child: Text('Menu not decided yet', style: TextStyle(fontSize: 16, color: _muted)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, raw) in items.indexed)
          if (raw is Map)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: _Dish(item: Map<String, dynamic>.from(raw)),
            ),
      ],
    );
  }
}

class _Dish extends StatelessWidget {
  const _Dish({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = '${item['name'] ?? ''}';
    final yt = item['youtube_url'] is String ? item['youtube_url'] as String : null;
    final notes = [
      for (final n in [item['notes'], item['dish_notes']])
        if (n != null && '$n'.trim().isNotEmpty) '$n'.trim(),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (yt != null && youtubeId(yt) != null) ...[
          VideoThumb(url: yt, title: name, width: 92),
          const SizedBox(width: 12),
        ] else ...[
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.circle, size: 8, color: accent),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.2)),
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(n, style: const TextStyle(fontSize: 14.5, color: _muted)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OffRow extends StatelessWidget {
  const _OffRow({required this.off, required this.slot});
  final Map<String, dynamic> off;
  final String slot;

  @override
  Widget build(BuildContext context) {
    final type = '${off['type']}';
    final (IconData icon, Color color, String text) = switch (type) {
      'holiday' => (Icons.beach_access_rounded, StatusColors.holiday, 'Holiday'),
      'leave' => (Icons.event_busy_rounded, StatusColors.leave, 'Cook on leave'),
      _ => (
        Icons.remove_circle_outline_rounded,
        StatusColors.grey,
        slot == 'evening' ? 'No evening meal on weekends' : 'No meal this time',
      ),
    };
    // Only holiday notes are shown (e.g. "Diwali"); the cook's leave reason stays private.
    final note = type == 'holiday' && off['note'] is String ? (off['note'] as String).trim() : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                if (note != null && note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 14.5, color: _muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "4 eating: Rahul, Priya, Amma, Dhruva" – tap for everyone's notes.
class _Eating extends StatelessWidget {
  const _Eating({required this.bookings, required this.title});
  final Map? bookings;
  final String title;

  List<Map<String, dynamic>> get _people => [
    for (final p in (bookings?['people'] is List ? bookings!['people'] as List : const []))
      if (p is Map) Map<String, dynamic>.from(p),
  ];

  void _sheet(BuildContext context) {
    final people = _people;
    final me = Device.name.trim().toLowerCase();
    // Tall enough for a whole family with notes; the title stays put while
    // the list scrolls.
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '${people.length} eating · $title',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  for (final p in people)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: tint,
                        foregroundColor: espresso,
                        child: Text(_initial('${p['name']}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      title: Text(
                        '${p['name']}${'${p['name']}'.trim().toLowerCase() == me ? ' (you)' : ''}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      subtitle: (p['note'] is String && (p['note'] as String).trim().isNotEmpty)
                          ? Text('${p['note']}', style: const TextStyle(fontSize: 15))
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initial(String name) => name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final count = bookings?['count'] is num ? (bookings!['count'] as num).toInt() : people.length;
    final names = people.map((p) => '${p['name']}').join(', ');
    final text = count == 0
        ? 'No one has booked yet'
        : names.isEmpty
        ? '$count eating'
        : '$count eating: $names';
    final row = Row(
      children: [
        Icon(Icons.groups_rounded, size: 22, color: count == 0 ? StatusColors.grey : accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: count == 0 ? _muted : espresso),
          ),
        ),
        if (people.isNotEmpty) const Icon(Icons.chevron_right_rounded, color: StatusColors.grey),
      ],
    );
    if (people.isEmpty) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _sheet(context),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.canEdit, required this.onEdit});
  final String? note;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    if (note == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(44, 40),
          ),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_note_rounded, size: 22),
          label: const Text('Add a note', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: canEdit ? onEdit : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.sticky_note_2_outlined, size: 20, color: _muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Your note: ',
                      style: TextStyle(color: _muted),
                    ),
                    TextSpan(
                      text: note,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 15.5),
              ),
            ),
            if (canEdit) const Icon(Icons.edit_rounded, size: 18, color: StatusColors.grey),
          ],
        ),
      ),
    );
  }
}

/// Green "Booked ✓" with a Cancel button while booking is open.
class _BookedRow extends StatelessWidget {
  const _BookedRow({super.key, required this.canCancel, required this.onCancel});
  final bool canCancel;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: StatusColors.done.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StatusColors.done.withValues(alpha: 0.55)),
      ),
      child: const Text(
        'Booked ✓',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _bookedGreen),
      ),
    );
    if (!canCancel) return pill;
    return Row(
      children: [
        Expanded(child: pill),
        const SizedBox(width: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(104, 52)),
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
