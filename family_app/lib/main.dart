import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'core/api.dart';
import 'core/device.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Device.init();
  if (AppConfig.supabaseConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  }
  // The owner removed this member or reset their PIN: back to the login.
  Api.signedOut.addListener(_backToLogin);
  runApp(const FamilyApp());
}

Future<void> _backToLogin() async {
  if (!Device.loggedIn) return;
  final name = Device.name;
  await Device.clearLogin();
  ApiCache.clear();
  navKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => LoginScreen(name: name, notice: 'Your login was reset. Please log in again.')),
    (_) => false,
  );
}

class FamilyApp extends StatelessWidget {
  const FamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family',
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      theme: buildTheme(),
      themeMode: ThemeMode.light,
      home: Device.loggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
