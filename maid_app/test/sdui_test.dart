import 'package:cook_attendance/core/device.dart';
import 'package:cook_attendance/core/i18n.dart';
import 'package:cook_attendance/sdui/blocks.dart';
import 'package:cook_attendance/sdui/server_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'name': 'Lakshmi', 'lang': 'en'});
    await Device.init();
    await L.init();
    ServerUi.reset();
  });

  group('UiBlock', () {
    test('skips anything that is not {"type": …}', () {
      final blocks = UiBlock.list([
        {'type': 'notice', 'text': 'Hi'},
        'text',
        {'text': 'no type'},
        {'type': 3},
        null,
        {'type': 'spacer'},
      ]);
      expect(blocks.map((b) => b.type), ['notice', 'spacer']);
      expect(UiBlock.list('not a list'), isEmpty);
    });

    test('finds a block inside a row or card', () {
      final blocks = UiBlock.list([
        {
          'type': 'card',
          'children': [
            {
              'type': 'row',
              'children': [
                {'type': 'scan_button'},
              ],
            },
          ],
        },
      ]);
      expect(UiBlock.contains(blocks, 'scan_button'), isTrue);
      expect(UiBlock.contains(blocks, 'salary_card'), isFalse);
    });

    test('from / until dates are India dates, until includes the whole day', () {
      final b = UiBlock('notice', {'from': '2026-10-20', 'until': '2026-10-22'});
      // 19 Oct 18:29 UTC = 19 Oct 23:59 IST; 18:30 UTC = 20 Oct 00:00 IST.
      expect(b.visibleAt(DateTime.utc(2026, 10, 19, 18, 29)), isFalse);
      expect(b.visibleAt(DateTime.utc(2026, 10, 19, 18, 30)), isTrue);
      expect(b.visibleAt(DateTime.utc(2026, 10, 22, 18, 29)), isTrue);
      expect(b.visibleAt(DateTime.utc(2026, 10, 22, 18, 30)), isFalse);
    });

    test('from / until exact times, and hidden', () {
      final b = UiBlock('notice', {'from': '2026-10-20T18:00:00+05:30', 'until': '2026-10-20T20:00:00+05:30'});
      expect(b.visibleAt(DateTime.utc(2026, 10, 20, 12, 29)), isFalse);
      expect(b.visibleAt(DateTime.utc(2026, 10, 20, 12, 30)), isTrue);
      expect(b.visibleAt(DateTime.utc(2026, 10, 20, 14, 30)), isFalse);
      expect(UiBlock('notice', {'hidden': true}).visibleAt(DateTime.now()), isFalse);
      expect(UiBlock('notice', {'from': 'garbage'}).visibleAt(DateTime.now()), isTrue);
    });

    test('only known actions and safe links are tappable', () {
      expect(UiBlock('button', {'action': 'history'}).action, 'history');
      expect(UiBlock('button', {'action': 'tel:+919999999999'}).action, 'tel:+919999999999');
      expect(UiBlock('button', {'action': 'https://wa.me/919999999999'}).action, isNotNull);
      expect(UiBlock('button', {'action': 'histroy'}).action, isNull);
      expect(UiBlock('button', {'action': 'javascript:alert(1)'}).action, isNull);
      expect(UiBlock('button', {'action': 'https:'}).action, isNull);
      expect(UiBlock('button', {'action': 42}).action, isNull);
    });
  });

  group('uiText', () {
    test('plain, per language, app string key, {name}', () async {
      expect(uiText('Hello {name}'), 'Hello Lakshmi');
      expect(uiText({'en': 'Hi', 'kn': 'ನಮಸ್ಕಾರ'}), 'Hi');
      expect(uiText({'key': 'scan_qr'}), L.t('scan_qr'));
      await L.setLang('kn');
      expect(uiText({'en': 'Hi', 'kn': 'ನಮಸ್ಕಾರ'}), 'ನಮಸ್ಕಾರ');
      expect(uiText({'en': 'Hi', 'kn': '  '}), 'Hi'); // no Kannada yet → English
      expect(uiText({'en': 'Hi'}), 'Hi');
      expect(uiText({'key': 'scan_qr'}), L.t('scan_qr')); // the Kannada app string
      expect(uiText(''), isNull);
      expect(uiText(12), isNull);
      expect(uiText({'fr': 'Salut'}), isNull);
    });
  });

  group('ServerUi', () {
    test('built-in Home until the server sends one', () {
      final types = ServerUi.blocks('home', required: {'scan_button'}).map((b) => b.type).toList();
      expect(types, containsAllInOrder(['salary_card', 'scan_button', 'cook_card', 'more_buttons']));
    });

    test("uses the server's Home, and falls back when it has no Scan QR", () {
      ServerUi.debugApply({
        'screens': {
          'home': {
            'blocks': [
              {'type': 'notice', 'text': 'Diwali'},
              {'type': 'scan_button'},
            ],
          },
        },
      });
      expect(ServerUi.blocks('home', required: {'scan_button'}).map((b) => b.type), ['notice', 'scan_button']);

      ServerUi.debugApply({
        'screens': {
          'home': {
            'blocks': [
              {'type': 'notice', 'text': 'oops'},
            ],
          },
        },
      });
      expect(
        ServerUi.blocks('home', required: {'scan_button'}).map((b) => b.type),
        contains('salary_card'),
      );
    });

    test('text overrides change the app strings, per language, and go away with the bundle', () async {
      final builtIn = L.t('scan_qr');
      final builtInKn = (await () async {
        await L.setLang('kn');
        final v = L.t('scan_qr');
        await L.setLang('en');
        return v;
      }());
      expect(
        ServerUi.debugApply({
          'strings': {
            'en': {'scan_qr': 'Scan kitchen QR', 'brand_new': 'New text'},
            'kn': {'brand_new': 'ಹೊಸ'},
          },
        }),
        isTrue,
      );
      expect(L.t('scan_qr'), 'Scan kitchen QR');
      expect(L.has('brand_new'), isTrue);
      await L.setLang('kn');
      expect(L.t('scan_qr'), builtInKn); // the built-in Kannada still wins over English
      expect(L.t('brand_new'), 'ಹೊಸ');
      await L.setLang('en');

      expect(ServerUi.debugApply(null), isTrue);
      expect(L.t('scan_qr'), builtIn);
      expect(ServerUi.debugApply(null), isFalse); // unchanged
    });
  });

  group('UiRenderer', () {
    Future<void> pump(WidgetTester tester, List<Object?> blocks, {Map<String, UiBuilder> screen = const {}}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ListView(
              children: UiRenderer(screen).build(context, UiBlock.list(blocks)),
            ),
          ),
        ),
      ));
    }

    testWidgets('general blocks; unknown, broken and expired ones are left out', (tester) async {
      await pump(tester, [
        {'type': 'notice', 'icon': 'celebration', 'tone': 'success', 'title': 'Happy Diwali, {name}!', 'text': 'Paid holiday'},
        {'type': 'from_the_future', 'text': 'x'},
        {'type': 'text', 'text': {'en': 'Hello', 'kn': 'ನಮಸ್ಕಾರ'}, 'size': 999},
        {'type': 'button', 'label': 'Call owner', 'icon': 'phone', 'action': 'tel:+919999999999'},
        {'type': 'button', 'label': 'Goes nowhere', 'action': 'nowhere'},
        {'type': 'notice', 'text': 'Old news', 'until': '2020-01-01'},
        {'type': 'notice'},
        {'type': 'image', 'url': 'http://insecure.example/x.png'},
        {'type': 'video', 'url': 'https://example.com/not-youtube'},
        {'type': 'mine', 'text': 'custom'},
      ], screen: {
        'mine': (_, b) => Text('custom: ${b.text('text')}'),
      });

      expect(find.text('Happy Diwali, Lakshmi!'), findsOneWidget);
      expect(find.byIcon(Icons.celebration_rounded), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Hello')).style!.fontSize, 40); // clamped
      expect(find.text('Call owner'), findsOneWidget);
      expect(find.text('Goes nowhere'), findsNothing);
      expect(find.text('Old news'), findsNothing);
      expect(find.text('custom: custom'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a block whose builder throws is left out, the rest still show', (tester) async {
      await pump(tester, [
        {'type': 'boom'},
        {'type': 'text', 'text': 'Still here'},
      ], screen: {
        'boom': (_, _) => throw StateError('bad data'),
      });
      expect(find.text('Still here'), findsOneWidget);
    });

    testWidgets('card with a title and a row of buttons', (tester) async {
      await pump(tester, [
        {
          'type': 'card',
          'title': 'Help',
          'icon': 'help',
          'children': [
            {
              'type': 'row',
              'children': [
                {'type': 'button', 'label': 'Leave', 'action': 'leave'},
                {'type': 'button', 'label': 'History', 'action': 'history'},
              ],
            },
          ],
        },
        {'type': 'card'}, // empty: nothing
      ]);
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
    });
  });
}
