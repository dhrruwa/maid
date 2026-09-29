import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// This phone's secret device ID and the family member logged in on it.
/// The login is kept until the member logs out or the owner removes them /
/// resets their PIN (the server then answers NOT_MEMBER).
class Device {
  static late SharedPreferences prefs;
  static late String id;

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    id = prefs.getString('device_id') ?? await _newId();
  }

  static Future<String> _newId() async {
    final r = Random.secure();
    final v = 'family-${List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join()}';
    await prefs.setString('device_id', v);
    return v;
  }

  static bool get loggedIn => prefs.getString('member_id') != null;
  static String get name => prefs.getString('member_name') ?? '';
  static String get houseName => prefs.getString('house_name') ?? '';

  static Future<void> saveLogin({required String memberId, required String name, required String houseName}) async {
    await prefs.setString('member_id', memberId);
    await prefs.setString('member_name', name);
    await prefs.setString('house_name', houseName);
  }

  static Future<void> setName(String v) => prefs.setString('member_name', v);
  static Future<void> setHouseName(String v) => prefs.setString('house_name', v);

  /// Forget the login on this phone. A fresh device ID means the old link on
  /// the server can never be used from here again.
  static Future<void> clearLogin() async {
    await prefs.remove('member_id');
    await prefs.remove('member_name');
    await prefs.remove('house_name');
    id = await _newId();
  }
}
