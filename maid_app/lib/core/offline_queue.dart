import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'api.dart';
import 'device.dart';

/// Result of uploading one saved scan.
class UploadResult {
  UploadResult.ok(this.attendance) : error = null;
  UploadResult.failed(this.error) : attendance = null;
  final Map<String, dynamic>? attendance;
  final ApiError? error;
}

/// Scans taken without internet are kept here (shared_preferences) and uploaded
/// automatically when the network returns, when the app is opened/resumed,
/// and every minute while the app is open.
class OfflineQueue {
  static const _key = 'pending_scans';
  static final _results = StreamController<List<UploadResult>>.broadcast();
  static final _changes = StreamController<int>.broadcast();

  /// Emits after uploads so Home can show "Saved scan uploaded".
  static Stream<List<UploadResult>> get results => _results.stream;

  /// Emits the pending count when it changes.
  static Stream<int> get changes => _changes.stream;

  static bool _syncing = false;
  static Timer? _timer;
  static StreamSubscription? _sub;

  static List<Map<String, dynamic>> get items {
    final raw = Device.prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static int get count => items.length;

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    await Device.prefs.setString(_key, jsonEncode(list));
    _changes.add(list.length);
  }

  static Future<void> add({
    required String qrToken,
    required double lat,
    required double lng,
    required bool isMocked,
    required DateTime scannedAt,
  }) async {
    await _save([
      ...items,
      {
        'qr_token': qrToken,
        'lat': lat,
        'lng': lng,
        'is_mocked': isMocked,
        'scanned_at': scannedAt.toUtc().toIso8601String(),
      },
    ]);
  }

  static void start() {
    _sub ??= Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) sync();
    });
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => sync());
    sync();
  }

  static Future<void> sync() async {
    if (_syncing || count == 0) return;
    _syncing = true;
    final done = <UploadResult>[];
    try {
      final pending = items;
      final keep = <Map<String, dynamic>>[];
      var offline = false;
      for (final scan in pending) {
        if (offline) {
          keep.add(scan);
          continue;
        }
        try {
          final r = await Api.call('mark_attendance', {...scan, 'is_offline': true});
          done.add(UploadResult.ok(Map<String, dynamic>.from(r['attendance'])));
        } on ApiError catch (e) {
          if (e.isNetwork) {
            offline = true;
            keep.add(scan);
          } else {
            done.add(UploadResult.failed(e)); // rejected: drop it, but tell her why
          }
        }
      }
      await _save(keep);
    } finally {
      _syncing = false;
    }
    if (done.isNotEmpty) _results.add(done);
  }
}
