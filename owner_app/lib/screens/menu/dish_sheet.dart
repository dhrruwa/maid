import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/youtube.dart';
import '../../widgets/common.dart';

/// The dishes of a `list_dishes` reply (null stays null).
List<Map<String, dynamic>>? parseDishes(Map<String, dynamic>? r) =>
    r == null ? null : (r['dishes'] as List).map((e) => Map<String, dynamic>.from(e)).toList();

/// Pick a saved dish or create a new one. Returns {dish_id, name, notes} or null.
Future<Map<String, dynamic>?> showDishPicker(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.9, child: _DishPicker()),
  );
}

class _DishPicker extends StatefulWidget {
  const _DishPicker();

  @override
  State<_DishPicker> createState() => _DishPickerState();
}

class _DishPickerState extends State<_DishPicker> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>>? _dishes;
  String _q = '';

  @override
  void initState() {
    super.initState();
    // Saved list at once, then the fresh one.
    final saved = parseDishes(Api.cached('list_dishes'));
    if (saved != null) _show(saved);
    Api.read('list_dishes').then((r) {
      if (mounted) setState(() => _show(parseDishes(r)!));
    }).catchError((e) {
      if (mounted) setState(() => _dishes ??= []);
    });
  }

  void _show(List<Map<String, dynamic>> list) {
    // Only jump to "New dish" when the first list shown is empty, not under the user's finger later.
    if (_dishes == null && list.isEmpty) _tabs.index = 1;
    _dishes = list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = (_dishes ?? [])
        .where((d) => '${d['name']}'.toLowerCase().contains(_q.toLowerCase()))
        .toList()
      ..sort((a, b) => (b['times_used'] as num).compareTo(a['times_used'] as num));
    return Column(children: [
      TabBar(controller: _tabs, tabs: const [Tab(text: 'My dishes'), Tab(text: 'New dish')]),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search dishes'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: _dishes == null
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('No saved dishes yet – add a new one'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final d = filtered[i];
                            final thumb = youtubeThumb(d['youtube_url']);
                            return ListTile(
                              leading: thumb != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(thumb, width: 56, height: 40, fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const Icon(Icons.ondemand_video)),
                                    )
                                  : const Icon(Icons.restaurant_rounded),
                              title: Text('${d['name']}'),
                              subtitle: Text('Used ${d['times_used']} time(s)'),
                              trailing: const Icon(Icons.add_circle_outline),
                              onTap: () => Navigator.pop(context, {
                                'dish_id': d['id'],
                                'name': d['name'],
                                'notes': null,
                              }),
                            );
                          },
                        ),
            ),
          ]),
          const _NewDishForm(),
        ]),
      ),
    ]);
  }
}

class _NewDishForm extends StatefulWidget {
  const _NewDishForm();

  @override
  State<_NewDishForm> createState() => _NewDishFormState();
}

class _NewDishFormState extends State<_NewDishForm> {
  final _name = TextEditingController();
  final _yt = TextEditingController();
  final _dishNotes = TextEditingController();
  final _mealNotes = TextEditingController();

  String? get _ytError {
    final v = _yt.text.trim();
    if (v.isEmpty) return null;
    return youtubeId(v) == null ? 'This is not a YouTube link' : null;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _ytError != null) return;
    final r = await busy(context, () => Api.call('save_dish', {
          'name': _name.text.trim(),
          'youtube_url': _yt.text.trim(),
          'notes': _dishNotes.text.trim(),
        }));
    if (r == null || !mounted) return;
    Navigator.pop(context, {
      'dish_id': r['dish']['id'],
      'name': r['dish']['name'],
      'notes': _mealNotes.text.trim().isEmpty ? null : _mealNotes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final thumb = youtubeThumb(_yt.text);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Dish name', hintText: 'e.g. Palak Paneer'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _yt,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'YouTube link (optional)',
            hintText: 'Paste a recipe video link',
            errorText: _ytError,
            prefixIcon: const Icon(Icons.smart_display_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (thumb != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(thumb, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(child: Icon(Icons.ondemand_video, size: 40))),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _dishNotes,
          decoration: const InputDecoration(labelText: 'Dish notes (saved with the dish)', hintText: 'e.g. Use less oil'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mealNotes,
          decoration: const InputDecoration(labelText: 'Notes for this meal only', hintText: 'e.g. Make for 4 people'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || _ytError != null ? null : _save,
          child: const Text('Save to My dishes & add'),
        ),
      ],
    );
  }
}

/// Edit an existing dish (used from My dishes).
Future<bool> showEditDish(BuildContext context, Map<String, dynamic> dish) async {
  final name = TextEditingController(text: '${dish['name']}');
  final yt = TextEditingController(text: '${dish['youtube_url'] ?? ''}');
  final notes = TextEditingController(text: '${dish['notes'] ?? ''}');
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final bad = yt.text.trim().isNotEmpty && youtubeId(yt.text) == null;
        return AlertDialog(
          title: const Text('Edit dish'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(
              controller: yt,
              decoration: InputDecoration(labelText: 'YouTube link', errorText: bad ? 'Not a YouTube link' : null),
              onChanged: (_) => set(() {}),
            ),
            const SizedBox(height: 10),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: bad ? null : () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return false;
  final r = await busy(context, () => Api.call('save_dish', {
        'id': dish['id'],
        'name': name.text.trim(),
        'youtube_url': yt.text.trim(),
        'notes': notes.text.trim(),
      }), success: 'Dish saved');
  return r != null;
}
