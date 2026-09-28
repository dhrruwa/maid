import 'package:supabase_flutter/supabase_flutter.dart';

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
    } catch (_) {
      throw ApiError('NETWORK', '');
    }
  }

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
