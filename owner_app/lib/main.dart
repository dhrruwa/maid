import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'core/app_state.dart';
import 'core/device.dart';
import 'core/push.dart';
import 'core/theme.dart';
import 'screens/lock_screen.dart';
import 'screens/setup/setup_flow.dart';
import 'screens/shell.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Device.init();
  if (AppConfig.supabaseConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  }
  await Push.init();
  AppState.i.loadCache();

  // Foreground pushes: show as a snackbar and refresh open screens.
  Push.foreground.listen((m) {
    final n = m.notification;
    if (n != null) {
      messengerKey.currentState?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${n.title ?? ''}\n${n.body ?? ''}'.trim()),
      ));
    }
    AppState.i.changed();
  });

  runApp(const OwnerApp());
}

class OwnerApp extends StatelessWidget {
  const OwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cook Dashboard',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: AppConfig.supabaseConfigured ? const Root() : const _MissingKeys(),
    );
  }
}

/// Setup → PIN lock → app. Locks again after 2 minutes in the background.
class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> with WidgetsBindingObserver {
  bool _unlocked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (s == AppLifecycleState.resumed) {
      if (_pausedAt != null && DateTime.now().difference(_pausedAt!) > const Duration(minutes: 2)) {
        setState(() => _unlocked = false);
      }
      AppState.i.changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Device.setupDone) {
      return SetupFlow(onDone: () => setState(() => _unlocked = true));
    }
    if (!_unlocked) {
      return LockScreen(onUnlocked: () {
        setState(() => _unlocked = true);
        Push.syncToken();
      });
    }
    return const Shell();
  }
}

class _MissingKeys extends StatelessWidget {
  const _MissingKeys();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Supabase key missing.\n\nOpen lib/config.dart and paste your Supabase anon key, '
            'then build the app again (see docs/SETUP_GUIDE.md).',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
