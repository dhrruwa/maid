import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

import 'device.dart';

class ApiError implements Exception {
  ApiError(this.code, this.message, [this.details = const {}]);
  final String code;
  final String message;
  final Map<String, dynamic> details;

  bool get isNetwork => code == 'NETWORK';

  @override
  String toString() => message;
}

/// Calls a Supabase Edge Function. Every call carries this phone's device ID.
///
/// Reads that screens show go through [read]: the reply is also saved on the
/// phone, so next time the screen opens it shows [cached] at once and refreshes
/// in the background (stale-while-revalidate).
class Api {
  /// Any call, typically a change (mark paid, holiday, ...). Nothing is saved,
  /// and reads started before it finished are not reused afterwards.
  static Future<Map<String, dynamic>> call(String fn, [Map<String, dynamic> body = const {}]) async {
    try {
      return await _send(fn, body);
    } finally {
      invalidate();
    }
  }

  /// A read whose reply is saved for [cached]. [key] replaces the body in the
  /// saved copy's name, for reads whose body moves every day (e.g. "the last 7 days").
  /// The same read already on its way is shared instead of being sent twice.
  static Future<Map<String, dynamic>> read(String fn, {Map<String, dynamic> body = const {}, String? key}) {
    final k = _cacheKey(fn, body, key);
    final running = _inflight[k];
    if (running != null && running.gen == _gen) return running.reply;

    final seq = ++_seq;
    final reply = _send(fn, body).then((r) {
      final newer = _newest[k];
      // A read started later already came back: its reply is the fresher one.
      if (newer != null && newer.seq > seq) return newer.reply;
      _newest[k] = (seq: seq, reply: r);
      _save(k, r);
      return r;
    }, onError: (Object e, StackTrace st) {
      // This phone is no longer the owner (moved with the recovery key): drop
      // the saved copies so the house's data is not shown on it again.
      if (e is ApiError && e.code == 'NOT_OWNER') clearSaved();
      // An older read failing after a newer one came back must not turn the
      // fresh data into an error.
      final newer = _newest[k];
      if (newer != null && newer.seq > seq) return newer.reply;
      Error.throwWithStackTrace(e, st);
    });
    _inflight[k] = (gen: _gen, reply: reply);
    reply.whenComplete(() {
      if (identical(_inflight[k]?.reply, reply)) _inflight.remove(k);
    }).ignore();
    return reply;
  }

  /// The last saved reply of [read] with the same arguments, or null.
  static Map<String, dynamic>? cached(String fn, {Map<String, dynamic> body = const {}, String? key}) {
    try {
      final raw = Device.prefs.getString(_cacheKey(fn, body, key));
      if (raw == null) return null;
      final m = jsonDecode(raw);
      return m is Map<String, dynamic> ? m : null;
    } catch (_) {
      return null;
    }
  }

  /// Fire-and-forget [read]s that fill the saved copies so other tabs open instantly.
  static void prefetch(List<(String, Map<String, dynamic>)> reads) {
    for (final (fn, body) in reads) {
      read(fn, body: body).ignore();
    }
  }

  /// Data changed (here or on the maid's phone): later reads go to the server
  /// instead of joining ones already on their way.
  static void invalidate() => _gen++;

  /// Forgets every saved reply (on this phone and in memory).
  static void clearSaved() {
    _newest.clear();
    invalidate();
    try {
      final prefs = Device.prefs;
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        prefs.remove(k).ignore();
      }
      prefs.remove(_indexKey).ignore();
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> _send(String fn, Map<String, dynamic> body) async {
    final payload = {...body, 'device_id': Device.id};
    final region = AppConfig.functionRegion;
    final pinRegion = region.isNotEmpty && region != 'any';
    try {
      if (AppConfig.supabaseConfigured) {
        // `region` adds the x-region header (and forceFunctionRegion) so the
        // function runs next to the database.
        final res = await Supabase.instance.client.functions
            .invoke(fn, body: payload, region: pinRegion ? region : null)
            .timeout(_timeout);
        return _unwrap(res.data);
      }
      // No anon key configured yet: the functions check the device ID themselves,
      // so they can be called directly.
      final res = await _http
          .post(
            Uri.parse('${AppConfig.supabaseUrl}/functions/v1/$fn')
                .replace(queryParameters: pinRegion ? {'forceFunctionRegion': region} : null),
            headers: {
              'Content-Type': 'application/json',
              if (pinRegion) 'x-region': region,
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      return _unwrap(jsonDecode(utf8.decode(res.bodyBytes)));
    } on FunctionsFetchException {
      // Never reached the server (offline, DNS, TLS...): a network error, not a bad reply.
      throw ApiError('NETWORK', 'No internet connection. Please try again.');
    } on FunctionException catch (e) {
      return _unwrap(e.details);
    } on ApiError {
      rethrow;
    } on FormatException {
      throw ApiError('SERVER_ERROR', 'Unexpected reply from the server');
    } catch (_) {
      throw ApiError('NETWORK', 'No internet connection. Please try again.');
    }
  }

  static const _timeout = Duration(seconds: 30);
  static final _http = http.Client();

  static Map<String, dynamic> _unwrap(dynamic data) {
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      if (m['ok'] == true) return m;
      final err = m['error'];
      if (err is Map) {
        throw ApiError(
          '${err['code'] ?? 'ERROR'}',
          '${err['message'] ?? 'Something went wrong'}',
          Map<String, dynamic>.from((err['details'] as Map?) ?? {}),
        );
      }
    }
    throw ApiError('SERVER_ERROR', 'Unexpected reply from the server');
  }

  // --- Saved replies -------------------------------------------------------

  static int _gen = 0;
  static int _seq = 0;
  static final _inflight = <String, ({int gen, Future<Map<String, dynamic>> reply})>{};
  static final _newest = <String, ({int seq, Map<String, dynamic> reply})>{};

  /// Bump the version when the app starts reading replies differently, so
  /// copies saved by an older version are not shown.
  static const _prefix = 'api_cache:v1:';
  static const _indexKey = 'api_cache_index';

  /// Oldest saved replies are dropped beyond this, so the store stays small.
  static const _maxSaved = 40;

  /// Includes the device ID, so a restored or different owner identity never
  /// sees another one's saved data.
  static String _cacheKey(String fn, Map<String, dynamic> body, String? key) =>
      '$_prefix${Device.id}:$fn:${key ?? _canonical(body)}';

  /// JSON with sorted map keys, so the same body always gives the same name.
  static String _canonical(Object? v) {
    if (v is Map) {
      final entries = [for (final e in v.entries) MapEntry('${e.key}', e.value)]
        ..sort((a, b) => a.key.compareTo(b.key));
      return '{${entries.map((e) => '${jsonEncode(e.key)}:${_canonical(e.value)}').join(',')}}';
    }
    if (v is Iterable) return '[${v.map(_canonical).join(',')}]';
    return jsonEncode(v);
  }

  static void _save(String k, Map<String, dynamic> reply) {
    try {
      final prefs = Device.prefs;
      prefs.setString(k, jsonEncode(reply)).ignore();
      final index = [...?prefs.getStringList(_indexKey)]
        ..remove(k)
        ..add(k);
      while (index.length > _maxSaved) {
        prefs.remove(index.removeAt(0)).ignore();
      }
      prefs.setStringList(_indexKey, index).ignore();
    } catch (_) {
      // Saving is only a speed-up; the screen already has the reply.
    }
  }
}
