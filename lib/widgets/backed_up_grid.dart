/// What is backed up, as a grid of tiles with their counts.
///
/// The second panel from the owner's reference. Six tiles rather than the
/// reference's five, because SafeNest holds a different set of things — and
/// each one goes somewhere: a tile that is decoration on a screen full of
/// tappable things is a tile people tap twice and then stop trusting.
///
/// A COUNT OF NOTHING IS STILL A COUNT. A tile reading "0" is more useful than
/// a tile with no number under it: zero photos is a fact about the backup,
/// while a blank is a fact about the app. Only a figure that has genuinely not
/// arrived yet shows nothing, and then the tile is dimmed so the gap is
/// visible rather than silent.
library;

import 'package:flutter/material.dart';

import 'module_tile.dart';

@immutable
class BackedUp {
  const BackedUp({
    required this.key,
    required this.label,
    required this.icon,
    required this.colour,
    required this.count,
    this.onTap,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color colour;

  /// Null while it is still being fetched.
  final int? count;
  final VoidCallback? onTap;
}

class BackedUpGrid extends StatelessWidget {
  const BackedUpGrid({
    super.key,
    required this.items,
    this.title = 'What is backed up',
  });

  final List<BackedUp> items;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
          // A fixed three columns, like the reference. A responsive count would
          // put two tiles on a narrow phone and leave a gap the eye reads as a
          // missing module.
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.92,
            children: [
              for (final it in items)
                Opacity(
                  opacity: it.count == null ? 0.45 : 1,
                  child: ModuleTile(
                    icon: it.icon,
                    colour: it.colour,
                    label: it.label,
                    count: it.count == null ? null : _grouped(it.count!),
                    onTap: it.onTap,
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Indian grouping — 1,780 and 1,24,500. Writing a lakh with Western grouping
/// is the tell that nobody local read the output, and the rest of this app has
/// already been corrected for it twice.
String _grouped(int n) {
  final s = n.abs().toString();
  if (s.length <= 3) return '$n';
  final last3 = s.substring(s.length - 3);
  var head = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) parts.insert(0, head);
  return '${n < 0 ? '-' : ''}${parts.join(',')},$last3';
}
