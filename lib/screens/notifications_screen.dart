/// Notifications — the inbox the web app keeps, on the phone.
///
/// Reads /api/notifications/inbox and marks things read. Push itself is not set
/// up here: that needs a VAPID key exchange and a per-device subscription, and
/// wiring half of it would leave a switch that looks like it works.
///
/// This was a ListTile list divided by hairlines, which is a desktop table —
/// the same thing the record screens were pulled away from. It is cards now,
/// with the kind of message carrying its own colour, because the bell is where
/// a timed reminder arrives and "your card bill is due" and "a message from
/// whoever supplied this" should not look identical.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/pill.dart';
import '../widgets/skeleton.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.initialRows});

  /// For tests, so this screen can be laid out without a server — the same
  /// device the Dashboard and the record lists use.
  final List<Map<String, dynamic>>? initialRows;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  // false shows UNREAD, true shows READ — two separate lists, defaulting to the
  // unread ones (the whole point of opening notifications is what you haven't seen).
  bool _showRead = false;

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
      final d = await context.read<Session>().api.get('/api/notifications/inbox');
      final list = d is List ? d : (d is Map ? (d['items'] ?? const []) : const []);
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

  Future<void> _readAll() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api.post('/api/notifications/inbox/read-all');
      _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// What kind of message this is, in the colour that module already owns.
  /// `kind` is set by push.notify() on the server — 'reminder' for a timed
  /// reminder, 'digest' for the daily summary, 'broadcast' for a message from
  /// the publisher, 'system' for everything the app says about itself.
  ({Color colour, IconData icon, String label}) _kind(String kind) {
    switch (kind) {
      case 'reminder':
        return (
          colour: kModuleColours['reminders']!,
          icon: Icons.notifications_active_outlined,
          label: 'Reminder'
        );
      case 'digest':
        return (
          colour: kBrand,
          icon: Icons.wb_sunny_outlined,
          label: 'Daily summary'
        );
      case 'broadcast':
        return (colour: kWarn, icon: Icons.campaign_outlined, label: 'Message');
      case 'export':
        return (
          colour: kOk,
          icon: Icons.download_outlined,
          label: 'Export'
        );
      default:
        return (colour: kBrand, icon: Icons.info_outline, label: 'SafeNest');
    }
  }

  /// Whether a row is read. The server serialises this as `read` (a bool) via
  /// notifications.py::_item — NOT `is_read`. Reading the wrong key meant every
  /// row came back null → treated as unread, so the list never emptied and
  /// "Mark all read" looked broken even though the server had marked them. Accept
  /// both so it is right whatever version the server is.
  bool _readOf(Map r) => r['read'] == true || (r['is_read'] ?? 0) == 1;

  /// The server sends the time as `at`; older shapes used `created_at`.
  dynamic _atOf(Map r) => r['at'] ?? r['created_at'];

  /// "2h ago", not "2026-08-07T18:30:00". The raw column was going straight to
  /// the screen, which is a timestamp for a database rather than for a person.
  String _when(dynamic raw) {
    final t = DateTime.tryParse('${raw ?? ''}');
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day.toString().padLeft(2, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = _rows.where((r) => !_readOf(r)).length;
    // Unread and Read are two separate lists; show only the chosen half.
    final shown = _rows.where((r) => _readOf(r) == _showRead).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(onPressed: _readAll, child: const Text('Mark all read')),
        ],
        bottom: _rows.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      ChoiceChip(
                        label: Text('Unread${unread > 0 ? ' ($unread)' : ''}'),
                        selected: !_showRead,
                        onSelected: (_) => setState(() => _showRead = false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Read'),
                        selected: _showRead,
                        onSelected: (_) => setState(() => _showRead = true),
                      ),
                    ]),
                  ),
                ),
              ),
      ),
      body: _loading
          ? const SkeletonList()
          : _error != null
              ? _Failed(message: _error!, onRetry: _load)
              : _rows.isEmpty
                  ? const _NothingYet()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: shown.isEmpty
                          ? ListView(children: [
                              Padding(
                                padding: const EdgeInsets.all(48),
                                child: Center(
                                    child: Text(
                                        _showRead
                                            ? 'Nothing read yet'
                                            : 'No unread notifications',
                                        style: theme.textTheme.bodyMedium)),
                              )
                            ])
                          : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                        itemCount: shown.length,
                        itemBuilder: (ctx, i) {
                          final n = shown[i];
                          final read = _readOf(n);
                          final k = _kind('${n['kind'] ?? ''}');
                          final when = _when(_atOf(n));

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: BrandCard(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          // An already-read message steps back
                                          // rather than disappearing: the colour
                                          // is what says "this is new", so a read
                                          // one keeps the shape and loses the
                                          // shout.
                                          color: read
                                              ? k.colour.withValues(alpha: 0.16)
                                              : k.colour,
                                          borderRadius: BorderRadius.circular(13),
                                          boxShadow: read
                                              ? null
                                              : [
                                                  BoxShadow(
                                                    color: k.colour
                                                        .withValues(alpha: 0.32),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                        ),
                                        child: Icon(k.icon,
                                            size: 20,
                                            color: read ? k.colour : Colors.white),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text('${n['title'] ?? ''}',
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: read
                                                        ? FontWeight.w600
                                                        : FontWeight.w800,
                                                  )),
                                              if ('${n['body'] ?? ''}'
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 3),
                                                Text('${n['body']}',
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.bodySmall),
                                              ],
                                            ]),
                                      ),
                                    ]),
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 54),
                                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                                        Pill(k.label, colour: k.colour),
                                        if (!read)
                                          const Pill('New', tone: PillTone.danger),
                                        if (when.isNotEmpty)
                                          Pill(when,
                                              tone: PillTone.muted,
                                              icon: Icons.schedule),
                                      ]),
                                    ),
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
                color: kBrand,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: kBrand.withValues(alpha: 0.38),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.notifications_none,
                  size: 30, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('All caught up',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                  'Reminders that come due, and messages from whoever supplied '
                  'SafeNest, arrive here.',
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

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});
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
            const Text('Can’t load right now',
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
