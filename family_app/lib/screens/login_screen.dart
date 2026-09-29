import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/logo.dart';
import '../widgets/motion.dart';
import 'home_screen.dart';

/// Shown once: name + 4-digit PIN (the last 4 digits of the member's phone
/// number). After that the login is remembered on this phone.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.name = '', this.notice});
  final String name;

  /// Why the member is here again (e.g. the owner reset their PIN).
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _name = TextEditingController(text: widget.name);
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  bool _busy = false;
  bool _showPin = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final name = _name.text.trim();
    final pin = _pin.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = 'The PIN is the last 4 digits of your phone number.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Api.call('member_login', {'name': name, 'pin': pin});
      final member = res['member'] is Map ? Map<String, dynamic>.from(res['member'] as Map) : <String, dynamic>{};
      final id = '${member['id'] ?? ''}';
      if (id.isEmpty) throw ApiError('SERVER_ERROR', '');
      ApiCache.clear();
      await Device.saveLogin(memberId: id, name: '${member['name'] ?? name}', houseName: '${res['house_name'] ?? ''}');
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.friendly);
      if (e.code == 'LOGIN_FAILED') _pin.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = <Widget>[
      if (widget.notice != null)
        InfoBanner(icon: Icons.info_outline_rounded, color: StatusColors.holiday, text: widget.notice!),
      const Center(child: AppLogo(size: 104)),
      Column(
        children: [
          Text(
            'Family meals',
            textAlign: TextAlign.center,
            style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            "See what's cooking and book your meals.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17),
          ),
        ],
      ),
      Glass(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: AutofillGroup(
          // No "Save password?" prompt: this phone remembers the login itself.
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.givenName],
                style: const TextStyle(fontSize: 20),
                onSubmitted: (_) => _pinFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  prefixIcon: Icon(Icons.person_rounded, size: 26),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pin,
                focusNode: _pinFocus,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                obscureText: !_showPin,
                obscuringCharacter: '●',
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.w800),
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: 'PIN',
                  labelStyle: const TextStyle(letterSpacing: 0, fontWeight: FontWeight.w400),
                  helperText: 'Last 4 digits of your phone number',
                  helperStyle: const TextStyle(fontSize: 14),
                  prefixIcon: const Icon(Icons.dialpad_rounded, size: 26),
                  suffixIcon: IconButton(
                    tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
                    onPressed: () => setState(() => _showPin = !_showPin),
                    icon: Icon(_showPin ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _error == null
                    ? const SizedBox(width: double.infinity, height: 18)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 4),
                        child: _ErrorText(text: _error!),
                      ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 3, color: espresso),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.login_rounded, size: 24),
                          SizedBox(width: 10),
                          Text('Log in', style: TextStyle(fontSize: 20)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      const Text(
        'You only need to do this once. This phone will remember you.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: Color(0xFF6B5446)),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 20),
              itemBuilder: (_, i) => EntryAnimation(index: i, child: items[i]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StatusColors.missed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StatusColors.missed.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB23535), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF8E2424)),
            ),
          ),
        ],
      ),
    );
  }
}
