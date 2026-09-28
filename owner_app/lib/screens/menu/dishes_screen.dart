import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/video.dart';
import 'dish_sheet.dart';

/// "My dishes": saved dishes to reuse, with edit and delete.
class DishesScreen extends StatefulWidget {
  const DishesScreen({super.key});

  @override
  State<DishesScreen> createState() => _DishesScreenState();
}

class _DishesScreenState extends State<DishesScreen> {
  List<Map<String, dynamic>>? _dishes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.call('list_dishes');
      if (mounted) {
        setState(() {
          _dishes = (r['dishes'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _delete(Map d) async {
    final ok = await confirm(context, 'Delete "${d['name']}"?',
        'It stays on past menus. You can restore it from History.', ok: 'Delete', danger: true);
    if (!ok || !mounted) return;
    final r = await busy(context, () => Api.call('delete_item', {'entity_type': 'dishes', 'id': d['id']}),
        success: 'Dish deleted');
    if (r != null) {
      AppState.i.changed();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My dishes')),
      body: _dishes == null
          ? (_error != null ? ErrorRetry(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : _dishes!.isEmpty
              ? const Center(child: Text('Dishes you add to a menu are saved here'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _dishes!.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    final d = _dishes![i];
                    return SectionCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        if (d['youtube_url'] != null) ...[
                          YoutubeThumb(url: d['youtube_url'], width: 96, height: 56),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              [
                                'Used ${d['times_used']} time(s)',
                                if ((d['notes'] ?? '').toString().isNotEmpty) '${d['notes']}',
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            if (await showEditDish(context, d)) _load();
                          },
                        ),
                        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(d)),
                      ]),
                    );
                  },
                ),
    );
  }
}
