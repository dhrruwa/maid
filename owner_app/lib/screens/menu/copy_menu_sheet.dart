import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../widgets/common.dart';

/// Copy a day's menu to other days, or repeat it weekly.
Future<bool> showCopyMenu(BuildContext context, DateTime from) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CopySheet(from: from),
  );
  return r ?? false;
}

class _CopySheet extends StatefulWidget {
  const _CopySheet({required this.from});
  final DateTime from;

  @override
  State<_CopySheet> createState() => _CopySheetState();
}

class _CopySheetState extends State<_CopySheet> {
  bool _weekly = false;
  int _weeks = 4;
  final _dates = <DateTime>{};
  Set<String> _slots = {'morning', 'evening'};

  Future<void> _addDate() async {
    final t = istToday();
    final d = await showDatePicker(
      context: context,
      initialDate: widget.from.add(const Duration(days: 1)),
      firstDate: DateTime(t.year - 1),
      lastDate: DateTime(t.year + 1, 12, 31),
    );
    if (d != null && d != widget.from) setState(() => _dates.add(d));
  }

  Future<void> _copy() async {
    final r = await busy(context, () => Api.call('copy_menu', {
          'from_date': ymd(widget.from),
          if (_weekly) 'repeat_weeks': _weeks else 'to_dates': _dates.map(ymd).toList(),
          'slots': _slots.toList(),
        }));
    if (r == null || !mounted) return;
    final copied = (r['copied'] as List).length;
    final skipped = (r['skipped'] as List).length;
    toast(context, 'Copied to $copied meal(s)${skipped > 0 ? ', skipped $skipped holiday/leave meal(s)' : ''}');
    AppState.i.changed();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _dates.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Copy menu of ${longDate(ymd(widget.from))}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Pick days'), icon: Icon(Icons.event_rounded)),
            ButtonSegment(value: true, label: Text('Repeat weekly'), icon: Icon(Icons.repeat_rounded)),
          ],
          selected: {_weekly},
          onSelectionChanged: (s) => setState(() => _weekly = s.first),
        ),
        const SizedBox(height: 16),
        if (!_weekly)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in sorted)
              InputChip(label: Text(shortDate(ymd(d))), onDeleted: () => setState(() => _dates.remove(d))),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add day'), onPressed: _addDate),
          ])
        else
          Row(children: [
            const Expanded(child: Text('Same weekday for the next')),
            IconButton(onPressed: _weeks > 1 ? () => setState(() => _weeks--) : null, icon: const Icon(Icons.remove)),
            Text('$_weeks', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            IconButton(onPressed: _weeks < 12 ? () => setState(() => _weeks++) : null, icon: const Icon(Icons.add)),
            const Text('weeks'),
          ]),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          multiSelectionEnabled: true,
          emptySelectionAllowed: false,
          segments: const [
            ButtonSegment(value: 'morning', label: Text('Morning')),
            ButtonSegment(value: 'evening', label: Text('Evening')),
          ],
          selected: _slots,
          onSelectionChanged: (s) => setState(() => _slots = s),
        ),
        const SizedBox(height: 8),
        const Text('Holidays, leave days and weekend evenings are skipped automatically.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 16),
        FilledButton(onPressed: !_weekly && _dates.isEmpty ? null : _copy, child: const Text('Copy')),
      ]),
    );
  }
}
