import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/i18n.dart';
import '../core/offline_queue.dart';
import '../core/push.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import 'home_screen.dart';
import 'qr_scanner.dart';

/// First launch: name → big "Scan pairing QR" → (or) small "Enter code instead".
/// (Reference: Opera "Connect" – one big button with a small text link below.)
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _name = TextEditingController(text: Device.name);
  bool _busy = false;

  bool _checkName() {
    if (_name.text.trim().isEmpty) {
      showMsg(context, L.t('pair_need_name'), error: true);
      return false;
    }
    return true;
  }

  Future<void> _pair({String? token, String? code}) async {
    setState(() => _busy = true);
    try {
      await Api.call('pair_cook', {
        'pairing_token': ?token,
        'code': ?code,
        'name': _name.text.trim(),
        'fcm_token': ?Push.token,
        'lang': L.code,
      });
      // Saved screens may belong to a house this phone was paired with before.
      ApiCache.clear();
      await Device.prefs.remove('home_cache');
      await Device.setName(_name.text.trim());
      await Device.setPaired(true);
      OfflineQueue.start();
      if (!mounted) return;
      showMsg(context, L.t('pair_success'));
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } on ApiError catch (e) {
      if (mounted) showMsg(context, e.friendly, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    if (!_checkName()) return;
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => QrScannerScreen(title: L.t('pair_scan_title'))),
    );
    if (value == null || !mounted) return;
    if (!value.startsWith('CDPAIR:')) {
      showMsg(context, L.t('err_NOT_PAIRING_QR'), error: true);
      return;
    }
    await _pair(token: value.substring(7));
  }

  Future<void> _enterCode() async {
    if (!_checkName()) return;
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L.t('pair_code_title')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, letterSpacing: 8, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(hintText: '000000'),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(L.t('pair_connect'))),
        ],
      ),
    );
    if (code == null || code.length != 6) return;
    await _pair(code: code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.t('app_title')), actions: [LangButton(onChanged: () => setState(() {}))]),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 12),
          const Center(child: AppLogo(size: 120)),
          const SizedBox(height: 20),
          Text(L.t('pair_welcome'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(L.t('pair_intro'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 28),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 22),
            decoration: InputDecoration(
              labelText: L.t('pair_name_label'),
              hintText: L.t('pair_name_hint'),
              prefixIcon: const Icon(Icons.person_rounded, size: 28),
            ),
          ),
          const SizedBox(height: 24),
          if (_busy)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else ...[
            BigButton(icon: Icons.qr_code_scanner_rounded, label: L.t('pair_scan'), onPressed: _scan, height: 76),
            const SizedBox(height: 12),
            Text(L.t('pair_help'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _enterCode,
              icon: const Icon(Icons.dialpad_rounded),
              label: Text(L.t('pair_enter_code'), style: const TextStyle(fontSize: 17)),
            ),
          ],
        ]),
      ),
    );
  }
}
