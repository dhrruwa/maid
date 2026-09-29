import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/theme.dart';
import 'common.dart';
import 'motion.dart';

/// The last 7 days as a timeline: each visit is a dot at its scan time, and a
/// missed visit shows as a red hatched gap across its time window.
class WeekTimeline extends StatefulWidget {
  const WeekTimeline({super.key});

  @override
  State<WeekTimeline> createState() => _WeekTimelineState();
}

class _WeekTimelineState extends State<WeekTimeline> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  Object? _error;
  int _seenVersion = -1;
  (String, String)? _pulseAt; // (date, slot) of a scan from the last 30 minutes
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    AppState.i.addListener(_onState);
    _load();
  }

  @override
  void dispose() {
    AppState.i.removeListener(_onState);
    _pulse.dispose();
    super.dispose();
  }

  void _onState() {
    if (AppState.i.version != _seenVersion) _load();
  }

  Future<void> _load() async {
    _seenVersion = AppState.i.version;
    final today = istToday();
    try {
      final r = await Api.call('get_timeline', {
        'from': ymd(today.subtract(const Duration(days: 6))),
        'to': ymd(today),
      });
      if (!mounted) return;
      setState(() {
        _data = r;
        _error = null;
        _pulseAt = _recentScan(r);
      });
      if (_pulseAt != null && !MediaQuery.of(context).disableAnimations) {
        _pulse.repeat();
        Future.delayed(const Duration(milliseconds: 4200), () => mounted ? _pulse.stop() : null);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  (String, String)? _recentScan(Map<String, dynamic> r) {
    final now = DateTime.now().toUtc();
    for (final d in (r['days'] as List).reversed) {
      for (final slot in ['evening', 'morning']) {
        final at = d['slots'][slot]['scanned_at'];
        if (at is String && now.difference(DateTime.parse(at)).inMinutes.abs() <= 30) return ('${d['date']}', slot);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return SectionCard(
        title: 'This week',
        child: _error != null
            ? Text('Could not load the timeline. Pull down to retry.', style: Theme.of(context).textTheme.bodySmall)
            : const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
      );
    }
    final win = TimelineWindows.from(Map<String, dynamic>.from(d['windows']));
    final days = (d['days'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
    final missed = d['missed'] as int;
    final today = '${d['today']}';
    final nowMin = _istMinutes(DateTime.now().toUtc().toIso8601String());
    final text = Theme.of(context).colorScheme.onSurface;

    return SectionCard(
      title: 'This week',
      trailing: _GapChip(missed: missed),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _AxisHeader(win: win, color: text),
        const SizedBox(height: 2),
        for (var i = 0; i < days.length; i++)
          EntryAnimation(
            index: i,
            child: _DayRow(
              day: days[i],
              win: win,
              isToday: days[i]['date'] == today,
              nowMin: nowMin,
              pulseSlot: _pulseAt?.$1 == days[i]['date'] ? _pulseAt!.$2 : null,
              pulse: _pulse,
              textColor: text,
            ),
          ),
        const SizedBox(height: 10),
        const TimelineLegend(),
      ]),
    );
  }
}

class _GapChip extends StatelessWidget {
  const _GapChip({required this.missed});
  final int missed;

  @override
  Widget build(BuildContext context) {
    final bad = missed > 0;
    final c = bad ? StatusColors.missed : StatusColors.done;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(bad ? Icons.report_gmailerrorred_rounded : Icons.verified_rounded, size: 16, color: c),
        const SizedBox(width: 4),
        Text(bad ? '$missed missed' : 'No gaps', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]),
    );
  }
}

/// Slot windows in minutes since midnight, plus the axis range.
class TimelineWindows {
  TimelineWindows(this.ms, this.me, this.es, this.ee)
      : start = ms < es ? ms : es,
        end = me > ee ? me : ee;
  final int ms, me, es, ee, start, end;

  static int _m(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  factory TimelineWindows.from(Map<String, dynamic> w) => TimelineWindows(
        _m('${w['morning_start']}'),
        _m('${w['morning_end']}'),
        _m('${w['evening_start']}'),
        _m('${w['evening_end']}'),
      );

  double x(double width, int minute) => (minute - start) / (end - start) * width;
}

int _istMinutes(String iso) {
  final t = DateTime.parse(iso).toUtc().add(const Duration(hours: 5, minutes: 30));
  return t.hour * 60 + t.minute;
}

String _hourLabel(int minute) => DateFormat('h a').format(DateTime(2000, 1, 1, minute ~/ 60, minute % 60));

const _labelWidth = 46.0;

class _AxisHeader extends StatelessWidget {
  const _AxisHeader({required this.win, required this.color});
  final TimelineWindows win;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const SizedBox(width: _labelWidth),
      Expanded(
        child: SizedBox(
          height: 16,
          child: CustomPaint(painter: _AxisPainter(win: win, color: color.withValues(alpha: 0.6))),
        ),
      ),
    ]);
  }
}

