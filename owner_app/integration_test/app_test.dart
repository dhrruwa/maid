// Read-only UI walk through the Owner app against the live backend.
//
// It never taps anything that writes (no Mark as paid, holiday, leave decision,
// settings change, member change, pairing). Screenshots are taken by the host:
// the test prints `@@SHOT <name>` and waits until the host writes
// `<SHOT_DIR>/.ack_<name>` (or a few seconds pass). `@@APPEARANCE dark|light`
// and `@@CONTENT_SIZE <size>` ask the host to change the simulator's settings.
//
// Run (ids and keys only at run time, never in this file):
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_test.dart -d <simulator> \
//     --dart-define-from-file=../dart_defines.json \
//     --dart-define=TEST_OWNER_DEVICE=<owner device id> \
//     --dart-define=SHOT_DIR=<host folder watched by the screenshot script>
import 'dart:io';

import 'package:cook_dashboard/core/device.dart';
import 'package:cook_dashboard/core/format.dart';
import 'package:cook_dashboard/main.dart' as app;
import 'package:cook_dashboard/screens/history/history_screen.dart';
import 'package:cook_dashboard/screens/menu/menu_screen.dart';
import 'package:cook_dashboard/widgets/glass.dart';
import 'package:cook_dashboard/widgets/pin_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The owner's device id (read from the live database by whoever runs this).
const ownerDevice = String.fromEnvironment('TEST_OWNER_DEVICE');

/// A local PIN that only exists in this simulator's preferences.
const testPin = String.fromEnvironment('TEST_PIN', defaultValue: '2580');

/// Host folder where the screenshot script writes its acknowledgements.
const shotDir = String.fromEnvironment('SHOT_DIR');

