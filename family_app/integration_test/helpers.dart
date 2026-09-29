import 'package:cook_family/core/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';

/// Screenshots through the driver (test_driver/integration_test.dart saves them).
class Shots {
  Shots(this.binding);
  final IntegrationTestWidgetsFlutterBinding binding;

  Future<void> take(WidgetTester t, String name) async {
    await t.pump();
    await binding.takeScreenshot(name);
  }
}

/// Pumps until [f] finds something (or nothing, with [gone]).
Future<void> waitFor(
  WidgetTester t,
  Finder f, {
  Duration timeout = const Duration(seconds: 30),
  bool gone = false,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty != gone) return;
  }
  throw TestFailure('Timed out waiting for $f${gone ? ' to disappear' : ''}\nOn screen: ${visibleTexts().join(' | ')}');
}

/// Every text on screen (for failure messages).
List<String> visibleTexts() => [
  for (final e in find.byType(Text).evaluate())
    if (e.widget is Text) (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '',
  for (final e in find.byType(EditableText).evaluate()) 'field:"${(e.widget as EditableText).controller.text}"',
];

/// Types [text] into a field. (enterText alone does not re-attach a field
/// that lost focus since the last enterText on it.)
Future<void> typeInto(WidgetTester t, Finder field, String text) async {
  t.binding.focusedEditable = null;
  await t.enterText(field, text);
  await t.pump(const Duration(milliseconds: 100));
}

/// Closes the keyboard (and any text toolbar) and taps [f] like a finger.
Future<void> press(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(t, 500);
  await t.tap(f);
}

/// Lets animations run for [ms] of real time.
Future<void> settle(WidgetTester t, [int ms = 900]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

bool _isType(Widget w, String name) => '${w.runtimeType}' == name;

final daySection = find.byWidgetPredicate((w) => _isType(w, '_DaySection'));
final slotCard = find.byWidgetPredicate((w) => _isType(w, '_SlotCard'));
Finder get homeList => find.byType(ListView).first;
Finder get homeScrollable => find.descendant(of: homeList, matching: find.byType(Scrollable)).first;

/// The day section whose header is [label] ("Today", "Tomorrow", "Thursday").
Finder dayOf(String label) => find.ancestor(of: find.text(label), matching: daySection);

/// Morning (at 0) and evening (at 1) cards of that day.
Finder cardsOf(String label) => find.descendant(of: dayOf(label), matching: slotCard);

/// India date [add] days from today, as a UTC midnight.
DateTime istDate(int add) {
  final n = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime.utc(n.year, n.month, n.day + add);
}

DateTime istDay(int add) => istDate(add);

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String dayLabel(int add) => add == 0
    ? 'Today'
    : add == 1
    ? 'Tomorrow'
    : DateFormat('EEEE').format(istDate(add));

/// Has [time] (India time) on [day] passed?
bool istPassed(DateTime day, Duration time) =>
    DateTime.now().toUtc().isAfter(day.add(time).subtract(const Duration(hours: 5, minutes: 30)));

/// Scrolls the home list so that the day [label] starts at the top.
Future<void> showDay(WidgetTester t, String label) async {
  if (find.text(label).evaluate().isEmpty) {
    await t.drag(homeList, const Offset(0, 6000)); // back to the top
    await settle(t, 500);
    await t.scrollUntilVisible(find.text(label), 300, scrollable: homeScrollable, maxScrolls: 80);
    await settle(t, 600); // entry animation (it moves the section while it runs)
  }
  final done = Scrollable.ensureVisible(t.element(dayOf(label)), alignment: 0.0);
  await settle(t, 500);
  await done;
  await settle(t, 300);
}

/// Scrolls [f] to the middle of the screen, then taps it.
Future<void> tapShown(WidgetTester t, Finder f) async {
  final done = Scrollable.ensureVisible(t.element(f), alignment: 0.5);
  await settle(t, 400);
  await done;
  await t.tap(f);
}

/// The number in "3 eating: …" (0 for "No one has booked yet").
int eatingCount(WidgetTester t, Finder card) {
  for (final e in find.descendant(of: card, matching: find.byType(Text)).evaluate()) {
    final w = e.widget as Text;
    final s = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (s == 'No one has booked yet') return 0;
    final m = RegExp(r'^(\d+) eating').firstMatch(s);
    if (m != null) return int.parse(m.group(1)!);
  }
  throw TestFailure('No "eating" line in the card');
}

/// The SLOT for [date]/[slot] as the server sees it now.
Future<Map<String, dynamic>> serverSlot(String date, String slot) async {
  final r = await Api.call('member_home', {'days': 7});
  for (final d in r['days'] as List) {
    if (d['date'] == date) return Map<String, dynamic>.from(d['slots'][slot] as Map);
  }
  throw TestFailure('No $date in member_home');
}
