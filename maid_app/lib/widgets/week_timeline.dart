import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import 'glass.dart';
import 'motion.dart';

/// The last 7 days as a timeline: each visit is a dot at its scan time, and a
/// missed visit shows as a red hatched gap across its time window.
/// [pulseDate]/[pulseSlot] make one dot pulse (the scan just logged).
class WeekTimeline extends StatefulWidget {
  const WeekTimeline({super.key, this.pulseDate, this.pulseSlot, this.opacity = 0.72});
  final String? pulseDate;
  final String? pulseSlot;

  /// Glass opacity; higher on coloured backgrounds (result screen).
  final double opacity;

  @override
  State<WeekTimeline> createState() => _WeekTimelineState();
}

class _WeekTimelineState extends State<WeekTimeline> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _failed = false;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.call('get_timeline', {'from': istDate(-6), 'to': istDate()});
      if (!mounted) return;
      setState(() => _data = r);
      if (widget.pulseSlot != null && !MediaQuery.of(context).disableAnimations) {
        _pulse.repeat();
        Future.delayed(const Duration(milliseconds: 4200), () => mounted ? _pulse.stop() : null);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return Glass(
        opacity: widget.opacity,
        child: _failed
            ? Text(L.t('timeline_error'), style: const TextStyle(fontSize: 15))
            : const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
      );
    }
    final win = TimelineWindows.from(Map<String, dynamic>.from(d['windows']));
    final days = (d['days'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
    final missed = d['missed'] as int;
    final today = '${d['today']}';
    final nowMin = _istMinutes(DateTime.now().toUtc().toIso8601String());

    return Glass(
      opacity: widget.opacity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.timeline_rounded, color: accent, size: 26),
          const SizedBox(width: 8),
          Expanded(child: Text(L.t('this_week'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          _GapChip(missed: missed),
        ]),
        const SizedBox(height: 10),
        _AxisHeader(win: win),
        for (var i = 0; i < days.length; i++)
          EntryAnimation(
            index: i,
            child: _DayRow(
              day: days[i],
              win: win,
              isToday: days[i]['date'] == today,
              nowMin: nowMin,
              pulseSlot: days[i]['date'] == (widget.pulseDate ?? today) ? widget.pulseSlot : null,
              pulse: _pulse,
            ),
          ),
        const SizedBox(height: 10),
        const _Legend(),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(bad ? Icons.report_gmailerrorred_rounded : Icons.verified_rounded, size: 18, color: c),
        const SizedBox(width: 4),
        Text(bad ? L.t('missed_n', {'count': missed}) : L.t('no_gaps'),
            style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 14)),
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

const _labelWidth = 52.0;

class _AxisHeader extends StatelessWidget {
  const _AxisHeader({required this.win});
  final TimelineWindows win;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const SizedBox(width: _labelWidth),
      Expanded(child: SizedBox(height: 18, child: CustomPaint(painter: _AxisPainter(win, L.code)))),
    ]);
  }
}

class _AxisPainter extends CustomPainter {
  _AxisPainter(this.win, this.lang);
  final TimelineWindows win;
  final String lang;

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in [win.ms, win.me, win.es, win.ee]) {
      final label = DateFormat('h a', lang).format(DateTime(2000, 1, 1, m ~/ 60, m % 60));
      final tp = TextPainter(
        text: TextSpan(
            text: label, style: TextStyle(fontSize: 11, color: espresso.withValues(alpha: 0.6), fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = win.x(size.width, m) - tp.width / 2;
      tp.paint(canvas, Offset(x.clamp(0, size.width - tp.width), 0));
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) => old.lang != lang;
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.win,
    required this.isToday,
    required this.nowMin,
    required this.pulseSlot,
    required this.pulse,
  });
  final Map<String, dynamic> day;
  final TimelineWindows win;
  final bool isToday;
  final int nowMin;
  final String? pulseSlot;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse('${day['date']}');
    return Row(children: [
      SizedBox(
        width: _labelWidth,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isToday ? L.t('today') : DateFormat('EEE', L.code).format(date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isToday ? const Color(0xFF9A4A12) : espresso)),
          Text(DateFormat('d MMM', L.code).format(date),
              maxLines: 1, style: TextStyle(fontSize: 11, color: espresso.withValues(alpha: 0.6))),
        ]),
      ),
      Expanded(
        child: SizedBox(
          height: 42,
          child: CustomPaint(
            painter: _DayPainter(
              slots: Map<String, dynamic>.from(day['slots']),
              win: win,
              nowMin: isToday ? nowMin : null,
              pulseSlot: pulseSlot,
              pulse: pulse,
              missed: L.t('st_missed'),
              holiday: L.t('st_holiday_short'),
              leave: L.t('st_leave_short'),
              lang: L.code,
            ),
          ),
        ),
      ),
    ]);
  }
}

class _DayPainter extends CustomPainter {
  _DayPainter({
    required this.slots,
    required this.win,
    required this.nowMin,
    required this.pulseSlot,
    required this.pulse,
    required this.missed,
    required this.holiday,
    required this.leave,
    required this.lang,
  }) : super(repaint: pulse);

  final Map<String, dynamic> slots;
  final TimelineWindows win;
  final int? nowMin;
  final String? pulseSlot;
  final Animation<double> pulse;
  final String missed, holiday, leave, lang;

