import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';

/// Who booked one meal in the Family app: `get_menu`'s `slot.bookings`
/// (`{count, people: [{name, note}]}`).
class Bookings {
  const Bookings(this.count, this.people);
  final int count;
  final List<({String name, String? note})> people;

  /// The bookings of a `get_menu` slot, or null when the reply has none (a
  /// copy saved before family bookings existed).
  static Bookings? of(Object? slot) {
    final b = slot is Map ? slot['bookings'] : null;
    if (b is! Map) return null;
    final raw = b['people'];
    final people = [
      if (raw is List)
        for (final p in raw)
          if (p is Map)
            (
              name: '${p['name'] ?? ''}',
              note: (p['note'] ?? '').toString().trim().isEmpty ? null : '${p['note']}'.trim(),
            ),
    ];
    final count = b['count'];
    return Bookings(count is num ? count.toInt() : int.tryParse('$count') ?? people.length, people);
  }

  bool get hasNotes => people.any((p) => p.note != null);

  /// "4 eating: Rahul, Priya, …"
  String get summary => count == 0 ? 'No one has booked yet' : '$count eating: ${people.map((p) => p.name).join(', ')}';
}

/// Row under a slot's dishes: how many are eating and who. Tap for each
/// person's note.
class BookingsRow extends StatelessWidget {
  const BookingsRow({super.key, required this.bookings, required this.title});
  final Bookings bookings;

  /// Heading of the sheet, e.g. "Evening · Tue, 30 Sep 2026".
  final String title;

  @override
  Widget build(BuildContext context) {
    final b = bookings;
    final none = b.count == 0;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Semantics(
      button: !none,
      label: none ? 'No one has booked yet' : '${b.count} eating. Show who',
      excludeSemantics: true,
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: none ? null : () => showBookingsSheet(context, bookings: b, title: title),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (none ? StatusColors.future : accent).withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.restaurant_rounded, size: 19, color: none ? StatusColors.future : accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: none
                ? Text('No one has booked yet', style: TextStyle(color: muted, fontWeight: FontWeight.w600))
                : Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${b.count} eating', style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: ': ${b.people.map((p) => p.name).join(', ')}'),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          if (b.hasNotes) ...[
            const SizedBox(width: 6),
            Icon(Icons.sticky_note_2_outlined, size: 18, color: muted),
          ],
          if (!none) const Icon(Icons.chevron_right),
        ]),
      ),
    );
  }
}

/// Everyone who booked this meal, with their notes (e.g. "no onion").
Future<void> showBookingsSheet(BuildContext context, {required Bookings bookings, required String title}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      final tt = Theme.of(c).textTheme;
      final people = bookings.people;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: people.length > 5 ? 0.6 : 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(c).bottom),
          children: [
            Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(bookings.count == 1 ? '1 person eating' : '${bookings.count} people eating', style: tt.bodyMedium),
            const SizedBox(height: 16),
            if (people.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No one has booked yet')),
              ),
            for (final (i, p) in people.indexed)
              EntryAnimation(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Glass(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      MemberAvatar(name: p.name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SizedBox(height: 2),
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          if (p.note != null) ...[
                            const SizedBox(height: 4),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(Icons.sticky_note_2_outlined, size: 16, color: Theme.of(c).colorScheme.primary),
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(p.note!, style: tt.bodyMedium)),
                            ]),
                          ],
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Round initial for a family member.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.name, this.radius = 18, this.muted = false});
  final String name;
  final double radius;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final initial = t.isEmpty ? '?' : t.characters.first.toUpperCase();
    final color = muted ? StatusColors.future : accent;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.16),
      child: Text(initial,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: radius * 0.9, color: muted ? null : Theme.of(context).colorScheme.primary)),
    );
  }
}
