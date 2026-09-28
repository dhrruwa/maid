import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/offline_queue.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'qr_scanner.dart';
import 'result_screen.dart';

/// Location check → scan house QR → GPS → online: mark_attendance / offline: save.
Future<void> startScan(BuildContext context) async {
  if (!await _ensureLocation(context) || !context.mounted) return;

  // Start the GPS fix while the camera is open, so it is ready sooner.
  final posFuture = _position();

  final value = await Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => QrScannerScreen(title: L.t('scan_title'))),
  );
  if (value == null || !context.mounted) return;
  final scannedAt = DateTime.now();

  if (value.startsWith('CDPAIR:')) {
    await showResult(context, ScanResult.fail(L.t('err_PAIR_QR')));
    return;
  }
  if (!value.startsWith('CDHOUSE:')) {
    await showResult(context, ScanResult.fail(L.t('err_WRONG_QR')));
    return;
  }

  final result = await Navigator.push<ScanResult>(
    context,
    MaterialPageRoute(builder: (_) => _Processing(qr: value, posFuture: posFuture, scannedAt: scannedAt)),
  );
  if (result != null && context.mounted) await showResult(context, result);
}

Future<Position?> _position() async {
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)),
    );
  } catch (_) {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 3)) return last;
    } catch (_) {}
    return null;
  }
}

/// Makes sure location is on and allowed. Shows a big "Please turn on location" screen if not.
Future<bool> _ensureLocation(BuildContext context) async {
  while (true) {
    final enabled = await Geolocator.isLocationServiceEnabled();
    var perm = await Geolocator.checkPermission();
    if (enabled && perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    final allowed = perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    if (enabled && allowed) return true;
    if (!context.mounted) return false;
    final retry = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _LocationNeeded(serviceOff: !enabled, foreverDenied: perm == LocationPermission.deniedForever)),
    );
    if (retry != true) return false;
  }
}

class _LocationNeeded extends StatelessWidget {
  const _LocationNeeded({required this.serviceOff, required this.foreverDenied});
  final bool serviceOff;
  final bool foreverDenied;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const Spacer(),
            const Icon(Icons.location_off_rounded, size: 110, color: StatusColors.missed),
            const SizedBox(height: 20),
            Text(
              serviceOff ? L.t('location_off') : L.t('location_permission'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(L.t('location_off_body'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 19)),
            const Spacer(),
            BigButton(
              icon: Icons.settings_rounded,
              label: L.t('open_settings'),
              onPressed: () async {
                if (serviceOff) {
                  await Geolocator.openLocationSettings();
                } else if (foreverDenied) {
                  await Geolocator.openAppSettings();
                } else {
                  await Geolocator.requestPermission();
                }
              },
            ),
            const SizedBox(height: 12),
            BigButton(
              icon: Icons.refresh_rounded,
              label: L.t('retry'),
              filled: false,
              onPressed: () => Navigator.pop(context, true),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Processing extends StatefulWidget {
  const _Processing({required this.qr, required this.posFuture, required this.scannedAt});
  final String qr;
  final Future<Position?> posFuture;
  final DateTime scannedAt;

  @override
  State<_Processing> createState() => _ProcessingState();
}

class _ProcessingState extends State<_Processing> {
  String _status = L.t('getting_location');

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    var pos = await widget.posFuture;
    pos ??= await _position();
    if (!mounted) return;
    if (pos == null) {
      Navigator.pop(context, ScanResult.fail(L.t('err_NO_LOCATION')));
      return;
    }
    setState(() => _status = L.t('checking'));

    final conn = await Connectivity().checkConnectivity();
    final noNet = conn.isEmpty || conn.every((c) => c == ConnectivityResult.none);
    if (noNet) return _saveOffline(pos);

    try {
      final r = await Api.call('mark_attendance', {
        'qr_token': widget.qr,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'is_mocked': pos.isMocked,
        'is_offline': false,
      });
      final a = Map<String, dynamic>.from(r['attendance']);
      HomeScreen.justEarned = (a['amount'] as num?)?.toInt();
      HomeScreen.refreshAll();
      if (mounted) {
        Navigator.pop(
          context,
          ScanResult.ok(amount: (a['amount'] as num).toInt(), slot: '${a['slot']}', timeIso: '${a['scanned_at']}'),
        );
      }
    } on ApiError catch (e) {
      if (e.isNetwork) return _saveOffline(pos);
      if (mounted) Navigator.pop(context, ScanResult.fail(e.friendly, detail: e.detail));
    }
  }

  Future<void> _saveOffline(Position pos) async {
    await OfflineQueue.add(
      qrToken: widget.qr,
      lat: pos.latitude,
      lng: pos.longitude,
      isMocked: pos.isMocked,
      scannedAt: widget.scannedAt,
    );
    HomeScreen.refreshAll();
    if (mounted) Navigator.pop(context, ScanResult.saved());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 6)),
            const SizedBox(height: 28),
            Text(_status, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
