import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This phone's identity (a random secret ID) and the local PIN.
class Device {
  static const _idKey = 'device_id';
  static const _pinKey = 'pin_hash';
  static const _setupKey = 'setup_done';

  static late SharedPreferences prefs;
  static late String id;

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    var v = prefs.getString(_idKey);
    if (v == null) {
      final r = Random.secure();
      v = 'own-${List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join()}';
      await prefs.setString(_idKey, v);
    }
    id = v;
  }

  static String hashPin(String pin) =>
      sha256.convert(utf8.encode('cook-dashboard-pin:$pin')).toString();

  static String? get pinHash => prefs.getString(_pinKey);
  static Future<void> savePinHash(String h) => prefs.setString(_pinKey, h);
  static bool checkPin(String pin) => hashPin(pin) == pinHash;

  static bool get setupDone => prefs.getBool(_setupKey) ?? false;
  static Future<void> markSetupDone() => prefs.setBool(_setupKey, true);

  /// Used after restoring with a recovery key: adopt the new identity.
  static Future<void> replaceId(String newId) async {
    id = newId;
    await prefs.setString(_idKey, newId);
  }
}
