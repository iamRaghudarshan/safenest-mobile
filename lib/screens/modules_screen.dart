/// Modules — every part of SafeNest, with what needs attention on it.
///
/// The web app's second tab, and it is not a plain menu: each tile carries its
/// count, and anything wanting attention carries a badge. /api/dashboard already
/// returns moduleTotals and moduleAttention for exactly this, so the phone shows
/// the same numbers the laptop does rather than a list of names.
///
/// Replaces the "Records" screen I invented, which listed seven modules with no
/// counts and left Gallery and Documents out entirely — so it was neither the
/// web app's screen nor a complete one.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../modules.dart';
import '../session.dart';
import '../theme.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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
  List<({String key, String label, IconData icon, Color colour, String blurb})>
      get _all => [
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
          ];

  @override
  Widget build(BuildContext context) {
    final allowed = widget.allowed;
    final tiles = _all
        .where((m) => allowed == null || allowed.contains(m.key))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Modules')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.12,
          ),
          itemCount: tiles.length,
          itemBuilder: (ctx, i) {
            final m = tiles[i];
            final count = _totals[m.key] ?? _totals[m.key == 'todos' ? 'todo' : m.key];
            final attn = (_attention[m.key] ??
                _attention[m.key == 'todos' ? 'todo' : m.key] ??
                0) as int;

            // .mod-tile, transcribed. The differences from what was here
            // before are not small: the icon is a 48px SOLID block of the
            // module's colour with a white glyph, not a 40px tinted circle; the
            // badge sits ON the icon with a ring cut out of the card; and there
            // is a large soft glow bleeding from the top-right corner. That glow
            // is most of the character of the screen, and it was missing
            // entirely.
            return _ModTile(
              label: m.label,
              blurb: m.blurb,
              icon: m.icon,
              colour: m.colour,
              count: count,
              attention: attn,
              loading: _loading,
              onTap: () => widget.onOpen(m.key),
            );
          },
        ),
      ),
    );
  }
}

class _ModTile extends StatelessWidget {
  const _ModTile({
    required this.label,
    required this.blurb,
    required this.icon,
    required this.colour,
    required this.count,
    required this.attention,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final String blurb;
  final IconData icon;
  final Color colour;
  final Object? count;
  final int attention;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final card = theme.colorScheme.surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(dark),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          // Clipped, because the glow is deliberately positioned outside the
          // tile and must be cut off at its rounded edge.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // .mod-glow — 92px circle, offset -30/-30, 12% opacity.
                Positioned(
                  top: -30,
                  right: -30,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // .mod-ic — 48px, radius 14, SOLID colour, white glyph.
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colour,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(icon, size: 24, color: Colors.white),
                          ),
                          if (attention > 0)
                            Positioned(
                              top: -7,
                              right: -7,
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 21),
                                height: 21,
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                decoration: BoxDecoration(
                                  color: kDanger,
                                  borderRadius: BorderRadius.circular(999),
                                  // box-shadow: 0 0 0 2.5px var(--card) — a ring
                                  // punched out of the tile so the badge reads
                                  // as sitting above it.
                                  border: Border.all(color: card, width: 2.5),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  attention > 9 ? '9+' : '$attention',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // .mod-name — 15px, weight 800, tight letter spacing.
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // .mod-metric — 12.5px, weight 600, soft ink.
                      Text(
                        loading || count == null ? blurb : '$count',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
