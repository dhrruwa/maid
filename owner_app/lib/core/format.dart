import 'package:intl/intl.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

String rupees(num? v) => _rupee.format(v ?? 0);

/// Today in Asia/Kolkata as a date-only DateTime.
DateTime istNow() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
DateTime istToday() {
  final n = istNow();
  return DateTime(n.year, n.month, n.day);
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String ym(DateTime d) => DateFormat('yyyy-MM').format(d);
DateTime parseYmd(String s) => DateTime.parse(s);

String shortDate(String ymdStr) => DateFormat('d MMM').format(parseYmd(ymdStr));
String longDate(String ymdStr) => DateFormat('EEE, d MMM yyyy').format(parseYmd(ymdStr));
String monthLabel(String ymStr) => DateFormat('MMMM yyyy').format(DateTime.parse('$ymStr-01'));
String monthName(String ymStr) => DateFormat('MMMM').format(DateTime.parse('$ymStr-01'));

/// ISO timestamp → "7:42 AM" in IST.
String istTime(String iso) {
  final t = DateTime.parse(iso).toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateFormat('h:mm a').format(t);
}

/// ISO timestamp → "29 Sep, 7:42 AM" in IST.
String istDateTime(String iso) {
  final t = DateTime.parse(iso).toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateFormat('d MMM, h:mm a').format(t);
}

String slotLabel(String s) =>
    s == 'morning' ? 'Morning' : s == 'evening' ? 'Evening' : 'Full day';

/// "06:00:00" → "6:00 AM"
String timeLabel(String hhmm) {
  final p = hhmm.split(':');
  final d = DateTime(2000, 1, 1, int.parse(p[0]), int.parse(p[1]));
  return DateFormat('h:mm a').format(d);
}
