import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'device.dart';

/// House, settings and paired maid phone, cached so the app opens offline.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState i = AppState._();

  Map<String, dynamic> house = {};
  Map<String, dynamic> settings = {};
  Map<String, dynamic>? cook;

  /// Bumped whenever data changes so open screens reload.
  int version = 0;

  void loadCache() {
    final raw = Device.prefs.getString('house_cache');
    if (raw == null) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    house = Map<String, dynamic>.from(m['house'] ?? {});
    settings = Map<String, dynamic>.from(m['settings'] ?? {});
    cook = m['cook'] == null ? null : Map<String, dynamic>.from(m['cook']);
  }

  void apply(Map<String, dynamic> r) {
    if (r['house'] != null) house = Map<String, dynamic>.from(r['house']);
    if (r['settings'] != null) settings = Map<String, dynamic>.from(r['settings']);
    if (r.containsKey('cook')) cook = r['cook'] == null ? null : Map<String, dynamic>.from(r['cook']);
    Device.prefs.setString('house_cache', jsonEncode({'house': house, 'settings': settings, 'cook': cook}));
    notifyListeners();
  }

  Future<void> refresh() async => apply(await Api.call('get_house'));

  void changed() {
    version++;
    notifyListeners();
  }

  String get houseQrPayload => 'CDHOUSE:${house['qr_token'] ?? ''}';
}
