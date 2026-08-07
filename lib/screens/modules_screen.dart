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
import '../widgets/brand_button.dart';

class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key, required this.onOpen, this.allowed});
  final void Function(String key) onOpen;
  final Set<String>? allowed;

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
            childAspectRatio: 1.28,
          ),
          itemCount: tiles.length,
          itemBuilder: (ctx, i) {
            final m = tiles[i];
            final count = _totals[m.key] ?? _totals[m.key == 'todos' ? 'todo' : m.key];
            final attn = (_attention[m.key] ??
                _attention[m.key == 'todos' ? 'todo' : m.key] ??
                0) as int;

            return BrandCard(
              onTap: () => widget.onOpen(m.key),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: m.colour.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(m.icon, color: m.colour, size: 21),
                    ),
                    const Spacer(),
                    // The badge the web app puts on the Modules tab, per module:
                    // a count of things actually wanting attention. Red because
                    // it means overdue, not merely "some".
                    if (attn > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: kDanger,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(attn > 9 ? '9+' : '$attn',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const Spacer(),
                  Text(m.label,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    _loading || count == null ? m.blurb : '$count',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
