import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

enum ResultKind { ok, saved, fail }

class ScanResult {
  ScanResult.ok({required this.amount, required this.slot, required this.timeIso})
      : kind = ResultKind.ok,
        reason = null,
        detail = null;
  ScanResult.saved()
      : kind = ResultKind.saved,
        amount = null,
        slot = null,
        timeIso = null,
        reason = null,
        detail = null;
  ScanResult.fail(this.reason, {this.detail})
      : kind = ResultKind.fail,
        amount = null,
        slot = null,
        timeIso = null;

  final ResultKind kind;
  final int? amount;
  final String? slot;
  final String? timeIso;
  final String? reason;
  final String? detail;
}

Future<void> showResult(BuildContext context, ScanResult r) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(result: r)));

/// Big full-screen green (success), amber (saved offline) or red (failure).
/// (Reference: Luma "You're In", Public "Debit card linked".)
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.result});
  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final (color, icon, title) = switch (r.kind) {
      ResultKind.ok => (StatusColors.done, Icons.check_circle_rounded, L.t('success_title')),
      ResultKind.saved => (StatusColors.wait, Icons.cloud_upload_rounded, L.t('saved_title')),
      ResultKind.fail => (StatusColors.missed, Icons.cancel_rounded, L.t('failed_title')),
    };
    const white = TextStyle(color: Colors.white);
    return Scaffold(
      backgroundColor: color,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.5, end: 1),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: Icon(icon, size: 150, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: white.copyWith(fontSize: 34, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            if (r.kind == ResultKind.ok) ...[
              Text(
                L.t('at_time', {'slot': L.slot(r.slot!), 'time': L.time(r.timeIso!)}),
                style: white.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(30)),
                child: Text(L.t('earned_amount', {'amount': rupees(r.amount)}),
                    style: white.copyWith(fontSize: 30, fontWeight: FontWeight.w900)),
              ),
            ],
            if (r.kind == ResultKind.saved)
              Text(L.t('saved_body'), textAlign: TextAlign.center, style: white.copyWith(fontSize: 22)),
            if (r.kind == ResultKind.fail) ...[
              Text(r.reason ?? '', textAlign: TextAlign.center, style: white.copyWith(fontSize: 26, fontWeight: FontWeight.w700)),
              if (r.detail != null) ...[
                const SizedBox(height: 10),
                Text(r.detail!, textAlign: TextAlign.center, style: white.copyWith(fontSize: 19)),
              ],
            ],
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: color,
                minimumSize: const Size(double.infinity, 68),
                textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('ok')),
            ),
          ]),
        ),
      ),
    );
  }
}
