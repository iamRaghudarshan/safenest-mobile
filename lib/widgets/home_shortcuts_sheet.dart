/// Choosing which shortcuts sit under the greeting on Home.
///
/// The row was four hardcoded tiles — Expense, Reminder, Photo, Document —
/// and nothing else could ever be reached from Home. Vault and Notes in
/// particular were two taps away on a screen most people never opened.
///
/// It deliberately mirrors the bottom bar's customiser: a hold on the row
/// opens it, the entries drag to reorder, and the ones not in it are chips to
/// tap. Somebody who has learnt one has learnt both, and a second gesture for
/// the same idea would be a second thing to remember.
library;

import 'package:flutter/material.dart';

import '../customize.dart';
import '../modules.dart';
import '../theme.dart';

/// Everything that may sit on Home, in the order it is offered.
///
/// `kModules` is the seven that share the generic list-and-sheet. Gallery,
/// Documents, Vault, Notes and Habits are screens of their own and are NOT in
/// it — which is exactly why they could never reach Home, and why leaving them
/// out here would have shipped this feature without the thing it was for.
/// `kAllModuleKeys` is the list that holds both halves, and it is what the
/// count below is checked against.
List<({String key, String label, IconData icon, Color colour})> shortcutChoices(
    {Set<String>? allowed}) {
  final out = <({String key, String label, IconData icon, Color colour})>[
    (
      key: 'gallery',
      label: 'Photo',
      icon: Icons.photo_camera,
      colour: kModuleColours['gallery'] ?? Colors.blueGrey
    ),
    (
      key: 'documents',
      label: 'Files',
      icon: Icons.folder,
      colour: kModuleColours['documents'] ?? Colors.teal
    ),
    (
      key: 'vault',
      label: 'Vault',
      icon: Icons.lock_outline,
      colour: kModuleColours['vault'] ?? Colors.indigo
    ),
    (
      key: 'notes',
      label: 'Notes',
      icon: Icons.lightbulb_outline,
      colour: kModuleColours['notes'] ?? Colors.amber
    ),
    (
      key: 'habits',
      label: 'Habits',
      icon: Icons.local_fire_department_outlined,
      colour: kModuleColours['habits'] ?? Colors.deepOrange
    ),
    for (final m in kModules)
      (
        key: m.key,
        label: _short(m.label),
        icon: m.icon,
        colour: m.colour,
      ),
  ];
  if (allowed == null) return out;
  // A shortcut to something this account cannot open is a button that
  // apologises, so it is never offered in the first place.
  return [for (final c in out) if (allowed.contains(c.key)) c];
}

/// Under an icon there is room for one word. "Expenses" is the module; the
/// thing somebody taps this to do is add an expense.
String _short(String label) => switch (label) {
      'Expenses' => 'Expense',
      'Reminders' => 'Reminder',
      'Documents' => 'Files',
      'To-dos' => 'To-do',
      _ => label,
    };

/// Open the sheet. Returns when it closes; the caller rebuilds.
Future<void> showHomeShortcutsSheet(BuildContext context,
    {Set<String>? allowed}) async {
  final choices = shortcutChoices(allowed: allowed);
  final known = {for (final c in choices) c.key: c};

  // Start from what is on Home, keeping only what is still offerable — a
  // module withdrawn from this account must not sit in the editor as a row
  // nobody can explain.
  final chosen = <String>[
    for (final k in Customize.homeShortcuts)
      if (known.containsKey(k)) k,
  ];

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final theme = Theme.of(ctx);
        final available =
            choices.where((c) => !chosen.contains(c.key)).toList();
        final atMin = chosen.length <= Customize.shortcutsMin;
        final atMax = chosen.length >= Customize.shortcutsMax;

        Future<void> save() => Customize.setHomeShortcuts(List.of(chosen));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Shortcuts on Home',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Drag to reorder. ${Customize.shortcutsMin} to '
                    '${Customize.shortcutsMax} — below '
                    '${Customize.shortcutsMin} it is not a row, and above '
                    '${Customize.shortcutsMax} the labels stop fitting.',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(height: 14),

              Flexible(
                child: ReorderableListView(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  // `onReorderItem`, not `onReorder`: it hands back an index
                  // already corrected for the row being lifted out. The old
                  // callback does not, which is why every use of it carries
                  // the same `if (to > from) to -= 1` — a correction that is
                  // silently wrong in one direction the moment somebody
                  // forgets it.
                  onReorderItem: (from, to) {
                    setSheet(() => chosen.insert(to, chosen.removeAt(from)));
                    save();
                  },
                  children: [
                    for (var i = 0; i < chosen.length; i++)
                      _Row(
                        key: ValueKey('chosen-${chosen[i]}'),
                        index: i,
                        item: known[chosen[i]]!,
                        // At the floor nothing may be removed. Disabled rather
                        // than hidden: a control that vanishes reads as a bug,
                        // and the sentence above already says why.
                        onRemove: atMin
                            ? null
                            : () {
                                setSheet(() => chosen.removeAt(i));
                                save();
                              },
                      ),
                  ],
                ),
              ),

              if (available.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(atMax ? 'REMOVE ONE TO ADD ANOTHER' : 'TAP TO ADD',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in available)
                      ActionChip(
                        avatar: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: atMax
                                ? theme.colorScheme.surfaceContainerHighest
                                : c.colour,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(c.icon,
                              size: 14,
                              color: atMax
                                  ? theme.colorScheme.onSurfaceVariant
                                  : Colors.white),
                        ),
                        label: Text(c.label),
                        onPressed: atMax
                            ? null
                            : () {
                                setSheet(() => chosen.add(c.key));
                                save();
                              },
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 16),
              Row(children: [
                OutlinedButton(
                  style: compactButtonStyle,
                  onPressed: () async {
                    await Customize.setHomeShortcuts(const []);
                    setSheet(() {
                      chosen
                        ..clear()
                        ..addAll(Customize.defaultShortcuts
                            .where(known.containsKey));
                    });
                  },
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: compactButtonStyle,
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.index,
    required this.item,
    required this.onRemove,
  });

  final int index;
  final ({String key, String label, IconData icon, Color colour}) item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(Icons.drag_handle,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 11),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.colour,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(item.icon, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(item.label,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: onRemove == null
                ? 'At least ${Customize.shortcutsMin} are needed'
                : 'Remove ${item.label}',
            icon: const Icon(Icons.close, size: 18),
          ),
        ]),
      ),
    );
  }
}
