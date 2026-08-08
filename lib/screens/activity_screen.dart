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
import '../dates.dart';
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

  /// BOTH: "2h ago" and the exact moment it happened.
  ///
  /// It used to be the relative form alone, which answers "was that recent"
  /// and nothing else. The moment you need to tell somebody WHEN a record
  /// changed — or check it against a bank statement, which is most of why this
  /// log exists — "2h ago" is useless, and it gets worse every hour it sits
  /// there. The relative reading is still first because it is what the eye
  /// wants when scanning; the date and time sit under it.
  DateTime? _at(Map<String, dynamic> r) =>
      parseDate('${r['created_at'] ?? r['at'] ?? ''}');

  /// Which part of the app an entry belongs to, in words a person uses.
  ///
  /// The server names the THING — 'photo', 'gallery', 'card' — and the modules
  /// are named for the drawer they live in. `entity_label` is preferred when
  /// the server sent one, because it already knows the difference between a
  /// photo and a policy better than a lookup table here does.
  static const _moduleNames = <String, String>{
    'photo': 'Photos',
    'gallery': 'Photos',
    'album': 'Photos',
    'person': 'Photos',
    'document': 'Documents',
    'vault': 'Vault',
    'card': 'Cards',
    'loan': 'Loans',
    'expense': 'Expenses',
    'insurance': 'Insurance',
    'investment': 'Investments',
    'reminder': 'Reminders',
    'todo': 'To-dos',
    'user': 'Account',
    'licence': 'Licences',
    'license': 'Licences',
    'master': 'Lists',
    'branding': 'Settings',
    'system': 'System',
  };

  String _moduleName(Map<String, dynamic> r) {
    final e = '${r['entity'] ?? ''}'.toLowerCase().trim();
    if (e.isEmpty) return '';
    final known = _moduleNames[e];
    if (known != null) return known;
    final given = '${r['entity_label'] ?? ''}'.trim();
    if (given.isNotEmpty) return given;
    return e[0].toUpperCase() + e.substring(1);
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
                          final label = '${r['label'] ?? ''}';
                          final k = _kind(action);
                          final at = _at(r);
                          // The server writes a proper sentence — "Moved to
                          // trash" — and this screen was deriving "Trash" from
                          // the raw action column instead, ignoring it.
                          final verb = '${r['verb'] ?? ''}'.trim().isEmpty
                              ? _phrase(action)
                              : '${r['verb']}';
                          // WHICH MODULE. Without it a log of forty rows reads
                          // as a list of verbs: "Updated", "Deleted",
                          // "Updated" — with no way to tell a card from a photo
                          // from an insurance policy.
                          final module = _moduleName(r);
                          final who = '${r['by'] ?? ''}'.trim();

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
                                        Row(children: [
                                          // The module, first and tinted in its
                                          // own colour, so a log scanned
                                          // quickly reads as "Photos … Cards …
                                          // Reminders" rather than as a column
                                          // of identical verbs.
                                          if (module.isNotEmpty) ...[
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: k.colour
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(module,
                                                  style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: k.colour)),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          // Flexible, or a long verb beside the
                                          // chip overflows the row.
                                          Flexible(
                                            child: Text(verb,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ),
                                        ]),
                                        if (label.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(ctx)
                                                  .textTheme
                                                  .bodySmall),
                                        ],
                                        const SizedBox(height: 3),
                                        // The exact moment, always — and who
                                        // did it, which matters the instant a
                                        // household has more than one sign-in.
                                        Text(
                                            who.isEmpty
                                                ? fmtDateTime(at)
                                                : '${fmtDateTime(at)} · $who',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(ctx)
                                                .textTheme
                                                .labelSmall),
                                      ]),
                                ),
                                const SizedBox(width: 8),
                                Pill(relative(at), tone: PillTone.muted),
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