  static const _h = 13.0;

  void _label(Canvas c, String text, double cx, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(cx - tp.width / 2, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height * 0.68;
    for (final slot in const ['morning', 'evening']) {
      final info = Map<String, dynamic>.from(slots[slot] as Map);
      final state = '${info['state']}';
      final a = slot == 'morning' ? win.ms : win.es;
      final b = slot == 'morning' ? win.me : win.ee;
      final rect = Rect.fromLTRB(win.x(size.width, a), cy - _h / 2, win.x(size.width, b), cy + _h / 2);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(_h / 2));

      switch (state) {
        case 'done':
          canvas.drawRRect(rr, Paint()..color = StatusColors.done.withValues(alpha: 0.22));
        case 'missed':
          canvas.drawRRect(rr, Paint()..color = StatusColors.missed.withValues(alpha: 0.10));
          canvas.save();
          canvas.clipRRect(rr);
          final hatch = Paint()
            ..color = StatusColors.missed.withValues(alpha: 0.6)
            ..strokeWidth = 1.3;
          for (double i = rect.left - rect.height; i < rect.right; i += 5) {
            canvas.drawLine(Offset(i, rect.bottom), Offset(i + rect.height, rect.top), hatch);
          }
          canvas.restore();
          canvas.drawRRect(rr, Paint()
            ..color = StatusColors.missed
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3);
          _label(canvas, missed, rect.center.dx, StatusColors.missed);
        case 'pending':
          canvas.drawRRect(rr, Paint()..color = StatusColors.wait.withValues(alpha: 0.14));
          canvas.drawRRect(rr, Paint()
            ..color = StatusColors.wait
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
        case 'upcoming':
          canvas.drawRRect(rr, Paint()
            ..color = espresso.withValues(alpha: 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
        case 'holiday_paid':
        case 'holiday_unpaid':
          canvas.drawRRect(rr, Paint()..color = StatusColors.holiday.withValues(alpha: 0.30));
          _label(canvas, holiday, rect.center.dx, StatusColors.holiday);
        case 'leave_paid':
        case 'leave_unpaid':
          canvas.drawRRect(rr, Paint()..color = StatusColors.leave.withValues(alpha: 0.30));
          _label(canvas, leave, rect.center.dx, StatusColors.leave);
        case 'not_needed':
          final dot = Paint()..color = espresso.withValues(alpha: 0.25);
          for (double x = rect.left + 3; x < rect.right; x += 6) {
            canvas.drawCircle(Offset(x, cy), 1.3, dot);
          }
      }

      final at = info['scanned_at'];
      if (state == 'done' && at is String) {
        final px = win.x(size.width, _istMinutes(at)).clamp(rect.left + 7, rect.right - 7).toDouble();
        final center = Offset(px, cy);
        if (pulseSlot == slot) {
          final t = pulse.value;
          canvas.drawCircle(center, 7 + 13 * t, Paint()
            ..color = StatusColors.done.withValues(alpha: (1 - t) * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2);
        }
        final white = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        final fill = Paint()..color = StatusColors.done;
        if (info['is_manual'] == true) {
          final sq = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: 12, height: 12), const Radius.circular(3));
          canvas.drawRRect(sq, fill);
          canvas.drawRRect(sq, white);
        } else {
          canvas.drawCircle(center, 7, fill);
          canvas.drawCircle(center, 7, white);
          if (info['is_offline'] == true) canvas.drawCircle(center, 2.4, Paint()..color = Colors.white);
        }
        final t = DateTime.parse(at).toUtc().add(const Duration(hours: 5, minutes: 30));
        _label(canvas, DateFormat('h:mm', lang).format(t), center.dx, espresso.withValues(alpha: 0.8));
      }
    }

    final n = nowMin;
    if (n != null && n >= win.start && n <= win.end) {
      final x = win.x(size.width, n);
      final p = Paint()
        ..color = accent
        ..strokeWidth = 1.8;
      canvas.drawLine(Offset(x, 15), Offset(x, size.height - 2), p);
      canvas.drawCircle(Offset(x, 15), 2.8, p);
    }
  }

  @override
  bool shouldRepaint(_DayPainter old) => true;
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Widget mark, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          mark,
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 13, color: espresso.withValues(alpha: 0.75))),
        ]);
    Widget box(Color c, {bool hatched = false}) => Container(
          width: 18,
          height: 10,
          decoration: BoxDecoration(
            color: c.withValues(alpha: hatched ? 0.18 : 0.3),
            borderRadius: BorderRadius.circular(4),
            border: hatched ? Border.all(color: c) : null,
          ),
        );
    return Wrap(spacing: 14, runSpacing: 6, children: [
      item(Container(width: 12, height: 12, decoration: const BoxDecoration(color: StatusColors.done, shape: BoxShape.circle)),
          L.t('legend_scan')),
      item(Container(width: 12, height: 12, decoration: BoxDecoration(color: StatusColors.done, borderRadius: BorderRadius.circular(3))),
          L.t('legend_manual')),
      item(box(StatusColors.missed, hatched: true), L.t('legend_missed')),
      item(box(StatusColors.holiday), L.t('st_holiday_short')),
      item(box(StatusColors.leave), L.t('st_leave_short')),
      item(Container(width: 2, height: 14, color: accent), L.t('legend_now')),
    ]);
  }
}
