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
            (
              key: 'notes',
              label: 'Notes',
              icon: Icons.lightbulb_outline,
              colour: kModuleColours['notes']!,
              blurb: 'Quick notes and checklists'
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
          // Three across and compact — an app-launcher grid that fits every
          // module on one screen, rather than the big two-up cards you had to
          // scroll through.
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 14,
            childAspectRatio: 0.82,
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
            return _CompactModTile(
              label: m.label,
              icon: m.icon,
              colour: m.colour,
              count: _loading ? null : count,
              attention: attn,
              onTap: () => widget.onOpen(m.key),
            );
          },
        ),
      ),
    );
  }
}

class _CompactModTile extends StatelessWidget {
  const _CompactModTile({
    required this.label,
    required this.icon,
    required this.colour,
    required this.count,
    required this.attention,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final Object? count;
  final int attention;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = theme.colorScheme.surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(clipBehavior: Clip.none, children: [
            // A solid rounded block of the module's colour, white glyph.
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: colour.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(icon, size: 25, color: Colors.white),
            ),
            if (attention > 0)
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
          const SizedBox(height: 8),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          if (count != null)
            Text('$count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
