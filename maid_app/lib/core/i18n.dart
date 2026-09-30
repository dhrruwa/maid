import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'device.dart';

/// English + Kannada strings from assets/i18n/*.json.
class L {
  static final lang = ValueNotifier<String>('en');
  static final _strings = <String, Map<String, String>>{};

  static Future<void> init() async {
    for (final code in ['en', 'kn']) {
      final raw = await rootBundle.loadString('assets/i18n/$code.json');
      _strings[code] = Map<String, String>.from(jsonDecode(raw));
    }
    await initializeDateFormatting('en');
    await initializeDateFormatting('kn');
    lang.value = Device.lang;
  }

  static Future<void> setLang(String code) async {
    lang.value = code;
    await Device.setLang(code);
  }

  static String get code => lang.value;
  static bool get isKannada => lang.value == 'kn';

  /// Text the owner or family typed (a dish name, a note). In Kannada the
  /// server's Kannada copy (`name` → `name_kn`) is shown when there is one.
  static String typed(Object? m, String key) {
    if (m is! Map) return '';
    final kn = m['${key}_kn'];
    if (isKannada && kn is String && kn.trim().isNotEmpty) return kn.trim();
    final v = m[key];
    return v == null ? '' : '$v'.trim();
  }

  /// Text overrides from the server (ServerUi), {"en": {key: text}, "kn": …}:
  /// fix or change the app's wording without a new build.
  static final _server = <String, Map<String, String>>{};

  static void setOverrides(Object? strings) {
    _server.clear();
    if (strings is! Map) return;
    strings.forEach((code, m) {
      if (m is Map) {
        _server['$code'] = {
          for (final e in m.entries)
            if (e.value is String && (e.value as String).trim().isNotEmpty) '${e.key}': e.value as String,
        };
      }
    });
  }

  static String? _find(String code, String key) => _server[code]?[key] ?? _strings[code]?[key];

  /// t('hello', {'name': 'Lakshmi'})
  static String t(String key, [Map<String, Object?> params = const {}]) {
    var s = _find(lang.value, key) ?? _find('en', key) ?? key;
    params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  static bool has(String key) => _find('en', key) != null;

  static String slot(String s) => t(s == 'morning' ? 'morning' : s == 'evening' ? 'evening' : 'full_day');

  // Dates in the chosen language ("30 ಸೆಪ್ಟೆಂ" / "30 Sep").
  static String shortDate(String ymd) => DateFormat('d MMM', code).format(DateTime.parse(ymd));
  static String longDate(String ymd) => DateFormat('EEEE, d MMM', code).format(DateTime.parse(ymd));
  static String monthName(String ym) => DateFormat('MMMM', code).format(DateTime.parse('$ym-01'));
  static String monthYear(String ym) => DateFormat('MMMM yyyy', code).format(DateTime.parse('$ym-01'));
  static String time(String iso) =>
      DateFormat('h:mm a', code).format(DateTime.parse(iso).toUtc().add(const Duration(hours: 5, minutes: 30)));
}
