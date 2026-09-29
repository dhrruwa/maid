// Layout and error-path test of the Family app against a fake server running
// inside the test (no real data is read or written). It feeds the app extreme
// content — very long dish names and notes, many people, holidays, leave,
// weekend evenings — at normal and large text sizes and on a narrow phone, and
// walks the error paths (locked login, booking closed while the screen was
// open, lost connection, the owner resetting the login, logging out).
//
//   SCREENSHOT_DIR=/tmp/shots flutter drive -d <device> \
//     --driver=test_driver/integration_test.dart --target=integration_test/layout_test.dart \
//     --dart-define=SUPABASE_URL=http://127.0.0.1:47651 --dart-define=SUPABASE_ANON_KEY=fake-key-for-tests
//
// Any layout overflow fails the test (the test framework reports it).
import 'dart:convert';
import 'dart:io';

import 'package:cook_family/config.dart';
import 'package:cook_family/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

const _longDish =
    'Hyderabadi Vegetable Dum Biryani with Mirchi ka Salan, Burani Raita and Crispy Fried Onions';
const _unbreakable = 'Bisibelebathwithextragheeandboondi';
const _longNote =
    'Please make it less spicy, no onion and no garlic, and keep the curd separate for the kids. Thank you!';
const _me = 'Test Layout Person With A Long Name';

final _people = [
  for (final n in [
    'Alexandria Venkataraman',
    'Bhagyalakshmi',
    'Chandrashekhar Subramaniam',
    'Dev',
    'Elizabeth-Anne',
    'Fatima',
    'Gurupadaswamy Mahalingappa',
    'Hari',
  ])
    {'name': n, 'note': n.length > 12 ? _longNote : null},
];

/// The fake Supabase Edge Functions.
class FakeServer {
  late HttpServer _server;
  final Map<String, Map<String, dynamic>> slots = {}; // 'date|slot' → SLOT
  final List<String> dates = [];

  /// Next member_home / book_meal answers.
  bool down = false;
  bool notMember = false;
  final closeOnBook = <String>{}; // 'date|slot' that answer BOOKING_CLOSED

  static DateTime get _now => DateTime.now().toUtc();

