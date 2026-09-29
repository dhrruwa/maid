// End-to-end test of the Family app against the configured Supabase project.
//
// It logs in as a THROWAWAY member that the owner created for testing (never a
// real family member), books a future meal, adds a note, cancels it again and
// checks closed / weekend slots. Nothing secret lives in this file: the member
// name and PIN come from --dart-define at run time.
//
//   SCREENSHOT_DIR=/tmp/shots flutter drive -d <device> \
//     --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart \
//     --dart-define-from-file=../dart_defines.json \
//     --dart-define=TEST_NAME='Test …' --dart-define=TEST_PIN=….
//
// Leaves the phone logged in (so a relaunch can be checked) and the booking
// cancelled.
import 'package:cook_family/core/api.dart';
import 'package:cook_family/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

const testName = String.fromEnvironment('TEST_NAME');
const testPin = String.fromEnvironment('TEST_PIN');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shots = Shots(binding);
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('log in, book, note, cancel, closed and weekend slots', (t) async {
    expect(testName.startsWith('Test '), isTrue, reason: 'Pass --dart-define=TEST_NAME="Test …" (a throwaway member)');
    expect(RegExp(r'^\d{4}$').hasMatch(testPin), isTrue, reason: 'Pass --dart-define=TEST_PIN=<4 digits>');

    // A fresh phone: no login, no saved replies.
    (await SharedPreferences.getInstance()).clear();
    app.main();
    await waitFor(t, find.text('Log in'));
    await settle(t);
    await shots.take(t, '01_login');

    // ---- wrong PIN ----
    final wrongPin = ((int.parse(testPin) + 1111) % 10000).toString().padLeft(4, '0');
    await typeInto(t, find.widgetWithText(TextField, 'Your name'), testName);
    await typeInto(t, find.widgetWithText(TextField, 'PIN'), wrongPin);
    await press(t, find.text('Log in'));
    await waitFor(t, find.textContaining("don't match"), timeout: const Duration(seconds: 20));
    await settle(t);
    await shots.take(t, '02_wrong_pin');
    // The PIN field is cleared after a wrong PIN, the name is kept.
    expect(find.text(testName), findsOneWidget);

    // ---- right PIN ----
    await typeInto(t, find.widgetWithText(TextField, 'PIN'), testPin);
    await press(t, find.text('Log in'));
    await waitFor(t, find.text('Hi $testName'), timeout: const Duration(seconds: 30));
    await waitFor(t, daySection, timeout: const Duration(seconds: 30));
    await settle(t, 1500);
    await shots.take(t, '03_home_top');

    final today = istDay(0);
    // ---- today: both meals have started → Closed, no Book button ----
    final todayCards = cardsOf(dayLabel(0));
    expect(todayCards, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      final card = todayCards.at(i);
      final off = find.descendant(of: card, matching: find.byWidgetPredicate((w) => '${w.runtimeType}' == '_OffRow'));
      if (off.evaluate().isNotEmpty) continue; // off today: nothing to book either
      if (!istPassed(today, i == 0 ? const Duration(hours: 6) : const Duration(hours: 15))) continue;
      expect(find.descendant(of: card, matching: find.text('Closed')), findsOneWidget,
          reason: 'Today ${i == 0 ? 'morning' : 'evening'} has started: it must say Closed');
      expect(find.descendant(of: card, matching: find.byType(FilledButton)), findsNothing);
      // Tapping the card does nothing.
      await t.tap(card, warnIfMissed: false);
      await settle(t, 400);
      expect(find.descendant(of: card, matching: find.text('Saving…')), findsNothing);
    }
    // The server refuses too (the slot has started).
    if (istPassed(today, const Duration(hours: 15))) {
      Object? err;
      try {
        await Api.call('book_meal', {'date': ymd(today), 'slot': 'evening', 'book': true});
      } catch (e) {
        err = e;
      }
      if (err == null) {
        // Must not happen; undo right away so no booking is left behind.
        await Api.call('book_meal', {'date': ymd(today), 'slot': 'evening', 'book': false});
      }
      expect(err, isA<ApiError>());
      expect((err as ApiError).code, anyOf('BOOKING_CLOSED', 'SLOT_OFF'));
    }

    // ---- scrolled ----
    await t.drag(homeList, const Offset(0, -700));
    await settle(t, 800);
    await shots.take(t, '04_home_scrolled');

    // ---- book the first open morning from two days ahead (not today/tomorrow:
    // keeps the cook's view of what to cook clean) ----
    var ahead = -1;
    for (var i = 2; i < 7 && ahead < 0; i++) {
      await showDay(t, dayLabel(i));
      if (find.descendant(of: cardsOf(dayLabel(i)).at(0), matching: find.text('Book morning')).evaluate().isNotEmpty) {
        ahead = i;
      }
    }
    expect(ahead, greaterThan(0), reason: 'No open morning in the next days to book');
    final label = dayLabel(ahead);
    await showDay(t, label);
    final card = cardsOf(label).at(0);
    final bookBtn = find.descendant(of: card, matching: find.text('Book morning'));
    final countBefore = eatingCount(t, card);
    await tapShown(t, bookBtn);
    await t.pump(const Duration(milliseconds: 50));
    // Optimistic: Booked ✓ at once.
    expect(find.descendant(of: card, matching: find.text('Booked ✓')), findsOneWidget);
    await waitFor(t, find.descendant(of: card, matching: find.text('Saving…')), gone: true);
    await settle(t, 600);
    expect(find.descendant(of: card, matching: find.text('Booked ✓')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Cancel')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining(testName)), findsWidgets);
    expect(eatingCount(t, card), countBefore + 1);
    await showDay(t, label);
    await shots.take(t, '05_booked');

    // Server agrees.
    var slot = await serverSlot(ymd(istDate(ahead)), 'morning');
    expect(slot['booked'], true);
    expect([for (final p in slot['bookings']['people'] as List) p['name']], contains(testName));

    // ---- note ----
    const note = 'No onion and no garlic please, less spicy, and extra curd on the side. Thank you so much!';
    await tapShown(t, find.descendant(of: card, matching: find.text('Add a note')));
    await waitFor(t, find.byType(AlertDialog));
    await typeInto(t, find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), note);
    await settle(t, 500);
    await shots.take(t, '06_note_dialog');
    await press(t, find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')));
    await waitFor(t, find.byType(AlertDialog), gone: true);
    await waitFor(t, find.descendant(of: card, matching: find.textContaining('Your note: ')));
    await waitFor(t, find.descendant(of: card, matching: find.text('Saving…')), gone: true);
    await settle(t, 800);
    await showDay(t, label);
    await shots.take(t, '07_note_added');
    slot = await serverSlot(ymd(istDate(ahead)), 'morning');
    expect(slot['note'], note);

    // Who's eating (with notes).
    await tapShown(t, find.descendant(of: card, matching: find.textContaining('eating: ')));
    await waitFor(t, find.byType(BottomSheet));
    await settle(t, 700);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('$testName (you)')), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(note)), findsOneWidget);
    await shots.take(t, '08_eating_sheet');
    await t.tapAt(const Offset(200, 120)); // barrier
    await waitFor(t, find.byType(BottomSheet), gone: true);
    await settle(t, 400);

    // ---- cancel ----
    await tapShown(t, find.descendant(of: card, matching: find.text('Cancel')));
    await t.pump(const Duration(milliseconds: 50));
    await waitFor(t, find.descendant(of: card, matching: find.text('Book morning')));
    await waitFor(t, find.descendant(of: card, matching: find.text('Saving…')), gone: true);
    await settle(t, 800);
    expect(eatingCount(t, card), countBefore);
    expect(find.descendant(of: card, matching: find.textContaining('Your note')), findsNothing);
    await showDay(t, label);
    await shots.take(t, '09_cancelled');
    slot = await serverSlot(ymd(istDate(ahead)), 'morning');
    expect(slot['booked'], false);
    expect(slot['note'], isNull);

    // ---- weekend evenings are off ----
    var weekendShot = false;
    for (var i = 0; i < 7; i++) {
      final d = istDate(i);
      if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) continue;
      final l = dayLabel(i);
      await showDay(t, l);
      final evening = cardsOf(l).at(1);
      final off = find.descendant(of: evening, matching: find.byWidgetPredicate((w) => '${w.runtimeType}' == '_OffRow'));
      expect(off, findsOneWidget, reason: '$l evening must be off');
      expect(find.descendant(of: evening, matching: find.byType(FilledButton)), findsNothing);
      if (find.descendant(of: evening, matching: find.text('No evening meal on weekends')).evaluate().isEmpty) {
        // A holiday or the cook's leave wins over the weekend rule.
        expect(find.descendant(of: evening, matching: find.textContaining(RegExp('Holiday|Cook on leave'))), findsWidgets);
      }
      if (!weekendShot) {
        await shots.take(t, '10_weekend_${DateFormat('EEE').format(d).toLowerCase()}');
        weekendShot = true;
      }
    }

    // ---- top-right menu → Refresh ----
    await t.drag(homeList, const Offset(0, 5000));
    await settle(t, 600);
    await t.tap(find.byTooltip('Menu'));
    await settle(t, 600);
    await shots.take(t, '11_menu');
    await t.tap(find.text('Refresh'));
    await settle(t, 2500);

    // ---- pull to refresh ----
    await t.fling(homeList, const Offset(0, 400), 1200);
    await t.pump(const Duration(milliseconds: 300));
    await shots.take(t, '12_pull_to_refresh');
    await settle(t, 3000);
    expect(find.text('Hi $testName'), findsOneWidget);
    expect(find.textContaining("Couldn't refresh"), findsNothing);
  });
}
