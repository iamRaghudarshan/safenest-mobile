/// Modules — every part of SafeNest, with what needs attention on it.
///
/// The web app's second tab, and it is not a plain menu: each tile carries its
/// count, and anything wanting attention carries a badge. /api/dashboard already
/// returns moduleTotals and moduleAttention for exactly this, so the phone shows
/// the same numbers the laptop does rather than a list of names.
///
/// The order is the PERSON'S to set: tap Arrange, then drag a tile onto where it
/// should go. The chosen order is saved on the phone (see customize.dart) and
/// survives a new module being added — see Customize.apply.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../customize.dart';
import '../modules.dart';
import '../session.dart';
import '../theme.dart';

typedef _Mod = ({String key, String label, IconData icon, Color colour, String blurb});

class ModulesScreen extends StatefulWidget {
  const ModulesScreen(
      {super.key, required this.onOpen, this.allowed, this.refreshTick = 0});
  final void Function(String key) onOpen;
  final Set<String>? allowed;

  /// Home bumps this when a pushed module returns, so a newly added habit's
  /// count is re-read instead of the tile keeping the number it loaded once.
  final int refreshTick;

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  Map<String, dynamic> _totals = {};
  Map<String, dynamic> _attention = {};
  bool _loading = true;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _load();
    Customize.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    Customize.revision.addListener(_onCustomize);
  }

  @override
  void dispose() {
    Customize.revision.removeListener(_onCustomize);
    super.dispose();
  }

  void _onCustomize() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ModulesScreen old) {
    super.didUpdateWidget(old);
    if (widget.refreshTick != old.refreshTick) _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<Session>().api.get('/api/dashboard');
      if (d is Map && mounted) {
        setState(() {
          _totals = Map<String, dynamic>.from(d['moduleTotals'] ?? {});
          _attention = Map<String, dynamic>.from(d['moduleAttention'] ?? {});
          _loading = false;
        });
        return;
      }
    } catch (_) {/* counts are a nicety; the tiles still work without them */}
    if (mounted) setState(() => _loading = false);
  }

  /// Every module the app can open, in the web app's order — the seven record
  /// ones plus Gallery, Documents and Vault, which are screens of their own.
  List<_Mod> get _all => [
        for (final m in kModules)
          (key: m.key, label: m.label, icon: m.icon, colour: m.colour, blurb: m.blurb),
        (
          key: 'habits',
          label: 'Habits',
          icon: Icons.local_fire_department_outlined,
          colour: kModuleColours['habits']!,
          blurb: 'Build a routine, keep the streak'
        ),
        (
          key: 'gallery',
          label: 'Gallery',
          icon: Icons.photo_library_outlined,
          colour: kModuleColours['gallery']!,
          blurb: 'Your photos, backed up here'
        ),
        (
          key: 'documents',
          label: 'Documents',
          icon: Icons.folder_outlined,
          colour: kModuleColours['documents']!,
          blurb: 'Bills, IDs and paperwork'
        ),
        (
          key: 'vault',
          label: 'Vault',
          icon: Icons.lock_outline,
          colour: kModuleColours['vault']!,
          blurb: 'Passwords, encrypted'
        ),
        (
          key: 'notes',
          label: 'Notes',
          icon: Icons.lightbulb_outline,
          colour: kModuleColours['notes']!,
          blurb: 'Quick notes and checklists'
        ),
      ];

  /// The tiles to show: the saved order, filtered to what this account may see.
  List<_Mod> _tiles() {
    final allowed = widget.allowed;
    final byKey = {for (final m in _all) m.key: m};
    final natural = _all.map((m) => m.key).toList();
    final ordered = Customize.apply(Customize.moduleOrder, natural);
    return [
      for (final k in ordered)
        if (byKey[k] != null && (allowed == null || allowed.contains(k))) byKey[k]!,
    ];
  }

  /// Move [moved] to sit where [onto] is. Reordered across the FULL set of keys,
  /// not just the visible ones, so the saved order stays complete.
  Future<void> _reorder(String moved, String onto) async {
    if (moved == onto) return;
    final natural = _all.map((m) => m.key).toList();
    final order = Customize.apply(Customize.moduleOrder, natural);
    order.remove(moved);
    final idx = order.indexOf(onto);
    order.insert(idx < 0 ? order.length : idx, moved);
    await Customize.setModuleOrder(order);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = _tiles();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modules'),
        actions: [
          if (_editing && Customize.moduleOrder.isNotEmpty)
            TextButton(
              onPressed: () async {
                await Customize.reset();
              },
              child: const Text('Reset'),
            ),
          TextButton.icon(
            onPressed: () => setState(() => _editing = !_editing),
            icon: Icon(_editing ? Icons.check : Icons.tune, size: 18),
            label: Text(_editing ? 'Done' : 'Arrange'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_editing)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: kBrand.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Icon(Icons.drag_indicator, size: 18, color: kBrand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Drag a tile onto where you want it. Your order is '
                      'saved on this phone.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.80,
                ),
                itemCount: tiles.length,
                itemBuilder: (ctx, i) {
                  final m = tiles[i];
                  final count =
                      _totals[m.key] ?? _totals[m.key == 'todos' ? 'todo' : m.key];
                  final attn = (_attention[m.key] ??
                      _attention[m.key == 'todos' ? 'todo' : m.key] ??
                      0) as int;
                  final tile = _ModTile(
                    label: m.label,
                    icon: m.icon,
                    colour: m.colour,
                    count: _loading ? null : count,
                    attention: attn,
                    editing: _editing,
                    onTap: _editing ? null : () => widget.onOpen(m.key),
                  );
                  if (!_editing) return tile;
                  // Drag one tile onto another to drop it into that slot.
                  return DragTarget<String>(
                    onWillAcceptWithDetails: (d) => d.data != m.key,
                    onAcceptWithDetails: (d) => _reorder(d.data, m.key),
                    builder: (ctx, cand, rej) {
                      final hovering = cand.isNotEmpty;
                      return AnimatedScale(
                        scale: hovering ? 1.10 : 1.0,
                        duration: const Duration(milliseconds: 120),
                        child: LongPressDraggable<String>(
                          data: m.key,
                          // A short delay so a scroll is not read as a drag.
                          delay: const Duration(milliseconds: 120),
                          feedback: Material(
                            color: Colors.transparent,
                            child: SizedBox(width: 108, height: 118, child: tile),
                          ),
                          childWhenDragging: Opacity(opacity: 0.25, child: tile),
                          child: tile,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A module tile: a soft card tinted in the module's colour, a large gradient
/// icon chip, the name, and its count. The gradient chip and the tint are what
/// lift it from "a glyph on the background" to something that looks built —
/// each module keeps its own colour identity across the whole screen.
class _ModTile extends StatelessWidget {
  const _ModTile({
    required this.label,
    required this.icon,
    required this.colour,
    required this.count,
    required this.attention,
    required this.onTap,
    this.editing = false,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final Object? count;
  final int attention;
  final VoidCallback? onTap;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final light = Color.lerp(colour, Colors.white, 0.26)!;
    final card = theme.colorScheme.surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: colour.withValues(alpha: dark ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colour.withValues(alpha: 0.16)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [light, colour],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: colour.withValues(alpha: 0.38),
                          blurRadius: 12,
                          offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Icon(icon, size: 28, color: Colors.white),
                ),
                // While arranging, a drag handle in the corner instead of a
                // count badge — it says "this moves" without a word.
                if (editing)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: card,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4),
                        ],
                      ),
                      child: Icon(Icons.drag_indicator,
                          size: 15, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                else if (attention > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: kDanger,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: card, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(attention > 9 ? '9+' : '$attention',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1)),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
              if (count != null && !editing) ...[
                const SizedBox(height: 2),
                Text('$count',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color.lerp(
                            colour, theme.colorScheme.onSurface, 0.25))),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
