import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../widgets/common.dart';
import '../holidays/holidays_screen.dart';

/// Tap a calendar day → scan times, distance, online/offline, amount, menu,
/// holiday/leave details, and manual add/remove.
Future<void> showDaySheet(BuildContext context, Map<String, dynamic> day, Map<String, dynamic> month) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (c, scroll) => _DaySheet(day: day, frozen: month['frozen'] == true, scroll: scroll),
    ),
  );
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.day, required this.frozen, required this.scroll});
  final Map<String, dynamic> day;
  final bool frozen;
  final ScrollController scroll;

  Future<void> _add(BuildContext context, String slot) async {
    final note = await askText(context, 'Add ${slotLabel(slot).toLowerCase()} entry', hint: 'Note (e.g. forgot her phone)', ok: 'Add');
    if (note == null || !context.mounted) return;
    final r = await busy(context, () => Api.call('owner_edit_attendance', {
          'action': 'add',
          'date': day['date'],
          'slot': slot,
          'note': note,
        }), success: 'Entry added (manual)');
    if (r != null && context.mounted) {
      AppState.i.changed();
      Navigator.pop(context);
    }
  }

  Future<void> _remove(BuildContext context, Map att, String slot) async {
    final note = await askText(context, 'Remove ${slotLabel(slot).toLowerCase()} entry?',
        hint: 'Why? (e.g. scanned by mistake)', ok: 'Remove');
    if (note == null || !context.mounted) return;
    final r = await busy(context, () => Api.call('owner_edit_attendance', {
          'action': 'remove',
          'id': att['id'],
          'note': note,
        }), success: 'Entry removed. You can restore it from History.');
    if (r != null && context.mounted) {
      AppState.i.changed();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = '${day['date']}';
    final isPastOrToday = date.compareTo(ymd(istToday())) <= 0;
    final slots = day['slots'] as Map;
    final menu = day['menu'] as Map;
    final tt = Theme.of(context).textTheme;

    Widget slotCard(String slot) {
      final info = Map<String, dynamic>.from(slots[slot]);
      final state = '${info['state']}';
      final att = info['attendance'] as Map?;
      final h = info['holiday'] as Map?;
      final l = info['leave'] as Map?;
      final lines = <(IconData, String)>[];
      if (att != null) {
        lines.add((Icons.access_time_rounded, 'Scanned ${istTime(att['scanned_at'])}'));
        if (att['is_offline'] == true) {
          lines.add((Icons.cloud_off_rounded, 'Offline scan · uploaded ${istDateTime(att['uploaded_at'])}'));
        } else if (att['is_manual'] == true) {
          lines.add((Icons.edit_note_rounded, 'Manual entry by owner'));
        } else {
          lines.add((Icons.cloud_done_rounded, 'Online scan'));
        }
        if (att['distance_m'] != null) lines.add((Icons.place_outlined, '${att['distance_m']} m from house'));
        if ((att['note'] ?? '').toString().isNotEmpty) lines.add((Icons.notes_rounded, '${att['note']}'));
      }
      if (h != null) {
        lines.add((Icons.beach_access_rounded,
            'Holiday (${h['paid'] == true ? 'paid' : 'unpaid'})${(h['note'] ?? '').toString().isNotEmpty ? ' – ${h['note']}' : ''}'));
      }
      if (l != null) {
        lines.add((Icons.event_busy_rounded,
            'Leave: ${'${l['status']}'.replaceAll('_', ' ')}${(l['reason'] ?? '').toString().isNotEmpty ? ' – ${l['reason']}' : ''}'));
      }
      final amount = (info['amount'] as num?) ?? 0;

      return SectionCard(
        title: slotLabel(slot),
        trailing: StatusPill(state, dense: true),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, t) in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [Icon(i, size: 18), const SizedBox(width: 8), Expanded(child: Text(t))]),
            ),
          if (state != 'not_needed' && state != 'none')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Amount: ${rupees(amount)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (!frozen && att != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _remove(context, att, slot),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove entry'),
              ),
            ),
          if (!frozen && att == null && isPastOrToday && state != 'not_needed')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _add(context, slot),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add entry manually'),
              ),
            ),
        ]),
      );
    }

    String dishes(List l) => l.isEmpty ? '—' : l.map((e) => e['name']).join(', ');

    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Text(longDate(date), style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      Row(children: [
        Text(DayStyle.label('${day['status']}')),
        const Spacer(),
        Text(rupees(day['amount']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ]),
      if (frozen)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('This month is paid and frozen – entries cannot be changed.',
              style: TextStyle(fontStyle: FontStyle.italic)),
        ),
      const SizedBox(height: 12),
      slotCard('morning'),
      const SizedBox(height: 10),
      slotCard('evening'),
      const SizedBox(height: 10),
      SectionCard(
        title: 'Menu',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Morning: ${dishes(menu['morning'] as List)}'),
          const SizedBox(height: 4),
          Text('Evening: ${dishes(menu['evening'] as List)}'),
        ]),
      ),
      if (!frozen && date.compareTo(ymd(istToday())) >= 0) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final nav = Navigator.of(context);
            nav.pop();
            await showAddHoliday(nav.context, initial: parseYmd(date));
          },
          icon: const Icon(Icons.beach_access_rounded),
          label: const Text('Set holiday on this day'),
        ),
      ],
    ]);
  }
}
