import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/device.dart';
import '../../core/push.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/pin_pad.dart';
import '../qr_views.dart';

/// First launch: welcome → PIN → house location → house QR → pair maid phone.
/// (Reference: Opera "Connect" – one idea, one primary button per step.)
class SetupFlow extends StatefulWidget {
  const SetupFlow({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends State<SetupFlow> {
  // 0 welcome, 1 pin, 2 confirm pin, 3 location, 4 house QR, 5 pair
  int _step = 0;
  String? _firstPin;

  // Resume where we stopped if the house already exists (app killed mid-setup).
  @override
  void initState() {
    super.initState();
    if (AppState.i.house['id'] != null && Device.pinHash != null) _step = 4;
  }

  Future<void> _finish() async {
    await Device.markSetupDone();
    await Push.syncToken();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final steps = ['PIN', 'Location', 'House QR', 'Pair'];
    final stepIdx = switch (_step) { 1 || 2 => 0, 3 => 1, 4 => 2, 5 => 3, _ => -1 };
    return Scaffold(
      appBar: _step == 0
          ? null
          : AppBar(
              leading: _step > 0 && _step < 4
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _step = _step == 3 ? 1 : _step - 1),
                    )
                  : null,
              automaticallyImplyLeading: false,
              title: Row(
                children: List.generate(steps.length, (i) {
                  final active = i <= stepIdx;
                  return Expanded(
                    child: Container(
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_step) {
      case 0:
        return _Welcome(
          onStart: () => setState(() => _step = 1),
          onRestore: () async {
            final ok = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => const RestoreScreen()),
            );
            if (ok == true) await _finish();
          },
        );
      case 1:
        return PinPad(
          key: const ValueKey('pin1'),
          title: 'Create a PIN',
          subtitle: 'You will enter this 4-digit PIN to open the app.',
          onCompleted: (pin) async {
            _firstPin = pin;
            setState(() => _step = 2);
            return true;
          },
        );
      case 2:
        return PinPad(
          key: const ValueKey('pin2'),
          title: 'Confirm your PIN',
          subtitle: 'Enter it again to make sure it matches.',
          onCompleted: (pin) async {
            if (pin != _firstPin) return false;
            await Device.savePinHash(Device.hashPin(pin));
            setState(() => _step = 3);
            return true;
          },
        );
      case 3:
        return _LocationStep(onCreated: () => setState(() => _step = 4));
      case 4:
        return _Padded(
          title: 'Your house QR code',
          subtitle: 'Print it or share it, then stick it in the kitchen.',
          action: FilledButton(onPressed: () => setState(() => _step = 5), child: const Text('Next')),
          child: const HouseQrView(),
        );
      default:
        return _Padded(
          title: 'Pair maid phone',
          subtitle: 'Link the cook\'s phone so only her phone can mark attendance.',
          action: FilledButton(onPressed: _finish, child: const Text('Done')),
          secondary: TextButton(onPressed: _finish, child: const Text('Skip for now – pair later in Settings')),
          child: const PairView(),
        );
    }
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.title, required this.subtitle, required this.child, required this.action, this.secondary});
  final String title;
  final String subtitle;
  final Widget child;
  final Widget action;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            child,
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          action,
          if (secondary != null) secondary!,
        ]),
      ),
    ]);
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart, required this.onRestore});
  final VoidCallback onStart;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Spacer(),
        const Center(child: AppLogo(size: 128)),
        const SizedBox(height: 28),
        Text('Owner',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(
          'Attendance, salary, holidays and the daily menu for your home cook – all in one place.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const Spacer(),
        FilledButton(onPressed: onStart, child: const Text('Get started')),
        const SizedBox(height: 8),
        TextButton(onPressed: onRestore, child: const Text('Moving from an old phone? Use recovery key')),
      ]),
    );
  }
}

class _LocationStep extends StatefulWidget {
  const _LocationStep({required this.onCreated});
  final VoidCallback onCreated;

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  final _name = TextEditingController(text: 'Home');
  Position? _pos;
  double _radius = 100;
  bool _locating = false;

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      _pos = await getCurrentPosition(context);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _create() async {
    final pos = _pos!;
    final r = await busy(context, () => Api.call('create_house', {
          'name': _name.text.trim().isEmpty ? 'Home' : _name.text.trim(),
          'lat': pos.latitude,
          'lng': pos.longitude,
          'radius_m': _radius.round(),
          'pin_hash': Device.pinHash,
          'fcm_token': Push.token,
        }));
    if (r == null || !mounted) return;
    AppState.i.apply({...r, 'cook': null});
    final key = r['recovery_key'];
    if (key != null) await showRecoveryKey(context, '$key');
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    return _Padded(
      title: 'Set house location',
      subtitle: 'Do this while you are at home. Attendance only counts when the cook scans within this distance.',
      action: FilledButton(onPressed: _pos == null ? null : _create, child: const Text('Continue')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'House name')),
        const SizedBox(height: 20),
        SectionCard(
          child: Column(children: [
            Icon(
              _pos == null ? Icons.location_searching_rounded : Icons.location_on_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              _pos == null
                  ? 'Location not set yet'
                  : 'Location saved (accuracy ±${_pos!.accuracy.round()} m)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _locating ? null : _locate,
              icon: _locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
              label: Text(_pos == null ? "I'm at home – set location" : 'Update location'),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Text('Allowed distance: ${_radius.round()} m', style: const TextStyle(fontWeight: FontWeight.w600)),
        Slider(
          value: _radius,
          min: 50,
          max: 500,
          divisions: 18,
          label: '${_radius.round()} m',
          onChanged: (v) => setState(() => _radius = v),
        ),
      ]),
    );
  }
}

/// Asks for permission and returns a fresh GPS fix, or null with a message.
Future<Position?> getCurrentPosition(BuildContext context) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) {
      final open = await confirm(context, 'Location is off', 'Please turn on location to continue.', ok: 'Open settings');
      if (open) await Geolocator.openLocationSettings();
    }
    return null;
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    if (context.mounted) {
      final open = await confirm(context, 'Location permission needed',
          'Allow location so the app knows where your house is.', ok: 'Open settings');
      if (open) await Geolocator.openAppSettings();
    }
    return null;
  }
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 30)),
    );
  } catch (e) {
    if (context.mounted) toast(context, 'Could not get location. Try again near a window.', error: true);
    return null;
  }
}

Future<void> showRecoveryKey(BuildContext context, String key) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.key_rounded),
      title: const Text('Your recovery key'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Write this down and keep it safe. You need it to move this app to a new phone. '
            'It will not be shown again.'),
        const SizedBox(height: 16),
        SelectableText(key, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2)),
      ]),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: key)),
          child: const Text('Copy'),
        ),
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text('I wrote it down')),
      ],
    ),
  );
}

class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _key = TextEditingController();

  Future<void> _restore() async {
    final r = await busy(context, () => Api.call('restore_owner', {
          'recovery_key': _key.text.trim(),
          'fcm_token': Push.token,
        }));
    if (r == null || !mounted) return;
    final pinHash = r['house']?['owner_pin_hash'];
    if (pinHash is String) await Device.savePinHash(pinHash);
    AppState.i.apply(r);
    await AppState.i.refresh().catchError((_) {});
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Move to this phone')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Enter the recovery key you wrote down when you first set up the app. '
            'Your old phone will stop working as the owner phone. Your old PIN stays the same.'),
        const SizedBox(height: 20),
        TextField(
          controller: _key,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Recovery key', hintText: 'XXXX-XXXX-XXXX'),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _restore, child: const Text('Restore')),
      ]),
    );
  }
}
