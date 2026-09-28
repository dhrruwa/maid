import 'package:supabase_flutter/supabase_flutter.dart';

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
    try {
      final res = await Supabase.instance.client.functions.invoke(
        fn,
        body: {...body, 'device_id': Device.id},
      );
      return _unwrap(res.data);
    } on FunctionException catch (e) {
      return _unwrap(e.details);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError('NETWORK', 'No internet connection. Please try again.');
    }
  }

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
