import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// White rounded tile with a QR (reference: Perplexity 2FA / Comet add device).
class QrTile extends StatelessWidget {
  const QrTile({super.key, required this.data, this.size = 240});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20)],
      ),
      child: QrImageView(data: data, size: size, backgroundColor: Colors.white),
    );
  }
}

/// House attendance QR with Share image / Print actions.
class HouseQrView extends StatelessWidget {
  const HouseQrView({super.key});

  static Future<void> shareImage(BuildContext context) async {
    final st = AppState.i;
    final painter = QrPainter(
      data: st.houseQrPayload,
      version: QrVersions.auto,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
    );
    final img = await painter.toImageData(1024);
    if (img == null) return;
    // Give the PNG a white background margin by wrapping it in a PDF raster is overkill;
    // QR readers accept the transparent PNG, and WhatsApp renders it on white.
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(img.buffer.asUint8List(), mimeType: 'image/png', name: 'house-qr.png')],
      text: 'Attendance QR for ${st.house['name']} – stick this in the kitchen.',
    ));
  }

  static Future<void> printQr() async {
    final st = AppState.i;
    await Printing.layoutPdf(
      name: 'house-qr.pdf',
      onLayout: (format) async {
        final doc = pw.Document();
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(
            child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
              pw.Text('${st.house['name']}', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Scan to mark attendance', style: const pw.TextStyle(fontSize: 18)),
              pw.SizedBox(height: 24),
              pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: st.houseQrPayload, width: 360, height: 360),
              pw.SizedBox(height: 24),
              pw.Text('Maid app → Scan QR', style: const pw.TextStyle(fontSize: 14)),
            ]),
          ),
        ));
        return doc.save();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      QrTile(data: AppState.i.houseQrPayload),
      const SizedBox(height: 16),
      Text('Stick this QR in the kitchen. The cook scans it every visit.',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => shareImage(context),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: printQr,
            icon: const Icon(Icons.print_rounded),
            label: const Text('Print / Save'),
          ),
        ),
      ]),
    ]);
  }
}

/// One-time pairing QR + 6-digit code. Waits until the maid phone is linked.
class PairView extends StatefulWidget {
  const PairView({super.key, this.onPaired});
  final VoidCallback? onPaired;

  @override
  State<PairView> createState() => _PairViewState();
}

class _PairViewState extends State<PairView> {
  Map<String, dynamic>? _tok;
  Object? _error;
  Timer? _tick;
  Timer? _poll;
  String? _pairedName;
  late final String? _startCookId = AppState.i.cook?['id'];

  @override
  void initState() {
    super.initState();
    _generate();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _tok = null;
      _error = null;
    });
    try {
      final r = await Api.call('generate_pairing_token');
      if (mounted) setState(() => _tok = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _check() async {
    if (_pairedName != null || _tok == null) return;
    try {
      await AppState.i.refresh();
      final cook = AppState.i.cook;
      if (cook != null && cook['id'] != _startCookId) {
        _poll?.cancel();
        setState(() => _pairedName = '${cook['name']}');
        widget.onPaired?.call();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_pairedName != null) {
      return Column(children: [
        const Icon(Icons.check_circle_rounded, color: StatusColors.done, size: 96),
        const SizedBox(height: 12),
        Text("$_pairedName's phone is paired", style: Theme.of(context).textTheme.titleLarge),
      ]);
    }
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _generate);
    if (_tok == null) return const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator());

    final left = DateTime.parse(_tok!['expires_at']).difference(DateTime.now());
    final expired = left.isNegative;
    final code = '${_tok!['code']}';
    return Column(children: [
      Text('On the cook\'s phone open the Maid app and tap "Scan pairing QR".',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 16),
      Opacity(opacity: expired ? 0.2 : 1, child: QrTile(data: '${_tok!['qr_payload']}', size: 220)),
      const SizedBox(height: 16),
      Text('Or enter this code', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      SelectableText(
        '${code.substring(0, 3)} ${code.substring(3)}',
        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4),
      ),
      const SizedBox(height: 8),
      if (!expired)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Waiting for the cook… valid ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}'),
        ])
      else
        FilledButton.icon(onPressed: _generate, icon: const Icon(Icons.refresh), label: const Text('New code')),
    ]);
  }
}

class PairScreen extends StatelessWidget {
  const PairScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair maid phone')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: PairView(onPaired: () => AppState.i.changed()),
      ),
    );
  }
}

class HouseQrScreen extends StatelessWidget {
  const HouseQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('House attendance QR')),
      body: const SingleChildScrollView(padding: EdgeInsets.all(24), child: HouseQrView()),
    );
  }
}
