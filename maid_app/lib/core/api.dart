import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

import 'device.dart';
import 'i18n.dart';

class ApiError implements Exception {
  ApiError(this.code, this.message, [this.details = const {}]);
  final String code;
  final String message;
  final Map<String, dynamic> details;

  bool get isNetwork => code == 'NETWORK';

  /// Simple, translated reason for the cook.
  String get friendly {
    switch (code) {
      case 'NOT_AT_HOUSE':
        return L.t('err_NOT_AT_HOUSE');
      case 'EVENING_NOT_NEEDED':
        return L.t('err_EVENING_NOT_NEEDED', {
          'day': L.t(details['day'] == 'Sunday' ? 'sunday' : 'saturday'),
        });
      case 'ALREADY_MARKED':
        return L.t('err_ALREADY_MARKED', {'slot': L.slot('${details['slot']}')});
      case 'MORNING_OVER':
      case 'EVENING_OVER':
        return L.t('err_$code', {'window': details['window'] ?? ''});
      case 'TOO_EARLY':
        return L.t('err_TOO_EARLY', {'opens': details['opens'] ?? ''});
    }
    final key = 'err_$code';
    return L.has(key) ? L.t(key) : (message.isNotEmpty ? message : L.t('err_GENERIC'));
  }

  /// Extra line under the reason (e.g. how far away she is).
  String? get detail {
    if (code == 'NOT_AT_HOUSE' && details['distance_m'] != null) {
      return L.t('err_NOT_AT_HOUSE_detail', {'distance': details['distance_m'], 'radius': details['radius_m']});
    }
    return null;
  }

  @override
  String toString() => friendly;
}

/// Calls a Supabase Edge Function with this phone's device ID.
class Api {
  static Future<Map<String, dynamic>> call(String fn, [Map<String, dynamic> body = const {}]) async {
    final payload = {...body, 'device_id': Device.id};
    try {
      if (AppConfig.supabaseConfigured) {
        final res = await Supabase.instance.client.functions
            .invoke(fn, body: payload, region: _region)
            .timeout(_timeout);
        return _unwrap(res.data);
      }
      // No anon key configured yet: the functions check the device ID themselves,
      // so they can be called directly.
      final res = await _http
          .post(
            Uri.parse('${AppConfig.supabaseUrl}/functions/v1/$fn'),
            headers: {'Content-Type': 'application/json', 'x-region': ?_region},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      return _unwrap(jsonDecode(utf8.decode(res.bodyBytes)));
    } on FunctionException catch (e) {
      return _unwrap(e.details);
    } on ApiError {
      rethrow;
    } on FormatException {
      throw ApiError('SERVER_ERROR', 'Unexpected reply from the server');
    } catch (_) {
      throw ApiError('NETWORK', '');
    } finally {
      // Something may have changed (a scan, a leave request, pairing…): later
      // reads must not join a request that started before it, and replies to
      // those older requests must not be saved over newer ones.
      if (!fn.startsWith('get_') && !fn.startsWith('list_')) {
        _inFlight.clear();
        ApiCache.epoch++;
      }
    }
  }

  /// The last saved reply of [fetch] for [fn] + [body], or null. Instant.
  static Map<String, dynamic>? cached(String fn, [Map<String, dynamic> body = const {}]) => ApiCache.read(fn, body);

  /// Like [call], and saves the reply so [cached] can show it next time.
  /// The same call already on its way is shared instead of sent twice.
  static Future<Map<String, dynamic>> fetch(String fn, [Map<String, dynamic> body = const {}]) {
    final key = ApiCache.keyFor(fn, body);
    final running = _inFlight[key];
    if (running != null) return running;
    final epoch = ApiCache.epoch;
    late final Future<Map<String, dynamic>> f;
    f = call(fn, body).then((r) {
      // Sent before a change or a re-pair: may be out of date, don't save it.
      if (epoch == ApiCache.epoch) ApiCache.write(fn, body, r);
      return r;
    }).whenComplete(() {
      if (identical(_inFlight[key], f)) _inFlight.remove(key);
    });
    _inFlight[key] = f;
    return f;
  }

  static final _inFlight = <String, Future<Map<String, dynamic>>>{};

  /// Run the functions next to the database (null = nearest edge).
  static final String? _region = AppConfig.functionRegion.isEmpty ? null : AppConfig.functionRegion;

  static const _timeout = Duration(seconds: 30);
  static final _http = http.Client();

  static Map<String, dynamic> _unwrap(dynamic data) {
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      if (m['ok'] == true) return m;
      final err = m['error'];
      if (err is Map) {
        final e = ApiError(
          '${err['code'] ?? 'ERROR'}',
          '${err['message'] ?? ''}',
          Map<String, dynamic>.from((err['details'] as Map?) ?? {}),
        );
        if (e.code == 'NOT_PAIRED') Device.setPaired(false);
        throw e;
      }
    }
    throw ApiError('GENERIC', '');
  }
}

/// Last good replies of read-only calls, kept in shared_preferences (per
/// device, function and body) so screens can show them instantly and refresh
/// behind. Only a few replies per function are kept, oldest dropped first.
class ApiCache {
  static const _prefix = 'api_cache:';
  static const _indexKey = 'api_cache_index';
  static const _keep = {'get_menu': 10, 'get_month_summary': 6, 'get_timeline': 2};
  static const _keepDefault = 2;

  /// Goes up after every change and every [clear]; [Api.fetch] only saves a
  /// reply when it is unchanged since the request was sent.
  static int epoch = 0;

  static String keyFor(String fn, Map<String, dynamic> body) {
    final keys = body.keys.toList()..sort();
    return '$_prefix${Device.id}:$fn:${jsonEncode({for (final k in keys) k: body[k]})}';
  }

  static Map<String, dynamic>? read(String fn, [Map<String, dynamic> body = const {}]) {
    try {
      final raw = Device.prefs.getString(keyFor(fn, body));
      return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// Saves [data]. shared_preferences updates its memory copy at once, so the
  /// disk writes are not awaited (and are skipped when nothing changed).
  static void write(String fn, Map<String, dynamic> body, Map<String, dynamic> data) {
    try {
      final key = keyFor(fn, body);
      final raw = jsonEncode(data);
      final prefs = Device.prefs;
      if (prefs.getString(key) == raw) return;
      prefs.setString(key, raw).ignore();
      final index = _index();
      final list = index[fn] ?? <String>[];
      if (list.contains(key)) return;
      list.add(key);
      final limit = _keep[fn] ?? _keepDefault;
      while (list.length > limit) {
        prefs.remove(list.removeAt(0)).ignore();
      }
      index[fn] = list;
      prefs.setString(_indexKey, jsonEncode(index)).ignore();
    } catch (_) {
      // A cache that can't be written just means a spinner next time.
    }
  }

  /// Forget everything (e.g. after pairing with a different house).
  static void clear() {
    epoch++;
    final prefs = Device.prefs;
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      prefs.remove(k).ignore();
    }
    prefs.remove(_indexKey).ignore();
  }

  static Map<String, List<String>> _index() {
    try {
      final raw = Device.prefs.getString(_indexKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', [for (final e in v as List) '$e']));
    } catch (_) {
      return {};
    }
  }
}
