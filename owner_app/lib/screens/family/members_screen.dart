import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../menu/bookings.dart';

/// What the owner sends to a family member so they can log in to the Family app.
const familyShareText =
    'Install the Family app and log in with your name and the last 4 digits of your phone number.';

/// Body of the members list read (saved on the phone, shared with Settings).
const membersListBody = {'action': 'list'};

/// Active members from a `manage_members` list reply.
List<Map<String, dynamic>>? parseMembers(Map<String, dynamic>? r) {
  if (r == null) return null;
  final list = r['members'];
  if (list is! List) return null;
  return [for (final m in list) if (m is Map) Map<String, dynamic>.from(m)];
}

/// Opens the share sheet with the Family app invitation. [name] adds the exact
/// name to type, since logging in needs it.
Future<void> shareFamilyInvite(BuildContext context, {String? name}) async {
  final box = context.findRenderObject() as RenderBox?;
  final text = name == null ? familyShareText : 'Hi $name! $familyShareText\nYour name in the app: $name';
  await SharePlus.instance.share(ShareParams(
    text: text,
    subject: 'Family app',
    sharePositionOrigin: box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
  ));
}

/// The server's error in words a family owner understands.
ApiError _friendly(Object e, {String? name}) {
  if (e is! ApiError) return ApiError('ERROR', 'Something went wrong. Please try again.');
  final msg = switch (e.code) {
    'NAME_TAKEN' => name == null
        ? 'Someone in the family already has this name. Add an initial or surname to tell them apart.'
        : 'Someone called "$name" is already in the family. Add an initial or surname to tell them apart.',
    'BAD_NAME' => 'Use a name of up to $maxMemberName letters, without the characters % _ * or \\.',
    'NOT_FOUND' || 'MEMBER_NOT_FOUND' => 'This member was already removed.',
    'MISSING_FIELD' => switch (e.details['field']) {
        'name' => 'Please enter a name.',
        'pin' => 'The PIN must be exactly 4 digits.',
        _ => 'Something went wrong. Please try again.',
      },
    'NETWORK' => e.message,
    final c when c.contains('PIN') => 'The PIN must be exactly 4 digits.',
    _ => e.message,
  };
  return ApiError(e.code, msg, e.details);
}

/// Longest name the server accepts (`MAX_NAME` in `_shared/family.ts`).
const maxMemberName = 40;

