import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'device.dart';

class ApiError implements Exception {
  ApiError(this.code, this.message, [this.details = const {}]);
  final String code;
  final String message;
  final Map<String, dynamic> details;

  bool get isNetwork => code == 'NETWORK';

  /// Simple, friendly reason for the family member.
  String get friendly {
    switch (code) {
      case 'NETWORK':
        return 'No internet connection. Please check it and try again.';
      case 'LOGIN_FAILED':
        return "That name and PIN don't match. Check how your name is spelled and use the last 4 digits of your phone number.";
      case 'LOGIN_LOCKED':
        final until = istTime(details['until']);
        return until == null
            ? 'Too many wrong tries. Please wait 15 minutes and try again.'
            : 'Too many wrong tries. Please try again after $until.';
      case 'NOT_MEMBER':
        return 'Please log in again.';
      case 'BOOKING_CLOSED':
        final cutoff = istTime(details['cutoff']);
        return cutoff == null ? 'Booking has closed for this meal.' : 'Booking closed at $cutoff for this meal.';
      case 'SLOT_OFF':
        return 'No meal is being cooked then.';
      case 'BAD_DATE':
        return 'That day can no longer be booked.';
      case 'SERVER_ERROR':
        return 'Something went wrong. Please try again.';
    }
    return message.isNotEmpty ? message : 'Something went wrong. Please try again.';
  }

  @override
  String toString() => friendly;
}

/// "3:00 PM" in India time for an ISO timestamp, or null.
String? istTime(dynamic iso) {
  if (iso == null) return null;
  final t = DateTime.tryParse('$iso');
  if (t == null) return null;
  return DateFormat('h:mm a').format(t.toUtc().add(const Duration(hours: 5, minutes: 30)));
}

/// Calls a Supabase Edge Function with this phone's device ID.
class Api {
  /// Told when the server no longer knows this phone (member removed or PIN
  /// reset): the app then goes back to the login screen.
  static final signedOut = ValueNotifier<int>(0);

  /// Read-only functions: their replies can be saved and shown next time.
  static bool _isRead(String fn) => fn == 'member_home' || fn.startsWith('get_') || fn.startsWith('list_');

  static Future<Map<String, dynamic>> call(String fn, [Map<String, dynamic> body = const {}]) async {
    final payload = {...body, 'device_id': Device.id};
    try {
      if (AppConfig.supabaseConfigured) {
        final res = await Supabase.instance.client.functions
            .invoke(fn, body: payload, region: _region)
            .timeout(_timeout);
        return _unwrap(res.data);
      }
      // No anon key configured: the functions check the device ID themselves,
      // so they can be called directly.
      final res = await _http
          .post(
            Uri.parse('${AppConfig.supabaseUrl}/functions/v1/$fn'),
            headers: {'Content-Type': 'application/json', 'x-region': ?_region},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      return _unwrap(jsonDecode(utf8.decode(res.bodyBytes)));
    } on FunctionsFetchException {
      // Never reached the server (offline, DNS, TLS...): a network error, not a
      // bad reply. It is a FunctionException too, so it must be caught first.
      throw ApiError('NETWORK', '');
    } on FunctionException catch (e) {
      return _unwrap(e.details);
    } on ApiError {
      rethrow;
    } on FormatException {
      throw ApiError('SERVER_ERROR', 'Unexpected reply from the server');
    } catch (_) {
      throw ApiError('NETWORK', '');
    } finally {
      // A booking changed something: later reads must not join a request that
      // started before it, and older replies must not be saved over newer ones.
      if (!_isRead(fn)) {
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
      // Sent before a booking or a logout: may be out of date, don't save it.
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
        if (e.code == 'NOT_MEMBER' && Device.loggedIn) signedOut.value++;
        throw e;
      }
    }
    throw ApiError('SERVER_ERROR', '');
  }
}

/// Last good replies of read-only calls, kept in shared_preferences (per
/// device, function and body) so screens can show them instantly and refresh
/// behind. Only a few replies per function are kept, oldest dropped first.
class ApiCache {
  static const _prefix = 'api_cache:';
  static const _indexKey = 'api_cache_index';
  static const _keep = 2;

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
      while (list.length > _keep) {
        prefs.remove(list.removeAt(0)).ignore();
      }
      index[fn] = list;
      prefs.setString(_indexKey, jsonEncode(index)).ignore();
    } catch (_) {
      // A cache that can't be written just means a spinner next time.
    }
  }

  /// Forget everything (after logging in or out).
  static void clear() {
    epoch++;
    Api._inFlight.clear();
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
