/// The activity log — what has happened in this copy, newest first.
///
/// Reads the same /api/activity the web app does. It is worth having on a phone
/// for one reason above the others: it is where you look when something has
/// changed and you did not change it.
///
/// Which is exactly why it was the wrong screen to render as a wall of grey
/// hairline-divided rows with raw ISO timestamps. A log is scanned, not read —
/// you are looking for the one entry that is a deletion, or the one that
/// happened at a time you were not at the machine.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/pill.dart';
import '../widgets/skeleton.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.initialRows});

  /// For tests — lay the screen out without a server.
  final List<Map<String, dynamic>>? initialRows;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialRows != null) {
      _rows = widget.initialRows!;
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/activity', {'limit': '200'});
      final list = d is List ? d : (d is Map ? (d['items'] ?? d['rows'] ?? const []) : const []);
      setState(() {
        _rows = [for (final e in (list as List)) Map<String, dynamic>.from(e as Map)];
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// A colour AND a glyph per kind of action.
  ///
  /// Deleting is the one worth spotting from across a list: it is the only
  /// entry here that means something is gone.
  ({Color colour, IconData icon}) _kind(String action) {
    if (action.contains('delete') || action.contains('revoke')) {
      return (colour: kDanger, icon: Icons.delete_outline);
    }
    if (action.contains('create') || action.contains('upload')) {
      return (colour: kOk, icon: Icons.add);
    }
    if (action.contains('login') || action.contains('password')) {
      return (colour: kBrand, icon: Icons.lock_outline);
    }
    if (action.contains('done') || action.contains('paid')) {
      return (colour: kOk, icon: Icons.check);
    }
    return (colour: kWarn, icon: Icons.edit_outlined);
  }

  /// "2h ago", not the raw column. A log is read to answer "when", and an ISO
  /// timestamp makes the person do the arithmetic themselves.
  String _when(dynamic raw) {
    final t = DateTime.tryParse('${raw ?? ''}');
    if (t == null) return '${raw ?? ''}';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day.toString().padLeft(2, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-${t.year}';
  }

  /// "card_paid" -> "Card paid".
  String _phrase(String action) {
    final w = action.replaceAll('_', ' ').trim();
    return w.isEmpty ? 'Changed' : w[0].toUpperCase() + w.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: _loading
          ? const SkeletonList()
          : _error != null
              ? _Problem(message: _error!, onRetry: _load)
              : _rows.isEmpty
                  ? const _NothingYet()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                        itemCount: _rows.length,
                        itemBuilder: (ctx, i) {
                          final r = _rows[i];
                          final action = '${r['action'] ?? ''}';
                          final label = '${r['label'] ?? r['entity'] ?? ''}';
                          final k = _kind(action);
                          final when = _when(r['created_at'] ?? r['at']);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: BrandCard(
                              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                              child: Row(children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: k.colour.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(k.icon, size: 19, color: k.colour),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_phrase(action),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w700)),
                                        if (label.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(ctx)
                                                  .textTheme
                                                  .bodySmall),
                                        ],
                                      ]),
                                ),
                                const SizedBox(width: 8),
                                Pill(when, tone: PillTone.muted),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 40, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: kModuleColours['insurance'],
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: kModuleColours['insurance']!.withValues(alpha: 0.38),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.receipt_long_outlined,
                  size: 30, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('Nothing recorded yet',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                  'Everything added, edited or deleted appears here, so you can '
                  'always see what changed and when.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ]),
        )
      ]);
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 40, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: kWarn.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Center(
                  child: Text('📡', style: TextStyle(fontSize: 30))),
            ),
            const SizedBox(height: 16),
            const Text('Can’t load the log',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 190),
              child: BrandButton(label: 'Try again', onPressed: onRetry),
            ),
          ]),
        )
      ]);
}
