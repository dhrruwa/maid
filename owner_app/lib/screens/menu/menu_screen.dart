import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/video.dart';
import 'copy_menu_sheet.dart';
import 'dish_sheet.dart';
import 'dishes_screen.dart';

/// Plan dishes per date and slot (reference: MacroFactor recipe library, Lifesum add-to-recipe).
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  DateTime _date = istToday();
  String _slot = istNow().hour < 12 ? 'morning' : 'evening';
  Map<String, dynamic>? _menu;

  /// The date [_menu] belongs to (it can still be the previous day's while loading).
  String? _menuDate;
  Object? _error;
  int _loading = 0;
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
    if (AppState.i.version != _seenVersion) _load();
  }

  Future<void> _load() async {
    _seenVersion = AppState.i.version;
    final date = ymd(_date);
    // Show the saved copy of this day at once, then refresh it.
    if (_menuDate != date) {
      _error = null;
      final c = Api.cached('get_menu', body: {'date': date});
      if (c != null) {
        _menu = c;
        _menuDate = date;
      }
    }
    setState(() => _loading++);
    try {
      final r = await Api.read('get_menu', body: {'date': date});
      // Ignore a reply for a day that is no longer selected.
      if (mounted && date == ymd(_date)) {
        setState(() {
          _menu = r;
          _menuDate = date;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && date == ymd(_date)) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading--);
  }

  List<Map<String, dynamic>> get _items =>
      ((_menu?[_slot]?['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

  Map? get _off => _menu?[_slot]?['off'] as Map?;

  Future<void> _save(List<Map<String, dynamic>> items, {String? success}) async {
    // The list on screen is still another day's: never write it to this day.
    if (_menuDate != ymd(_date)) return;
    final r = await busy(
      context,
      () => Api.call('set_menu', {
        'date': ymd(_date),
        'slot': _slot,
        'items': items.map((i) => {'dish_id': i['dish_id'], 'notes': i['notes']}).toList(),
      }),
      success: success,
    );
    // Reloads this screen (and the others) through the AppState listener.
    if (r != null) AppState.i.changed();
  }

  Future<void> _add() async {
    final picked = await showDishPicker(context);
    if (picked == null) return;
    await _save([..._items, picked], success: 'Added ${picked['name']}');
  }

  Future<void> _remove(int i) async {
    final items = [..._items]..removeAt(i);
    await _save(items, success: 'Removed');
  }

  Future<void> _editNotes(int i) async {
    final n = await askText(context, 'Notes for this meal', hint: 'e.g. Less spicy, make for 4 people',
        initial: '${_items[i]['notes'] ?? ''}');
    if (n == null) return;
    final items = [..._items];
    items[i] = {...items[i], 'notes': n.isEmpty ? null : n};
    await _save(items, success: 'Notes saved');
  }

  @override
  Widget build(BuildContext context) {
    final today = istToday();
    final days = List.generate(21, (i) => today.add(Duration(days: i - 3)));
    final off = _off;

    return Column(children: [
      SizedBox(
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: days.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (c, i) {
            if (i == days.length) {
              return _DayChip(
                top: 'More',
                bottom: '',
                icon: Icons.calendar_month_rounded,
                selected: false,
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(today.year - 2),
                    lastDate: DateTime(today.year + 1, 12, 31),
                  );
                  if (d != null) {
                    setState(() => _date = d);
                    _load();
                  }
                },
              );
            }
            final d = days[i];
            return _DayChip(
              top: d == today ? 'Today' : DateFormat('EEE').format(d),
              bottom: '${d.day}',
              selected: d == _date,
              onTap: () {
                setState(() => _date = d);
                _load();
              },
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(children: [
          Expanded(
            child: Text(longDate(ymd(_date)),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Copy menu',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () async {
              if (await showCopyMenu(context, _date)) _load();
            },
          ),
          IconButton(
            tooltip: 'My dishes',
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DishesScreen())),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'morning', label: Text('Morning'), icon: Icon(Icons.wb_sunny_outlined)),
              ButtonSegment(value: 'evening', label: Text('Evening'), icon: Icon(Icons.nights_stay_outlined)),
            ],
            selected: {_slot},
            onSelectionChanged: (s) => setState(() => _slot = s.first),
          ),
        ),
      ),
      if (_loading > 0 && _menuDate != ymd(_date)) const LinearProgressIndicator(),
      Expanded(
        // Never show another day's dishes under this day's date while it loads.
        child: _menu == null || _menuDate != ymd(_date)
            ? (_error != null ? ErrorRetry(error: _error!, onRetry: _load) : const SizedBox())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom), children: [
                  if (_error != null) StaleNote(error: _error!, onRetry: _load),
                  if (off != null)
                    _OffBanner(off: off)
                  else if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Column(children: [
                        Icon(Icons.restaurant_rounded, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No dishes planned yet'),
                      ]),
                    ),
                  for (var i = 0; i < _items.length; i++)
                    Padding(
                      key: ValueKey(_items[i]['menu_id']),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: EntryAnimation(index: i, child: _DishCard(
                        item: _items[i],
                        onRemove: () => _remove(i),
                        onNotes: () => _editNotes(i),
                      )),
                    ),
                  if (off == null)
                    FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add dish')),
                ]),
              ),
      ),
    ]);
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.top, required this.bottom, required this.selected, required this.onTap, this.icon});
  final String top;
  final String bottom;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 58,
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(top, style: TextStyle(fontSize: 12, color: selected ? scheme.onPrimary : null)),
          const SizedBox(height: 2),
          icon != null
              ? Icon(icon, color: selected ? scheme.onPrimary : null)
              : Text(bottom,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: selected ? scheme.onPrimary : null)),
        ]),
      ),
    );
  }
}

class _OffBanner extends StatelessWidget {
  const _OffBanner({required this.off});
  final Map off;

  @override
  Widget build(BuildContext context) {
    final type = '${off['type']}';
    final (icon, color, text) = switch (type) {
      'holiday' => (Icons.beach_access_rounded, StatusColors.holiday, 'Holiday – no cooking needed'),
      'leave' => (Icons.event_busy_rounded, StatusColors.leave, 'Cook is on leave'),
      _ => (Icons.remove_circle_outline_rounded, StatusColors.future, 'No evening visit on Saturday/Sunday'),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            [text, if ((off['note'] ?? '').toString().isNotEmpty) '${off['note']}'].join('\n'),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _DishCard extends StatelessWidget {
  const _DishCard({required this.item, required this.onRemove, required this.onNotes});
  final Map<String, dynamic> item;
  final VoidCallback onRemove;
  final VoidCallback onNotes;

  @override
  Widget build(BuildContext context) {
    final yt = item['youtube_url'] as String?;
    final notes = [item['notes'], item['dish_notes']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        if (yt != null) ...[YoutubeThumb(url: yt), const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (notes.isNotEmpty) Text(notes, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        PopupMenuButton<String>(
          onSelected: (v) => v == 'notes' ? onNotes() : onRemove(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'notes', child: Text('Edit notes')),
            PopupMenuItem(value: 'remove', child: Text('Remove from menu')),
          ],
        ),
      ]),
    );
  }
}
