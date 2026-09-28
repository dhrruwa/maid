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

  /// t('hello', {'name': 'Lakshmi'})
  static String t(String key, [Map<String, Object?> params = const {}]) {
    var s = _strings[lang.value]?[key] ?? _strings['en']?[key] ?? key;
    params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  static bool has(String key) => _strings['en']?.containsKey(key) ?? false;

  static String slot(String s) => t(s == 'morning' ? 'morning' : s == 'evening' ? 'evening' : 'full_day');

  // Dates in the chosen language ("30 ಸೆಪ್ಟೆಂ" / "30 Sep").
  static String shortDate(String ymd) => DateFormat('d MMM', code).format(DateTime.parse(ymd));
  static String longDate(String ymd) => DateFormat('EEEE, d MMM', code).format(DateTime.parse(ymd));
  static String monthName(String ym) => DateFormat('MMMM', code).format(DateTime.parse('$ym-01'));
  static String monthYear(String ym) => DateFormat('MMMM yyyy', code).format(DateTime.parse('$ym-01'));
  static String time(String iso) =>
      DateFormat('h:mm a', code).format(DateTime.parse(iso).toUtc().add(const Duration(hours: 5, minutes: 30)));
}