/// Name of the throwaway member whose actions menu may be opened (never used).
const testMember = String.fromEnvironment('TEST_MEMBER');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('owner app read-only walk', (tester) async {
    expect(ownerDevice, isNotEmpty, reason: 'pass --dart-define=TEST_OWNER_DEVICE=...');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_id', ownerDevice);
    await prefs.setString('pin_hash', Device.hashPin(testPin));
    await prefs.setBool('setup_done', true);

    // Collect framework errors (overflows, exceptions) instead of failing at
    // the first one, so the whole walk runs; they are listed at the end.
    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.exceptionAsString().split('\n').first;
      if (!errors.contains(text)) {
        // First time: where it comes from (the widget and its source line).
        final where = d.toString().split('\n').where((l) => l.contains('file://') || l.contains('error-causing'));
        debugPrint('@@FLUTTER_ERROR_DETAIL $text | ${where.take(4).join(' | ')}');
      }
      errors.add(text);
      debugPrint('@@FLUTTER_ERROR $text');
    };

    Size screen() => tester.view.physicalSize / tester.view.devicePixelRatio;

    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<bool> waitFor(Finder f, {int seconds = 20}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (f.evaluate().isNotEmpty) return true;
      }
      debugPrint('@@WARN not found: $f');
      return false;
    }

    Future<void> host(String command, String name) async {
      final ack = File('$shotDir/.ack_$name');
      if (shotDir.isNotEmpty && ack.existsSync()) ack.deleteSync();
      debugPrint('@@$command');
      final end = DateTime.now().add(const Duration(seconds: 12));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (shotDir.isNotEmpty && ack.existsSync()) return;
      }
      debugPrint('@@WARN no ack for $name');
    }

    Future<void> shot(String name) async {
      await wait(600);
      await host('SHOT $name', name);
    }

    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
      } catch (e, st) {
        debugPrint('@@STEP_FAILED $name: $e\n$st');
      }
    }

    Finder navTab(String label) => find.descendant(of: find.byType(GlassNavBar), matching: find.text(label));

    Future<void> goTab(String label) async {
      await tester.tap(navTab(label));
      await wait(1500);
    }

    /// Scrolls the vertical list under the middle of the screen by [dy] points.
    Future<void> scroll(double dy) async {
      final s = screen();
      await tester.dragFrom(Offset(s.width / 2, s.height * 0.55), Offset(0, -dy));
      await wait(900);
    }

    Future<void> scrollToTop() async {
      for (var i = 0; i < 3; i++) {
        await scroll(-900);
      }
    }

    /// Closes a bottom sheet or popup menu by tapping its barrier at the top.
    Future<void> dismissSheet() async {
      await tester.tapAt(Offset(screen().width / 2, 70));
      await wait(900);
    }

    final tomorrow = istToday().add(const Duration(days: 1));

    // ---- Start + unlock ----------------------------------------------------
    app.main();
    await waitFor(find.text('Enter PIN'));
    await shot('01_lock');
    for (final d in testPin.split('')) {
      await tester.tap(find.descendant(of: find.byType(PinPad), matching: find.text(d)));
      await tester.pump(const Duration(milliseconds: 150));
    }
    await waitFor(find.textContaining('Earned so far'), seconds: 40);
    await wait(3500); // menu counts, week timeline, entry animations

    // ---- Home --------------------------------------------------------------
    await step('home', () async {
      await shot('02_home_top');
      await tester.tap(find.textContaining('Lost this month'));
      await wait(800);
      await shot('03_home_salary_open');
      await tester.tap(find.textContaining('Lost this month'));
      await wait(600);
      await scroll(330);
      await shot('04_home_scroll1');
      await scroll(330);
      await shot('05_home_scroll2');
      await scroll(900);
      await shot('06_home_bottom');
      await scrollToTop();
    });

    // ---- Calendar (by swiping the pages) ----------------------------------
    await step('calendar', () async {
      final s = screen();
      await tester.flingFrom(Offset(s.width * 0.85, s.height * 0.45), Offset(-s.width * 0.6, 0), 1500);
      await wait(2500);
      await shot('07_calendar');
      await scroll(500);
      await shot('08_calendar_bottom');
      await scrollToTop();
    });

    // ---- Menu --------------------------------------------------------------
    await step('menu', () async {
      await goTab('Menu');
      await wait(1500);
      await shot('09_menu_today');
      await tester.tap(find.descendant(of: find.byType(MenuScreen), matching: find.text('${tomorrow.day}')).first);
      await wait(3000);
      await shot('10_menu_tomorrow');
      final other = find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.textContaining(istNow().hour < 12 ? 'Evening' : 'Morning'));
      await tester.tap(other);
      await wait(1200);
      await shot('11_menu_tomorrow_other_slot');
      await tester.tap(other); // back to the first slot
      await wait(800);
      for (final slot in ['Evening', 'Morning']) {
        final seg = find.descendant(of: find.byType(SegmentedButton<String>), matching: find.textContaining(slot));
        await tester.tap(seg);
        await wait(900);
        final row = find.descendant(of: find.byType(MenuScreen), matching: find.textContaining(' eating'));
        if (row.evaluate().isNotEmpty) {
          await tester.tap(row.first);
          await wait(1500);
          await shot('12_bookings_sheet_${slot.toLowerCase()}');
          await dismissSheet();
          break;
        }
      }
    });

    // ---- History -----------------------------------------------------------
    await step('history', () async {
      await goTab('History');
      await wait(2500);
      await shot('13_history_activity');
      // The chip row scrolls sideways; Bookings is off screen at first.
      final chips = find
          .descendant(
            of: find.byType(ActivityTab),
            // Not the search field's own scrollable (restorationId 'editable').
            matching: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.right && w.restorationId == null),
          )
          .first;
      await tester.scrollUntilVisible(find.widgetWithText(FilterChip, 'Bookings'), 150, scrollable: chips);
      await wait(600);
      await tester.tap(find.widgetWithText(FilterChip, 'Bookings'));
      await wait(3500);
      await shot('14_activity_bookings');
      final booked = find.textContaining(' booked ');
      if (booked.evaluate().isNotEmpty) {
        await tester.tap(booked.first);
        await wait(1500);
        await shot('15_activity_booking_event');
        await dismissSheet();
      }
      await tester.tap(find.widgetWithText(FilterChip, 'Bookings')); // filter off again
      await wait(1500);
      // Actor filter: what family members did in the Family app.
      await tester.scrollUntilVisible(find.widgetWithText(ChoiceChip, 'Family'), 150, scrollable: chips);
      await wait(600);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Family'));
      await wait(3500);
      await shot('15b_activity_actor_family');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Family')); // filter off again
      await wait(1500);
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Payments')));
      await wait(2500);
      await shot('16_history_payments');
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Menu')));
      await wait(2500);
      await shot('17_history_menu');
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Leave')));
      await wait(2500);
      await shot('18_history_leave');
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Activity')));
      await wait(800);
    });

    // ---- Tab bar taps back to Home, then Settings → Family members --------
    await step('settings', () async {
      await goTab('Calendar');
      await goTab('Home');
      await shot('19_home_via_tab');
      await tester.tap(find.byTooltip('Settings'));
      await wait(3000);
      await shot('20_settings_top');
      await tester.tap(find.text('Family members'));
      await wait(4000);
      await shot('21_members');
      await scroll(400);
      await shot('22_members_scrolled');
      if (testMember.isNotEmpty) {
        final menu = find.byTooltip('Actions for $testMember');
        if (menu.evaluate().isNotEmpty) {
          await tester.ensureVisible(menu);
          await wait(500);
          await tester.tap(menu);
          await wait(1000);
          await shot('23_member_actions_test_member');
          await dismissSheet();
        }
      }
      await tester.pageBack();
      await wait(1500);
      await scroll(600);
      await shot('24_settings_mid');
      await scroll(900);
      await shot('25_settings_bottom');
      await tester.pageBack();
      await wait(1500);
    });

    // ---- Dark mode ---------------------------------------------------------
    await step('dark', () async {
      await host('APPEARANCE dark', 'dark');
      await wait(2000);
      await scrollToTop();
      await shot('30_dark_home_top');
      await scroll(450);
      await shot('31_dark_home_scroll');
      await scroll(900);
      await shot('32_dark_home_bottom');
      await scrollToTop();
      await goTab('Menu');
      await shot('33_dark_menu');
      final row = find.descendant(of: find.byType(MenuScreen), matching: find.textContaining(' eating'));
      if (row.evaluate().isNotEmpty) {
        await tester.tap(row.first);
        await wait(1500);
        await shot('34_dark_bookings_sheet');
        await dismissSheet();
      }
      await goTab('Calendar');
      await shot('35_dark_calendar');
      await goTab('History');
      await shot('36_dark_history');
      await goTab('Home');
      await tester.tap(find.byTooltip('Settings'));
      await wait(2500);
      await tester.tap(find.text('Family members'));
      await wait(2500);
      await shot('37_dark_members');
      await tester.pageBack();
      await wait(1200);
      await tester.pageBack();
      await wait(1200);
      await host('APPEARANCE light', 'light');
      await wait(1500);
    });

    // ---- Larger text -------------------------------------------------------
    await step('large text', () async {
      await host('CONTENT_SIZE extra-extra-extra-large', 'xxxl');
      await wait(2500);
      await scrollToTop();
      await shot('40_xxxl_home_top');
      await scroll(450);
      await shot('41_xxxl_home_scroll');
      await scroll(450);
      await shot('42_xxxl_home_scroll2');
      await scrollToTop();
      await goTab('Menu');
      await shot('43_xxxl_menu');
      await goTab('History');
      await shot('44_xxxl_history');
      await goTab('Home');
      await tester.tap(find.byTooltip('Settings'));
      await wait(2500);
      await tester.tap(find.text('Family members'));
      await wait(2500);
      await shot('45_xxxl_members');
      await tester.pageBack();
      await wait(1200);
      await tester.pageBack();
      await wait(1200);
      await host('CONTENT_SIZE large', 'default_size');
      await wait(1500);
    });

    FlutterError.onError = original;
    debugPrint('@@DONE errors=${errors.length}');
    for (final e in errors.toSet()) {
      debugPrint('@@ERROR_SUMMARY $e');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
