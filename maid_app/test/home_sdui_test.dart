// Home drawn from server blocks, with saved data only (the test has no
// network: every call fails, so Home shows what's saved, as when offline).

import 'dart:convert';

import 'package:cook_attendance/core/api.dart';
import 'package:cook_attendance/core/device.dart';
import 'package:cook_attendance/core/i18n.dart';
import 'package:cook_attendance/screens/home_screen.dart';
import 'package:cook_attendance/sdui/server_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _day = {
  'date': '2026-09-30',
  'dow': 3,
  'slots': {
    'morning': {'state': 'done', 'attendance': {'scanned_at': '2026-09-30T02:40:00Z'}},
    'evening': {'state': 'pending', 'attendance': null},
  },
};

final _salary = {
  'month': '2026-09',
  'from': '2026-09-01',
  'earned': 2400,
  'expected_total': 2800,
  'payday': '2026-10-01',
  'days_to_payday': 1,
  'breakdown': <String, Object>{},
  'last_payment': null,
  'today_info': _day,
};

final _menu = {
  'morning': {'items': [], 'off': null},
  'evening': {'items': [], 'off': null},
};

Map<String, Object> _ui(List<Object> home, [Map<String, Object> strings = const {}]) => {
      'ok': true,
      'ui': {
        'id': 'test',
        'schema': 1,
        'screens': {
          'home': {'blocks': home},
        },
        'strings': strings,
      },
    };

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'device_id': 'cook-0123456789abcdef0123456789abcdef',
      'paired': true,
      'name': 'Lakshmi',
      'lang': 'en',
      'home_cache': jsonEncode({'salary': _salary, 'today': _menu, 'tomorrow': _menu}),
    });
    await Device.init();
    await L.init();
    ServerUi.reset();
  });

  Future<void> showHome(WidgetTester tester) async {
    // Very tall, so the list builds every section; wide, because the test
    // font's square glyphs make text far wider than on a phone (real small
    // phones are covered by integration_test/app_test.dart).
    tester.view.physicalSize = const Size(1440, 7200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('saved server layout: its order, a notice and a text override', (tester) async {
    ApiCache.write(
      'get_ui',
      {'schema': ServerUi.schema},
      _ui([
        {'type': 'notice', 'icon': 'celebration', 'tone': 'success', 'title': 'Happy Diwali, {name}!'},
        {'type': 'scan_button'},
        {'type': 'today_card'},
      ], {
        'en': {'scan_qr': 'Scan kitchen QR'},
      }),
    );

    await showHome(tester);

    final notice = find.text('Happy Diwali, Lakshmi!');
    final scan = find.text('Scan kitchen QR');
    final today = find.textContaining(L.t('today'));
    expect(notice, findsOneWidget);
    expect(scan, findsOneWidget);
    expect(today, findsOneWidget);
    expect(tester.getTopLeft(notice).dy, lessThan(tester.getTopLeft(scan).dy));
    expect(tester.getTopLeft(scan).dy, lessThan(tester.getTopLeft(today).dy));
    // Left out of this layout.
    expect(find.text(L.t('earned_so_far')), findsNothing);
    expect(find.text(L.t('what_to_cook')), findsNothing);
  });

  testWidgets('a server Home without Scan QR is ignored', (tester) async {
    ApiCache.write('get_ui', {'schema': ServerUi.schema}, _ui([
      {'type': 'notice', 'title': 'Only a notice'},
    ]));

    await showHome(tester);

    expect(find.text('Only a notice'), findsNothing);
    expect(find.text(L.t('scan_qr')), findsOneWidget);
    expect(find.text(L.t('earned_so_far')), findsOneWidget);
  });

  testWidgets('nothing from the server: the built-in Home', (tester) async {
    await showHome(tester);

    expect(find.text(L.t('earned_so_far')), findsOneWidget);
    expect(find.text(L.t('scan_qr')), findsOneWidget);
    // Offline in this test, so the "showing saved information" banner is on.
    expect(find.text(L.t('showing_saved')), findsOneWidget);
  });
}