  Future<void> start(Uri url) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, url.port);
    _seed();
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Map<String, dynamic> _slot({
    List<Map<String, dynamic>> items = const [],
    Map<String, dynamic>? off,
    bool open = true,
    bool booked = false,
    String? note,
    List<Map<String, dynamic>> people = const [],
  }) {
    final cutoff = open ? _now.add(const Duration(hours: 5)) : _now.subtract(const Duration(hours: 1));
    final all = [...people, if (booked) {'name': _me, 'note': note}];
    return {
      'items': items,
      'off': off,
      'cutoff': cutoff.toIso8601String(),
      'open': off == null && open,
      'booked': booked,
      'note': note,
      'bookings': {'count': all.length, 'people': all},
    };
  }

  static Map<String, dynamic> _dish(String name, {String? yt, String? notes, String? dishNotes}) => {
    'menu_id': 'm-$name',
    'dish_id': 'd-$name',
    'name': name,
    'youtube_url': yt,
    'notes': notes,
    'dish_notes': dishNotes,
  };

  void _seed() {
    for (var i = 0; i < 7; i++) {
      dates.add(ymd(istDate(i)));
    }
    final dishes = [
      _dish(_longDish, yt: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', notes: _longNote, dishNotes: 'Soak the rice for 30 minutes before cooking. Use the big handi.'),
      _dish(_unbreakable, notes: 'extra ghee'),
      _dish('Chapati'),
    ];
    void put(int day, String slot, Map<String, dynamic> s) => slots['${dates[day]}|$slot'] = s;
    // Today: morning over (closed, booked); evening open and booked with a long note.
    put(0, 'morning', _slot(items: dishes, open: false, booked: true, note: 'Less oil', people: _people.take(3).toList()));
    put(0, 'evening', _slot(items: dishes, booked: true, note: _longNote, people: _people));
    // Tomorrow: holiday with a long note in the morning, cook on leave in the evening.
    put(1, 'morning', _slot(off: {'type': 'holiday', 'paid': true, 'note': 'Diwali — everyone is travelling to the village for the festival and the cook is off'}));
    put(1, 'evening', _slot(off: {'type': 'leave', 'paid': false, 'note': 'Private reason that must not be shown'}));
    // Day 2: nothing decided yet / open with many people.
    put(2, 'morning', _slot());
    put(2, 'evening', _slot(items: dishes.take(2).toList(), people: _people));
    // Day 3: closed without booking; "no meal" morning (not_needed).
    put(3, 'morning', _slot(off: {'type': 'not_needed', 'paid': false, 'note': null}));
    put(3, 'evening', _slot(items: [dishes[2]], open: false, people: _people.take(1).toList()));
    for (var i = 4; i < 7; i++) {
      final weekend = istDate(i).weekday >= DateTime.saturday;
      put(i, 'morning', _slot(items: [dishes[i % 3]], people: _people.take(i).toList()));
      put(i, 'evening',
          weekend ? _slot(off: {'type': 'not_needed', 'paid': false, 'note': null}) : _slot(items: [dishes[(i + 1) % 3]]));
    }
  }

  Map<String, dynamic> _home() => {
    'ok': true,
    'member': {'id': 'member-1', 'name': _me},
    'house_name': 'Test House With A Rather Long Name, 2nd Cross, Jayanagar',
    'today': dates.first,
    'days': [
      for (final d in dates)
        {
          'date': d,
          'slots': {'morning': slots['$d|morning'], 'evening': slots['$d|evening']},
        },
    ],
  };

  Future<void> _handle(HttpRequest req) async {
    final fn = req.uri.pathSegments.last;
    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    if (down) {
      // Drop the connection: the app sees "no internet".
      final socket = await req.response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }
    Object reply;
    var status = 200;
    Map<String, dynamic> err(String code, [Map<String, dynamic> details = const {}]) => {
      'ok': false,
      'error': {'code': code, 'message': code, 'details': details},
    };
    switch (fn) {
      case 'member_login':
        final pin = '${body['pin']}';
        if (pin == '0000') {
          reply = err('LOGIN_LOCKED', {'until': _now.add(const Duration(minutes: 15)).toIso8601String()});
        } else if (pin == '1111') {
          reply = err('LOGIN_FAILED');
        } else {
          notMember = false;
          reply = {'ok': true, 'member': {'id': 'member-1', 'name': _me}, 'house_name': 'Test House'};
        }
      case 'member_home':
        if (notMember) {
          status = 401;
          reply = err('NOT_MEMBER');
        } else {
          reply = _home();
        }
      case 'book_meal':
        final key = '${body['date']}|${body['slot']}';
        final s = slots[key]!;
        if (closeOnBook.contains(key)) {
          reply = err('BOOKING_CLOSED', {'cutoff': _now.subtract(const Duration(minutes: 1)).toIso8601String()});
          break;
        }
        final book = body['book'] == true;
        final people = [
          for (final p in (s['bookings']['people'] as List).cast<Map<String, dynamic>>())
            if (p['name'] != _me) p,
        ];
        final note = book ? (body.containsKey('note') ? (('${body['note']}').trim().isEmpty ? null : '${body['note']}'.trim()) : s['note']) : null;
        if (book) people.add({'name': _me, 'note': note});
        s['booked'] = book;
        s['note'] = note;
        s['bookings'] = {'count': people.length, 'people': people};
        reply = {'ok': true, 'date': body['date'], ...s, 'slot': s};
      default:
        reply = err('NOT_FOUND');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250)); // a little network time
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(reply));
    await req.response.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shots = Shots(binding);
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('extreme content, large text, narrow phone and error paths', (t) async {
    final url = Uri.parse(AppConfig.supabaseUrl);
    expect(url.host, '127.0.0.1', reason: 'Run with --dart-define=SUPABASE_URL=http://127.0.0.1:<port>');
    final server = FakeServer();
    await server.start(url);
    addTearDown(server.stop);

    (await SharedPreferences.getInstance()).clear();
    app.main();
    await waitFor(t, find.text('Log in'));
    await settle(t);

    // ---- empty fields / locked ----
    await press(t, find.text('Log in'));
    await waitFor(t, find.text('Please enter your name.'));
    await typeInto(t, find.widgetWithText(TextField, 'Your name'), _me);
    await typeInto(t, find.widgetWithText(TextField, 'PIN'), '12');
    await press(t, find.text('Log in'));
    await waitFor(t, find.text('The PIN is the last 4 digits of your phone number.'));
    await typeInto(t, find.widgetWithText(TextField, 'PIN'), '0000');
    await press(t, find.text('Log in'));
    await waitFor(t, find.textContaining('Too many wrong tries'));
    await settle(t);
    await shots.take(t, 'm01_login_locked');

    // ---- log in ----
    await typeInto(t, find.widgetWithText(TextField, 'PIN'), '2468');
    await press(t, find.text('Log in'));
    await waitFor(t, daySection);
    await settle(t, 1500);
    await shots.take(t, 'm02_home_top');

    // Walk down the whole list, one day at a time.
    for (var i = 0; i < 7; i++) {
      await showDay(t, dayLabel(i));
      await shots.take(t, 'm03_day$i');
    }
    // The leave reason stays private; the holiday note is shown.
    expect(find.textContaining('Private reason'), findsNothing);

    // ---- scrolling back up: the days are already there (no second fade-in) ----
    await t.fling(homeList, const Offset(0, 3000), 4000);
    await t.pump(const Duration(milliseconds: 150));
    await t.pump(const Duration(milliseconds: 150));
    await shots.take(t, 'm03b_scrolled_back_up');
    final faded = [
      for (final e in find.byType(Opacity).evaluate())
        if ((e.widget as Opacity).opacity < 0.99 && find.descendant(of: find.byWidget(e.widget), matching: daySection).evaluate().isNotEmpty)
          (e.widget as Opacity).opacity,
    ];
    expect(faded, isEmpty, reason: 'Day sections fade in again after scrolling back up: $faded');
    await settle(t, 800);

    // ---- everyone's notes ----
    await showDay(t, dayLabel(0));
    final todayEvening = cardsOf(dayLabel(0)).at(1);
    await tapShown(t, find.descendant(of: todayEvening, matching: find.textContaining('eating: ')));
    await waitFor(t, find.byType(BottomSheet));
    await settle(t, 700);
    await shots.take(t, 'm04_eating_sheet');
    await t.drag(find.byType(BottomSheet), const Offset(0, -500), warnIfMissed: false);
    await settle(t, 500);
    await shots.take(t, 'm04b_eating_sheet_scrolled');
    Navigator.of(t.element(find.byType(BottomSheet))).pop();
    await waitFor(t, find.byType(BottomSheet), gone: true);

    // ---- booking closed while the screen was open → rolls back ----
    final day2 = dayLabel(2);
    await showDay(t, day2);
    server.closeOnBook.add('${ymd(istDate(2))}|morning');
    final morning2 = cardsOf(day2).at(0);
    await tapShown(t, find.descendant(of: morning2, matching: find.text('Book morning')));
    await t.pump(const Duration(milliseconds: 60));
    expect(find.descendant(of: morning2, matching: find.text('Booked ✓')), findsOneWidget); // optimistic
    await waitFor(t, find.byType(SnackBar));
    await settle(t, 600);
    expect(find.descendant(of: cardsOf(day2).at(0), matching: find.text('Book morning')), findsOneWidget);
    await shots.take(t, 'm05_booking_closed_rollback');
    await waitFor(t, find.byType(SnackBar), gone: true, timeout: const Duration(seconds: 10));

    // ---- book with a note on a slot with many people ----
    final evening2 = cardsOf(day2).at(1);
    await tapShown(t, find.descendant(of: evening2, matching: find.text('Book evening')));
    await waitFor(t, find.descendant(of: cardsOf(day2).at(1), matching: find.text('Add a note')));
    await tapShown(t, find.descendant(of: cardsOf(day2).at(1), matching: find.text('Add a note')));
    await waitFor(t, find.byType(AlertDialog));
    await typeInto(t, find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '${_longNote}x' * 2);
    await settle(t, 400);
    await shots.take(t, 'm06_note_dialog_long');
    await press(t, find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')));
    await waitFor(t, find.descendant(of: cardsOf(day2).at(1), matching: find.textContaining('Your note: ')));
    await settle(t, 800);
    await showDay(t, day2);
    await shots.take(t, 'm07_booked_long_note');

    // ---- large text (1.5x on a 402 pt wide phone ≈ 1.35x on a 360 dp Android) ----
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    await settle(t, 800);
    await t.drag(homeList, const Offset(0, 6000));
    await settle(t, 600);
    await shots.take(t, 'm08_large_text_top');
    for (final i in [0, 1, 2, 3]) {
      await showDay(t, dayLabel(i));
      await shots.take(t, 'm09_large_text_day$i');
    }
    // The booking time is never cut off ("Book until 9:0…").
    for (final e in find.textContaining(RegExp('^(Book|Cancel) until')).evaluate()) {
      final p = e.renderObject! as RenderParagraph;
      expect(p.didExceedMaxLines, isFalse, reason: 'Cut hint: ${(e.widget as Text).data}');
    }
    await t.tap(find.byTooltip('Menu'));
    await settle(t, 600);
    await shots.take(t, 'm10_large_text_menu');
    await t.tapAt(const Offset(20, 400));
    await settle(t, 500);
    await showDay(t, dayLabel(2));
    await tapShown(t, find.descendant(of: cardsOf(dayLabel(2)).at(1), matching: find.textContaining('eating: ')));
    await waitFor(t, find.byType(BottomSheet));
    await settle(t, 700);
    await shots.take(t, 'm10b_large_text_sheet');
    Navigator.of(t.element(find.byType(BottomSheet))).pop();
    await waitFor(t, find.byType(BottomSheet), gone: true);

    // ---- no connection → saved menu with a banner ----
    server.down = true;
    await t.drag(homeList, const Offset(0, 6000)); // to the top
    await settle(t, 600);
    await t.fling(homeList, const Offset(0, 500), 1500);
    await waitFor(t, find.textContaining("Couldn't refresh"), timeout: const Duration(seconds: 40));
    await settle(t, 800);
    await t.drag(homeList, const Offset(0, 6000));
    await settle(t, 500);
    await shots.take(t, 'm11_offline_banner');
    server.down = false;
    t.platformDispatcher.clearTextScaleFactorTestValue();
    await settle(t, 600);

    // ---- log out ----
    await t.tap(find.byTooltip('Menu'));
    await settle(t, 600);
    await t.tap(find.text('Log out'));
    await waitFor(t, find.byType(AlertDialog));
    await settle(t, 400);
    await shots.take(t, 'm12_logout_confirm');
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Log out')));
    await waitFor(t, find.text('Log in'));
    await settle(t);
    expect(find.text(_me), findsOneWidget); // name kept for the next login
    await shots.take(t, 'm13_after_logout');

    // ---- the owner resets the login while the app is open ----
    await typeInto(t, find.widgetWithText(TextField, 'PIN'), '2468');
    await press(t, find.text('Log in'));
    await waitFor(t, daySection);
    await settle(t, 800);
    server.notMember = true;
    await t.tap(find.byTooltip('Menu'));
    await settle(t, 500);
    await t.tap(find.text('Refresh'));
    await waitFor(t, find.textContaining('Your login was reset'));
    await settle(t);
    await shots.take(t, 'm14_login_reset');

    (await SharedPreferences.getInstance()).clear();
  });
}