/// "  Asha   Rao " → "Asha Rao" (the server saves names this way too).
String _cleanName(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Codes meaning the member is gone (removed on another phone, or a stale list).
bool _isGone(Object e) => e is ApiError && (e.code == 'NOT_FOUND' || e.code == 'MEMBER_NOT_FOUND');

/// Settings → Family members: who can book meals in the Family app.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<Map<String, dynamic>>? _members = parseMembers(Api.cached('manage_members', body: membersListBody));
  Object? _error;
  int _seenVersion = -1;

  @override
  void initState() {
    super.initState();
    AppState.i.addListener(_onState);
    _load();
  }

  @override
  void dispose() {
    AppState.i.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (AppState.i.version != _seenVersion) _load();
  }

  Future<void> _load() async {
    _seenVersion = AppState.i.version;
    try {
      final r = await Api.read('manage_members', body: membersListBody);
      if (mounted) {
        setState(() {
          _members = parseMembers(r) ?? [];
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// A change through `manage_members`; reloads every screen on success.
  Future<bool> _change(Map<String, dynamic> body, {required String success, String? name}) async {
    var gone = false;
    final r = await busy(context, () async {
      try {
        return await Api.call('manage_members', body);
      } catch (e) {
        gone = _isGone(e);
        throw _friendly(e, name: name);
      }
    }, success: success);
    // Success, or the member was already removed: show the server's list.
    if (r != null || gone) AppState.i.changed();
    return r != null;
  }

  Future<void> _add() async {
    // The sheet reloads the lists itself once the member is added.
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddMemberSheet(),
    );
    if (name == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: StatusColors.done, size: 40),
        title: Text('$name added'),
        content: Text('Send $name the Family app. They log in once with their name and the last 4 digits '
            'of their phone number, and stay logged in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
          Builder(
            builder: (b) => FilledButton.icon(
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share'),
              onPressed: () async {
                await shareFamilyInvite(b, name: name);
                if (c.mounted) Navigator.pop(c);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(Map m) async {
    final v = await _askName(context, '${m['name'] ?? ''}');
    if (v == null || v == m['name'] || !mounted) return;
    await _change({'action': 'rename', 'id': m['id'], 'name': v}, success: 'Name changed', name: v);
  }

  Future<void> _setPin(Map m) async {
    final pin = await _askPin(context, m['name'] as String? ?? '');
    if (pin == null || !mounted) return;
    await _change({'action': 'set_pin', 'id': m['id'], 'pin': pin},
        success: 'PIN changed – ${m['name']} logs in again with the new PIN');
  }

  Future<void> _unlink(Map m) async {
    final ok = await confirm(context, 'Log out ${m['name']}\'s phone?',
        'They will need to log in again with their name and PIN. Their bookings stay.', ok: 'Log out');
    if (!ok || !mounted) return;
    await _change({'action': 'unlink', 'id': m['id']}, success: '${m['name']}\'s phone logged out');
  }

  Future<void> _remove(Map m) async {
    final ok = await confirm(
      context,
      'Remove ${m['name']}?',
      'Their phone is logged out and their upcoming meal bookings are cancelled. Past bookings stay in History.',
      ok: 'Remove',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _change({'action': 'remove', 'id': m['id']}, success: '${m['name']} removed');
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family members'),
        actions: [
          Builder(
            builder: (b) => IconButton(
              tooltip: 'Share Family app login steps',
              icon: const Icon(Icons.share_rounded),
              onPressed: () => shareFamilyInvite(b),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add member'),
      ),
      body: members == null
          ? (_error != null ? ErrorRetry(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 96 + MediaQuery.paddingOf(context).bottom),
                children: [
                  if (_error != null) StaleNote(error: _error!, onRetry: _load),
                  EntryAnimation(index: 0, child: _IntroCard(count: members.length)),
                  const SizedBox(height: 12),
                  if (members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Column(children: [
                        Icon(Icons.groups_rounded, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No family members yet', style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text('Tap "Add member" for each person who eats at home.', textAlign: TextAlign.center),
                      ]),
                    ),
                  for (final (i, m) in members.indexed)
                    Padding(
                      key: ValueKey(m['id']),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: EntryAnimation(
                        index: i + 1,
                        child: _MemberCard(
                          m: m,
                          onAction: (a) => switch (a) {
                            'rename' => _rename(m),
                            'pin' => _setPin(m),
                            'unlink' => _unlink(m),
                            'share' => shareFamilyInvite(context, name: '${m['name']}'),
                            _ => _remove(m),
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Glass(
      padding: const EdgeInsets.all(16),
      tintColor: accent.withValues(alpha: 0.10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.restaurant_menu_rounded, color: accent, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Meal booking', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Each person installs the Family app and logs in once with their name and the last 4 digits of '
              'their phone number. They book the meals they will eat, and the cook sees how many to cook for.',
              style: tt.bodyMedium,
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (b) => OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => shareFamilyInvite(b),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(count == 0 ? 'Share login steps' : 'Share login steps with the family'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.m, required this.onAction});
  final Map<String, dynamic> m;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final linked = m['linked'] == true;
    final name = '${m['name'] ?? ''}';
    final at = m['linked_at'] as String?;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Glass(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(children: [
        MemberAvatar(name: name, radius: 22, muted: !linked),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 3),
            Row(children: [
              Icon(linked ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 16, color: linked ? StatusColors.done : StatusColors.future),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  linked ? (at == null ? 'Phone linked' : 'Phone linked · ${istDateTime(at)}') : 'Not logged in yet',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: linked ? StatusColors.done : muted,
                  ),
                ),
              ),
            ]),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: 'Actions for $name',
          onSelected: onAction,
          itemBuilder: (_) => [
            if (!linked)
              const PopupMenuItem(
                value: 'share',
                child: ListTile(leading: Icon(Icons.share_rounded), title: Text('Send login steps')),
              ),
            const PopupMenuItem(
              value: 'pin',
              child: ListTile(leading: Icon(Icons.pin_outlined), title: Text('Change PIN')),
            ),
            const PopupMenuItem(
              value: 'rename',
              child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Change name')),
            ),
            if (linked)
              const PopupMenuItem(
                value: 'unlink',
                child: ListTile(leading: Icon(Icons.phonelink_erase_rounded), title: Text('Log out their phone')),
              ),
            const PopupMenuItem(
              value: 'remove',
              child: ListTile(
                leading: Icon(Icons.person_remove_rounded, color: StatusColors.missed),
                title: Text('Remove', style: TextStyle(color: StatusColors.missed)),
              ),
            ),
          ],
        ),
      ]),
    );
  }
}

/// 4-digit numeric PIN field (digits only, big and spaced out).
class _PinField extends StatelessWidget {
  const _PinField({required this.controller, this.onChanged, this.onSubmitted, this.autofocus = false});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
      autofillHints: const <String>[],
      enableSuggestions: false,
      autocorrect: false,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 8),
      decoration: const InputDecoration(
        labelText: 'PIN',
        hintText: '4 digits',
        helperText: 'Use the last 4 digits of their phone number',
        prefixIcon: Icon(Icons.pin_outlined),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// Asks for a new 4-digit PIN for [name]; null when cancelled.
Future<String?> _askPin(BuildContext context, String name) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final ok = RegExp(r'^\d{4}$').hasMatch(ctl.text);
        return AlertDialog(
          title: Text('New PIN for $name'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Their phone will be logged out. They log in again with their name and this PIN.'),
            const SizedBox(height: 16),
            _PinField(
              controller: ctl,
              autofocus: true,
              onChanged: (_) => set(() {}),
              onSubmitted: (v) => ok ? Navigator.pop(c, v) : null,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: ok ? () => Navigator.pop(c, ctl.text) : null, child: const Text('Change PIN')),
          ],
        );
      },
    ),
  );
}

/// Asks for a new name (same rules as Add member); null when cancelled.
Future<String?> _askName(BuildContext context, String current) {
  final ctl = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final v = _cleanName(ctl.text);
        final ok = v.isNotEmpty && v != current;
        return AlertDialog(
          title: const Text('Change name'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('They log in to the Family app with this name.'),
            const SizedBox(height: 16),
            TextField(
              controller: ctl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              maxLength: maxMemberName,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Rahul',
                prefixIcon: Icon(Icons.person_outline_rounded),
                counterText: '',
              ),
              onChanged: (_) => set(() {}),
              onSubmitted: (_) => ok ? Navigator.pop(c, v) : null,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: ok ? () => Navigator.pop(c, v) : null, child: const Text('Save')),
          ],
        );
      },
    ),
  );
}

/// Name + 4-digit PIN. Pops with the added member's name.
class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet();

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  String? _nameError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && RegExp(r'^\d{4}$').hasMatch(_pin.text);

  Future<void> _save() async {
    if (!_valid || _saving) return;
    final name = _cleanName(_name.text);
    setState(() {
      _saving = true;
      _nameError = null;
      _error = null;
    });
    try {
      await Api.call('manage_members', {'action': 'add', 'name': name, 'pin': _pin.text});
      // Reload the lists even if the sheet is no longer open.
      AppState.i.changed();
      if (mounted) Navigator.pop(context, name);
    } catch (e) {
      final f = _friendly(e, name: name);
      if (mounted) {
        setState(() {
          _saving = false;
          if (f.code == 'NAME_TAKEN' || f.code == 'BAD_NAME') {
            _nameError = f.message;
          } else {
            _error = f.message;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    // Stays open while saving, so the result (e.g. "Name taken") is seen.
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add family member', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('They log in to the Family app with this name and PIN.', style: tt.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: maxMemberName,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Rahul',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                errorText: _nameError,
                errorMaxLines: 3,
                counterText: '',
              ),
              onChanged: (_) => setState(() => _nameError = null),
            ),
            const SizedBox(height: 12),
            _PinField(controller: _pin, onChanged: (_) => setState(() {}), onSubmitted: (_) => _save()),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.error_outline_rounded, color: StatusColors.missed, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: const TextStyle(color: StatusColors.missed))),
              ]),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _valid && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add member'),
            ),
          ]),
        ),
      ),
    );
  }
}
