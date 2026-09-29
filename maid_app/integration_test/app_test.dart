// UI walk-through of the Maid app on a simulator/phone: Home, My history
// (months, one month, past menus, leave) and Request leave, with a screenshot
// of each. It only reads: it never taps Scan QR, Send, View/Share slip or the
// language toggle, and it does not run main() (which would sync the phone's
// language/FCM token to the server).
//
// Nothing secret lives in this file; the paired phone's device id comes in at
// run time:
//
//   flutter drive -d <device> \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_test.dart \
//     --dart-define=TEST_MAID_DEVICE=<device id of a paired maid phone> \
//     --dart-define=TEST_LANG=kn            # en (default) or kn
//     --dart-define=TEST_SMALL=true         # optional: lay out in a 320x568 box
//     --dart-define=TEST_TEXT_SCALE=1.3     # optional: larger system text
//     --dart-define=TEST_TAG=kn             # optional: screenshot name prefix
//
// Screenshots are written by the driver to $SHOT_DIR (default
// build/screenshots). Layout errors (overflow stripes etc.) are collected and
// reported at the end instead of stopping the walk-through.

import 'package:cook_attendance/core/device.dart';
import 'package:cook_attendance/core/i18n.dart';
import 'package:cook_attendance/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _device = String.fromEnvironment('TEST_MAID_DEVICE');
const _lang = String.fromEnvironment('TEST_LANG', defaultValue: 'en');
const _small = bool.fromEnvironment('TEST_SMALL');
const _textScale = String.fromEnvironment('TEST_TEXT_SCALE', defaultValue: '1.0');
const _tag = String.fromEnvironment('TEST_TAG', defaultValue: _lang);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('maid app walk-through ($_tag)', (tester) async {
    expect(_device, isNotEmpty, reason: 'pass --dart-define=TEST_MAID_DEVICE=<device id>');

    // (tester.view.physicalSize can't be used on a phone/simulator: the
    // engine drops frames whose size doesn't match the screen. So a small
    // phone is imitated by laying the app out in a 320 x 568 box instead.)
    final scale = double.tryParse(_textScale) ?? 1.0;
    if (scale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    // Layout errors are noted and reported at the end, so one overflow does
    // not hide the screens after it.
    final problems = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.exceptionAsString();
      problems.add('${d.library}: ${text.split('\n').first}');
      debugPrint('LAYOUT PROBLEM: ${d.toString()}');
    };

    // The paired maid phone: device id, name and language (local only).
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('device_id', _device);
    await prefs.setBool('paired', true);
    await prefs.setString('name', 'Test');
    await prefs.setString('lang', _lang);
    await Device.init();
    await L.init();
    runApp(_small ? const _SmallPhone(child: CookApp()) : const CookApp());

    var n = 0;
    Future<void> shot(String name) async {
      await _pumpFor(tester, const Duration(milliseconds: 900));
      n++;
      await binding.takeScreenshot('$_tag-${n.toString().padLeft(2, '0')}-$name');
    }

    Future<void> checkGuidelines(String screen) async {
      for (final (label, g) in [
        ('android tap target 48dp', androidTapTargetGuideline),
        ('iOS tap target 44pt', iOSTapTargetGuideline),
        ('labeled tap targets', labeledTapTargetGuideline),
      ]) {
        try {
          await expectLater(tester, meetsGuideline(g));
          debugPrint('GUIDELINE OK [$screen] $label');
        } catch (e) {
          problems.add('guideline [$screen] $label: ${'$e'.split('\n').take(6).join(' | ')}');
          debugPrint('GUIDELINE FAIL [$screen] $label: $e');
        }
      }
    }

    Future<void> walk() async {
      // ---------- Home ----------
      await _waitFor(tester, find.text(L.t('earned_so_far')), const Duration(seconds: 40));
      await _pumpFor(tester, const Duration(seconds: 2));
      await shot('home_top');
      if (_small) {
        await _scrollTo(tester, find.text(L.t('scan_qr')));
        await shot('home_scan');
        await _scrollBy(tester, -3000);
      }
      await checkGuidelines('home');

      await tester.tap(find.text(L.t('tap_details')));
      await shot('home_salary_details');
      await _dismissSheet(tester);

      final cook = find.text(L.t('what_to_cook'));
      await _scrollTo(tester, cook);
      await shot('home_cook_today');

      await tester.tap(find.text(L.t('tomorrow')));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      await _scrollTo(tester, cook);
      await shot('home_cook_tomorrow');
      await _scrollBy(tester, 420);
      await shot('home_cook_tomorrow_evening');
      await tester.tap(find.text(L.t('today')).first);
      await _pumpFor(tester, const Duration(milliseconds: 500));

      await _scrollTo(tester, find.text(L.t('this_week')));
      await shot('home_this_week');
      await _scrollBy(tester, 3000);
      await shot('home_bottom');

      // ---------- My history ----------
      await tester.tap(find.text(L.t('my_history')));
      await _waitFor(tester, find.text(L.t('months')), const Duration(seconds: 5));
      await _waitFor(tester, find.byType(Card), const Duration(seconds: 30));
      await shot('history_months');
      await checkGuidelines('history');

      await tester.tap(find.byType(Card).first);
      await _waitFor(tester, find.text(L.t('day_by_day')), const Duration(seconds: 30));
      await shot('month_top');
      await _scrollBy(tester, 500);
      await shot('month_days');
      await _scrollBy(tester, 3000);
      await shot('month_end');
      await tester.tap(find.byType(BackButton));
      await _pumpFor(tester, const Duration(milliseconds: 700));

      await tester.tap(find.text(L.t('past_menus')));
      await _pumpFor(tester, const Duration(seconds: 3));
      await shot('history_past_menus');
      await tester.tap(find.byIcon(Icons.calendar_month_rounded));
      await _pumpFor(tester, const Duration(milliseconds: 800));
      await shot('history_date_picker');
      Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
      await _pumpFor(tester, const Duration(milliseconds: 600));

      await tester.tap(find.text(L.t('leave_tab')));
      await _pumpFor(tester, const Duration(seconds: 3));
      await shot('history_leave');
      await tester.tap(find.byType(BackButton));
      await _pumpFor(tester, const Duration(milliseconds: 700));

      // ---------- Request leave (never sent) ----------
      await tester.tap(find.text(L.t('request_leave')));
      await _waitFor(tester, find.text(L.t('leave_title')), const Duration(seconds: 5));
      await _pumpFor(tester, const Duration(seconds: 2));
      await shot('leave_top');
      await checkGuidelines('leave');
      await tester.tap(find.text(L.slot('evening')).last);
      await _scrollBy(tester, 3000);
      await shot('leave_bottom');
      await tester.tap(find.byType(BackButton));
      await _pumpFor(tester, const Duration(milliseconds: 700));
    }

    Object? failure;
    try {
      await walk();
    } catch (e, st) {
      failure = e;
      debugPrint('WALKTHROUGH FAILED: $e\n$st');
      final texts = find.byType(Text).evaluate().map((el) => (el.widget as Text).data).whereType<String>();
      debugPrint('ON SCREEN: ${texts.take(40).join(' | ')}');
      try {
        await binding.takeScreenshot('$_tag-FAILED');
      } catch (_) {}
    } finally {
      FlutterError.onError = original;
    }
    debugPrint('WALKTHROUGH DONE [$_tag] problems=${problems.length}');
    for (final p in problems) {
      debugPrint('PROBLEM: $p');
    }
    if (failure != null) fail('$failure');
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _waitFor(WidgetTester tester, Finder f, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for $f');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the page so [f] sits near the top of the screen.
Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(f.first), alignment: 0.02);
  await _pumpFor(tester, const Duration(milliseconds: 400));
}

Future<void> _scrollBy(WidgetTester tester, double dy) async {
  final pos = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  pos.jumpTo((pos.pixels + dy).clamp(pos.minScrollExtent, pos.maxScrollExtent));
  await _pumpFor(tester, const Duration(milliseconds: 400));
}

Future<void> _dismissSheet(WidgetTester tester) async {
  final sheet = find.byType(BottomSheet);
  if (sheet.evaluate().isNotEmpty) Navigator.of(tester.element(sheet)).pop();
  await _pumpFor(tester, const Duration(milliseconds: 600));
}

/// Lays the app out as on a 320 x 568 pt phone (top-left of the screen).
/// The app's own MediaQuery still reports the real screen, so only widths and
/// heights from layout constraints are "small" – which is what overflows.
class _SmallPhone extends StatelessWidget {
  const _SmallPhone({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF202020),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 320, height: 568, child: ClipRect(child: child)),
      ),
    );
  }
}
