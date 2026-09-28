import 'package:flutter/material.dart';

import '../../config.dart';
import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/device.dart';
import '../../core/export.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/pin_pad.dart';
import '../qr_views.dart';
import '../setup/setup_flow.dart';

/// Grouped settings (reference: Perplexity notification settings).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final st = AppState.i;

  @override
  void initState() {
    super.initState();
    st.addListener(_rebuild);
    st.refresh().catchError((_) {});
  }

  @override
  void dispose() {
    st.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => mounted ? setState(() {}) : null;

  Future<void> _update({Map<String, dynamic>? house, Map<String, dynamic>? settings, String? success}) async {
    final r = await busy(context, () => Api.call('update_settings', {
          if (house != null) 'house': house,
          if (settings != null) 'settings': settings,
        }), success: success ?? 'Saved');
    if (r != null) {
      st.apply(r);
      st.changed();
    }
  }

  Future<void> _editNumber(String title, String key, {required int current, required String suffix}) async {
    final v = await askText(context, title, initial: '$current', hint: suffix);
    final n = int.tryParse(v ?? '');
    if (n == null) return;
    await _update(settings: {key: n});
  }

  Future<void> _editTime(String key) async {
    final cur = '${st.settings[key] ?? '06:00'}'.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(cur[0]), minute: int.parse(cur[1])),
    );
    if (t == null) return;
    await _update(settings: {key: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'});
  }

  Future<void> _changePin() async {
    String? newPin;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (c) => Scaffold(
          appBar: AppBar(),
          body: SafeArea(child: _ChangePinFlow(onDone: (p) {
            newPin = p;
            Navigator.pop(c, true);
          })),
        ),
      ),
    );
    if (ok != true || newPin == null || !mounted) return;
    final hash = Device.hashPin(newPin!);
    final r = await busy(context, () => Api.call('update_settings', {'house': {'owner_pin_hash': hash}}),
        success: 'PIN changed');
    if (r != null) await Device.savePinHash(hash);
  }

  Future<void> _setLocation() async {
    final ok = await confirm(context, 'Update house location?',
        'Do this only while you are at home. The cook must scan within ${st.house['radius_m']} m of this spot.',
        ok: "I'm at home");
    if (!ok || !mounted) return;
    final pos = await getCurrentPosition(context);
    if (pos == null) return;
    await _update(house: {'lat': pos.latitude, 'lng': pos.longitude}, success: 'Location updated');
  }

  Future<void> _radius() async {
    var v = ((st.house['radius_m'] ?? 100) as num).toDouble();
    final r = await showDialog<double>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Allowed distance'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${v.round()} m', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            Slider(value: v, min: 20, max: 500, divisions: 48, onChanged: (x) => set(() => v = x)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, v), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (r != null) await _update(house: {'radius_m': r.round()});
  }

  Future<void> _regenerateQr() async {
    final ok = await confirm(context, 'Make a new house QR?',
        'The old printed QR will stop working immediately. You will need to print the new one.',
        ok: 'Regenerate', danger: true);
    if (!ok || !mounted) return;
    final r = await busy(context, () => Api.call('regenerate_qr'), success: 'New QR created');
    if (r != null && mounted) {
      st.apply(r);
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HouseQrScreen()));
    }
  }

  Future<void> _unpair() async {
    final ok = await confirm(context, 'Unpair maid phone?',
        'Her phone will no longer be able to mark attendance until you pair again. History is kept.',
        ok: 'Unpair', danger: true);
    if (!ok || !mounted) return;
    final r = await busy(context, () => Api.call('unpair_cook'), success: 'Maid phone unpaired');
    if (r != null) {
      await st.refresh().catchError((_) {});
      st.changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = st.house;
    final s = st.settings;
    final cook = st.cook;

    Widget toggle(String key, IconData icon, String title, String sub) => SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(sub),
          value: s[key] == true,
          onChanged: (v) => _update(settings: {key: v}, success: v ? 'Turned on' : 'Turned off'),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        _Group('House', [
          ListTile(
            leading: const Icon(Icons.home_rounded),
            title: const Text('House name'),
            subtitle: Text('${h['name'] ?? ''}'),
            onTap: () async {
              final v = await askText(context, 'House name', initial: '${h['name'] ?? ''}');
              if (v != null && v.isNotEmpty) await _update(house: {'name': v});
            },
          ),
          ListTile(
            leading: const Icon(Icons.location_on_rounded),
            title: const Text('House location'),
            subtitle: Text(h['lat'] == null
                ? 'Not set'
                : '${(h['lat'] as num).toStringAsFixed(5)}, ${(h['lng'] as num).toStringAsFixed(5)}'),
            trailing: const Icon(Icons.my_location_rounded),
            onTap: _setLocation,
          ),
          ListTile(
            leading: const Icon(Icons.radar_rounded),
            title: const Text('Allowed distance'),
            subtitle: Text('${h['radius_m'] ?? 100} m'),
            onTap: _radius,
          ),
        ]),
        _Group('Pay rates', [
          ListTile(
            leading: const Icon(Icons.work_outline_rounded),
            title: const Text('Monday – Friday, per visit'),
            trailing: Text(rupees(s['weekday_rate']), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => _editNumber('Weekday rate (₹ per visit)', 'weekday_rate',
                current: (s['weekday_rate'] ?? 100) as int, suffix: '₹'),
          ),
          ListTile(
            leading: const Icon(Icons.weekend_outlined),
            title: const Text('Saturday – Sunday, per visit (morning)'),
            trailing: Text(rupees(s['weekend_rate']), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => _editNumber('Weekend rate (₹ per visit)', 'weekend_rate',
                current: (s['weekend_rate'] ?? 200) as int, suffix: '₹'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('New rates apply from the next scan. Paid months never change.', style: TextStyle(fontSize: 12)),
          ),
        ]),
        _Group('Time windows', [
          for (final (k, label, icon) in [
            ('morning_start', 'Morning starts', Icons.wb_twilight_rounded),
            ('morning_end', 'Morning ends', Icons.wb_sunny_outlined),
            ('evening_start', 'Evening starts (Mon–Fri)', Icons.wb_twilight_rounded),
            ('evening_end', 'Evening ends', Icons.nights_stay_outlined),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: Text(s[k] == null ? '' : timeLabel('${s[k]}'), style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => _editTime(k),
            ),
        ]),
        _Group('Notifications', [
          toggle('notify_scan', Icons.how_to_reg_rounded, 'Attendance marked', 'When the cook scans the QR'),
          toggle('notify_leave', Icons.event_busy_rounded, 'Leave requests', 'When the cook asks for leave'),
          toggle('notify_offline', Icons.cloud_off_rounded, 'Offline scans', 'When a saved offline scan is uploaded'),
          toggle('notify_payday', Icons.payments_rounded, 'Salary due', 'On the 1st, and a reminder on the 4th'),
          toggle('notify_menu', Icons.restaurant_menu_rounded, 'Tell the cook about menu changes',
              'Sends her today\'s/tomorrow\'s menu when you change it'),
          if (!AppConfig.firebaseConfigured)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Push notifications are off until Firebase is set up (see setup guide).',
                  style: TextStyle(fontSize: 12, color: StatusColors.missed)),
            ),
        ]),
        _Group('Maid phone', [
          ListTile(
            leading: Icon(cook != null ? Icons.phone_android_rounded : Icons.phonelink_off_rounded,
                color: cook != null ? StatusColors.done : StatusColors.future),
            title: Text(cook != null ? '${cook['name']}' : 'No phone paired'),
            subtitle: cook != null ? Text('Paired ${istDateTime(cook['paired_at'])}') : null,
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner_rounded),
            title: Text(cook != null ? 'Pair a new phone' : 'Pair maid phone'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PairScreen())),
          ),
          if (cook != null)
            ListTile(
              leading: const Icon(Icons.link_off_rounded, color: StatusColors.missed),
              title: const Text('Unpair maid phone', style: TextStyle(color: StatusColors.missed)),
              onTap: _unpair,
            ),
        ]),
        _Group('Attendance QR', [
          ListTile(
            leading: const Icon(Icons.qr_code_2_rounded),
            title: const Text('Show / share / print house QR'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HouseQrScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.autorenew_rounded),
            title: const Text('Regenerate QR'),
            subtitle: const Text('Old QR stops working'),
            onTap: _regenerateQr,
          ),
        ]),
        _Group('Security & data', [
          ListTile(leading: const Icon(Icons.pin_outlined), title: const Text('Change PIN'), onTap: _changePin),
          ListTile(
            leading: const Icon(Icons.table_view_rounded),
            title: const Text('Export all data (Excel)'),
            onTap: () => busy(context, exportAllData),
          ),
        ]),
      ]),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        child: Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1, fontWeight: FontWeight.w700)),
      ),
      Card(child: Column(children: children)),
    ]);
  }
}

class _ChangePinFlow extends StatefulWidget {
  const _ChangePinFlow({required this.onDone});
  final void Function(String pin) onDone;

  @override
  State<_ChangePinFlow> createState() => _ChangePinFlowState();
}

class _ChangePinFlowState extends State<_ChangePinFlow> {
  int _step = 0;
  String? _new;

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      0 => PinPad(
          key: const ValueKey(0),
          title: 'Current PIN',
          onCompleted: (p) async {
            if (!Device.checkPin(p)) return false;
            setState(() => _step = 1);
            return true;
          },
        ),
      1 => PinPad(
          key: const ValueKey(1),
          title: 'New PIN',
          onCompleted: (p) async {
            _new = p;
            setState(() => _step = 2);
            return true;
          },
        ),
      _ => PinPad(
          key: const ValueKey(2),
          title: 'Confirm new PIN',
          onCompleted: (p) async {
            if (p != _new) return false;
            widget.onDone(p);
            return true;
          },
        ),
    };
  }
}
