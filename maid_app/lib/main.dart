import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'core/device.dart';
import 'core/i18n.dart';
import 'core/offline_queue.dart';
import 'core/push.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/pairing_screen.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Device.init();
  await L.init();
  if (AppConfig.supabaseConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  }
  await Push.init();

  Push.foreground.listen((m) {
    final n = m.notification;
    if (n == null) return;
    messengerKey.currentState?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Text('${n.title ?? ''}\n${n.body ?? ''}'.trim(), style: const TextStyle(fontSize: 16)),
    ));
    HomeScreen.refreshAll();
  });

  if (AppConfig.supabaseConfigured && Device.paired) {
    OfflineQueue.start();
    Push.syncDevice();
  }
  runApp(const CookApp());
}

class CookApp extends StatelessWidget {
  const CookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: L.lang,
      builder: (context, lang, _) => MaterialApp(
        title: 'Cook Attendance',
        debugShowCheckedModeBanner: false,
        navigatorKey: navKey,
        scaffoldMessengerKey: messengerKey,
        theme: buildTheme(),
        themeMode: ThemeMode.light,
        home: !AppConfig.supabaseConfigured
            ? Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(L.t('new_version_needed')))))
            : Device.paired
                ? const HomeScreen()
                : const PairingScreen(),
      ),
    );
  }
}
