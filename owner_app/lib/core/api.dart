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
class Api {
  static Future<Map<String, dynamic>> call(String fn, [Map<String, dynamic> body = const {}]) async {
    final payload = {...body, 'device_id': Device.id};
    try {
      if (AppConfig.supabaseConfigured) {
        final res = await Supabase.instance.client.functions.invoke(fn, body: payload).timeout(_timeout);
        return _unwrap(res.data);
      }
      // No anon key configured yet: the functions check the device ID themselves,
      // so they can be called directly.
      final res = await _http
          .post(
            Uri.parse('${AppConfig.supabaseUrl}/functions/v1/$fn'),
            headers: {'Content-Type': 'application/json'},
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
}