class _AxisPainter extends CustomPainter {
  _AxisPainter({required this.win, required this.color});
  final TimelineWindows win;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in [win.ms, win.me, win.es, win.ee]) {
      final tp = TextPainter(
        text: TextSpan(text: _hourLabel(m), style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = win.x(size.width, m) - tp.width / 2;
      tp.paint(canvas, Offset(x.clamp(0, size.width - tp.width), 0));
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) => false;
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.win,
    required this.isToday,
    required this.nowMin,
    required this.pulseSlot,
    required this.pulse,
    required this.textColor,
  });
  final Map<String, dynamic> day;
  final TimelineWindows win;
  final bool isToday;
  final int nowMin;
  final String? pulseSlot;
  final Animation<double> pulse;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse('${day['date']}');
    return Row(children: [
      SizedBox(
        width: _labelWidth,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isToday ? 'Today' : DateFormat('EEE').format(date),
              style: TextStyle(fontSize: 12, fontWeight: isToday ? FontWeight.w800 : FontWeight.w600, color: isToday ? ink : textColor)),
          Text(DateFormat('d MMM').format(date), style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.6))),
        ]),
      ),
      Expanded(
        child: SizedBox(
          height: 40,
          child: CustomPaint(
            painter: TimelineDayPainter(
              slots: Map<String, dynamic>.from(day['slots']),
              win: win,
              nowMin: isToday ? nowMin : null,
              pulseSlot: pulseSlot,
              pulse: pulse,
              textColor: textColor,
              missedLabel: 'Missed',
              holidayLabel: 'Holiday',
              leaveLabel: 'Leave',
              timeFormat: DateFormat('h:mm'),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Draws one day: time windows as tracks, scans as dots, misses as hatched gaps.
class TimelineDayPainter extends CustomPainter {
  TimelineDayPainter({
    required this.slots,
    required this.win,
    required this.nowMin,
    required this.pulseSlot,
    required this.pulse,
    required this.textColor,
    required this.missedLabel,
    required this.holidayLabel,
    required this.leaveLabel,
    required this.timeFormat,
  }) : super(repaint: pulse);

  final Map<String, dynamic> slots;
  final TimelineWindows win;
  final int? nowMin;
  final String? pulseSlot;
  final Animation<double> pulse;
  final Color textColor;
  final String missedLabel, holidayLabel, leaveLabel;
  final DateFormat timeFormat;

  static const _trackH = 12.0;

  void _label(Canvas c, String text, Offset center, Color color, {double top = 0}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(center.dx - tp.width / 2, top));
  }

  void _dashed(Canvas c, RRect rr, Paint p) {
    final path = Path()..addRRect(rr);
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 7) {
        c.drawPath(m.extractPath(d, (d + 4).clamp(0, m.length)), p);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height * 0.66;
    for (final slot in const ['morning', 'evening']) {
      final info = Map<String, dynamic>.from(slots[slot] as Map);
      final state = '${info['state']}';
      final a = slot == 'morning' ? win.ms : win.es;
      final b = slot == 'morning' ? win.me : win.ee;
      final rect = Rect.fromLTRB(win.x(size.width, a), cy - _trackH / 2, win.x(size.width, b), cy + _trackH / 2);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(_trackH / 2));

      switch (state) {
        case 'done':
          canvas.drawRRect(rr, Paint()..color = StatusColors.done.withValues(alpha: 0.22));
        case 'missed':
          canvas.drawRRect(rr, Paint()..color = StatusColors.missed.withValues(alpha: 0.10));
          canvas.save();
          canvas.clipRRect(rr);
          final hatch = Paint()
            ..color = StatusColors.missed.withValues(alpha: 0.55)
            ..strokeWidth = 1.2;
          for (double i = rect.left - rect.height; i < rect.right; i += 5) {
            canvas.drawLine(Offset(i, rect.bottom), Offset(i + rect.height, rect.top), hatch);
          }
          canvas.restore();
          _dashed(canvas, rr, Paint()
            ..color = StatusColors.missed
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
          _label(canvas, missedLabel, rect.center, StatusColors.missed, top: 1);
        case 'pending':
          canvas.drawRRect(rr, Paint()..color = StatusColors.partial.withValues(alpha: 0.12));
          canvas.drawRRect(rr, Paint()
            ..color = StatusColors.partial
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
        case 'upcoming':
          canvas.drawRRect(rr, Paint()
            ..color = textColor.withValues(alpha: 0.28)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
        case 'holiday_paid':
        case 'holiday_unpaid':
          canvas.drawRRect(rr, Paint()..color = StatusColors.holiday.withValues(alpha: 0.30));
          _label(canvas, holidayLabel, rect.center, StatusColors.holiday, top: 1);
        case 'leave_paid':
        case 'leave_unpaid':
          canvas.drawRRect(rr, Paint()..color = StatusColors.leave.withValues(alpha: 0.30));
          _label(canvas, leaveLabel, rect.center, StatusColors.leave, top: 1);
        case 'not_needed':
          final dot = Paint()..color = textColor.withValues(alpha: 0.25);
          for (double x = rect.left + 3; x < rect.right; x += 6) {
            canvas.drawCircle(Offset(x, cy), 1.2, dot);
          }
      }

      final at = info['scanned_at'];
      if (state == 'done' && at is String) {
        final px = win.x(size.width, _istMinutes(at)).clamp(rect.left + 6, rect.right - 6).toDouble();
        final center = Offset(px, cy);
        if (pulseSlot == slot) {
          final t = pulse.value;
          canvas.drawCircle(center, 6 + 12 * t, Paint()
            ..color = StatusColors.done.withValues(alpha: (1 - t) * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
        }
        final white = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        final fill = Paint()..color = StatusColors.done;
        if (info['is_manual'] == true) {
          final sq = Rect.fromCenter(center: center, width: 11, height: 11);
          canvas.drawRRect(RRect.fromRectAndRadius(sq, const Radius.circular(2.5)), fill);
          canvas.drawRRect(RRect.fromRectAndRadius(sq, const Radius.circular(2.5)), white);
        } else {
          canvas.drawCircle(center, 6, fill);
          canvas.drawCircle(center, 6, white);
          if (info['is_offline'] == true) canvas.drawCircle(center, 2.2, Paint()..color = Colors.white);
        }
        final t = DateTime.parse(at).toUtc().add(const Duration(hours: 5, minutes: 30));
        _label(canvas, timeFormat.format(t), center, textColor.withValues(alpha: 0.8), top: 0);
      }
    }

    final n = nowMin;
    if (n != null && n >= win.start && n <= win.end) {
      final x = win.x(size.width, n);
      final p = Paint()
        ..color = accent
        ..strokeWidth = 1.6;
      canvas.drawLine(Offset(x, 13), Offset(x, size.height - 2), p);
      canvas.drawCircle(Offset(x, 13), 2.6, p);
    }
  }

  @override
  bool shouldRepaint(TimelineDayPainter old) =>
      old.slots != slots || old.nowMin != nowMin || old.pulseSlot != pulseSlot || old.textColor != textColor;
}

class TimelineLegend extends StatelessWidget {
  const TimelineLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72);
    Widget item(Widget mark, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          mark,
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, color: text)),
        ]);
    Widget box(Color c, {bool hatched = false}) => Container(
          width: 16,
          height: 9,
          decoration: BoxDecoration(
            color: c.withValues(alpha: hatched ? 0.18 : 0.3),
            borderRadius: BorderRadius.circular(4),
            border: hatched ? Border.all(color: c, width: 1) : null,
          ),
        );
    return Wrap(spacing: 12, runSpacing: 6, children: [
      item(Container(width: 10, height: 10, decoration: const BoxDecoration(color: StatusColors.done, shape: BoxShape.circle)), 'Scan'),
      item(Container(width: 10, height: 10, decoration: BoxDecoration(color: StatusColors.done, borderRadius: BorderRadius.circular(2))), 'Manual'),
      item(box(StatusColors.missed, hatched: true), 'Missed (gap)'),
      item(box(StatusColors.holiday), 'Holiday'),
      item(box(StatusColors.leave), 'Leave'),
      item(Container(width: 2, height: 12, color: accent), 'Now'),
    ]);
  }
}
