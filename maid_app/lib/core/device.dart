import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// This phone's secret device ID, the cook's name, language and pairing state.
class Device {
  static late SharedPreferences prefs;
  static late String id;

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    var v = prefs.getString('device_id');
    if (v == null) {
      final r = Random.secure();
      v = 'cook-${List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join()}';
      await prefs.setString('device_id', v);
    }
    id = v;
  }

  static bool get paired => prefs.getBool('paired') ?? false;
  static Future<void> setPaired(bool v) => prefs.setBool('paired', v);

  static String get name => prefs.getString('name') ?? '';
  static Future<void> setName(String v) => prefs.setString('name', v);

  static String get lang => prefs.getString('lang') ?? 'en';
  static Future<void> setLang(String v) => prefs.setString('lang', v);
}
