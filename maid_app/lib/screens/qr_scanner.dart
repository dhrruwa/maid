import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// Full camera with a rounded frame; pops with the first QR value found.
/// (Reference: Meetup / Luma "Scan to check in".)
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, required this.title, this.bottom});
  final String title;
  final Widget? bottom;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        _done = true;
        Navigator.pop(context, v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            iconSize: 30,
            icon: const Icon(Icons.flashlight_on_rounded, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(alignment: Alignment.center, children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? L.t('camera_permission')
                        : L.t('err_GENERIC'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: accent, width: 5),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ]),
        ),
        Container(
          color: Colors.black,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.qr_code_2_rounded, color: Colors.white70, size: 40),
            const SizedBox(height: 8),
            Text(L.t('scan_hint'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19)),
            if (widget.bottom != null) ...[const SizedBox(height: 12), widget.bottom!],
          ]),
        ),
      ]),
    );
  }
}
