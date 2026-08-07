/// Home — the web app's Dashboard, screen for screen.
///
/// This did not exist in the phone app at all, which is why it felt like a
/// different product: the web app opens on a greeting, what is due, quick
/// actions and a snapshot, and the phone opened straight into a photo grid.
///
/// Same two endpoints as the web app — /api/dashboard and /api/briefing — and
/// the same order down the page:
///
///   greeting · add-an-expense nudge · what is DUE · quick actions ·
///   a memory from this day · Snapshot
///
/// Both fetches are independent and neither is allowed to take the screen down.
/// The web app does the same: a briefing that fails should cost the briefing,
/// not the dues list somebody opened the app to see.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onOpen,
    this.initialData,
    this.initialBrief,
  });

  /// Opens another tab or module by key — 'expenses', 'gallery', 'modules'.
  final void Function(String key) onOpen;

  /// Supplied ONLY by tests, so this screen can be laid out with realistic
  /// content and no server. It exists because the overflow that reached a real
  /// phone — Columns inside Rows inside a ListView, defaulting to
  /// MainAxisSize.max and so trying to fill infinite height — is exactly what a
  /// widget test catches and an analyser never will.
  final Map<String, dynamic>? initialData;
  final Map<String, dynamic>? initialBrief;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _brief;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null || widget.initialBrief != null) {
      _data = widget.initialData;
      _brief = widget.initialBrief;
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    // Deliberately separate try blocks, not one around both.
    try {
      final d = await api.get('/api/dashboard');
      if (d is Map) _data = Map<String, dynamic>.from(d);
    } catch (_) {/* keep whatever was there */}
    try {
      final b = await api.get('/api/briefing');
      if (b is Map) _brief = Map<String, dynamic>.from(b);
    } catch (_) {/* the briefing is a nicety; the dues are not */}
    if (mounted) setState(() => _loading = false);
  }

  /// The same greeting the web app shows, on the same boundaries.
  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<Session>();
    final name = '${session.user?['name'] ?? ''}'.split(' ').first;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final stats = (_data?['stats'] ?? const {}) as Map;
    final upcoming = (_data?['upcoming'] ?? const []) as List;
    // A due date in the past is still due — the server sends negative days for
    // overdue, and dropping them would hide exactly the ones that matter.
    final dues = upcoming.where((u) => (u as Map)['days'] != null).toList();

    return Scaffold(
      // SafeArea, because this is the ONE screen with no AppBar.
      //
      // Every other screen has one, and an AppBar insets itself below the status
      // bar automatically. Home does not — so its content began at y=0, under
      // the clock and behind the notch, with the greeting and the person's own
      // name half-hidden. That is what "the home page is going out of screen"
      // was, and it appears on a phone and on no simulator sized without a
      // notch.
      //
      // bottom: false — the ListView already reserves its own room at the end,
      // and insetting twice would leave a visible gap above the tab bar.
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'Home' : name,
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text(
                        '$_greeting 👋'
                        '${_brief?['date'] != null ? " · ${_brief!['date']}" : ""}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => widget.onOpen('search'),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // The "add an expense" nudge the web app opens with.
            BrandCard(
              onTap: () => widget.onOpen('expenses'),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor:
                      kModuleColours['expenses']!.withValues(alpha: 0.15),
                  child: Icon(Icons.add, color: kModuleColours['expenses']),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add an expense', style: theme.textTheme.titleSmall),
                      Text('Takes a few seconds',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.outline),
              ]),
            ),
            const SizedBox(height: 18),

            if (dues.isNotEmpty) ...[
              _SectionTitle(
                  'Due · ${dues.length} item${dues.length == 1 ? '' : 's'}'),
              const SizedBox(height: 8),
              for (final d in dues) _DueRow(item: Map<String, dynamic>.from(d as Map)),
            ] else
              BrandCard(
                child: Row(children: [
                  const Text('✅', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('All clear!', style: theme.textTheme.titleSmall),
                        Text(
                            'Nothing due right now — bills paid, tasks done. '
                            'Enjoy your day 🎉',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 18),

            // The web app's quick-act row.
            Row(children: [
              _Quick(
                  icon: Icons.receipt_long,
                  label: 'Expense',
                  colour: kModuleColours['expenses']!,
                  onTap: () => widget.onOpen('expenses')),
              _Quick(
                  icon: Icons.notifications,
                  label: 'Reminder',
                  colour: kModuleColours['reminders']!,
                  onTap: () => widget.onOpen('reminders')),
              _Quick(
                  icon: Icons.photo_camera,
                  label: 'Photo',
                  colour: kModuleColours['gallery']!,
                  onTap: () => widget.onOpen('gallery')),
              _Quick(
                  icon: Icons.folder,
                  label: 'Document',
                  colour: kModuleColours['documents']!,
                  onTap: () => widget.onOpen('documents')),
            ]),
            const SizedBox(height: 20),

            _SectionTitle('Snapshot'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: _Stat(
                      label: 'Spent this month',
                      value: _money(stats['monthSpend']),
                      colour: kModuleColours['expenses']!)),
              const SizedBox(width: 10),
              Expanded(
                  child: _Stat(
                      label: 'Came in',
                      value: _money(stats['monthIncome']),
                      colour: kOk)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _Stat(
                      label: 'Outstanding',
                      value: _money(stats['outstanding']),
                      colour: kModuleColours['loans']!)),
              const SizedBox(width: 10),
              Expanded(
                  child: _Stat(
                      label: 'Investments',
                      value: _money(stats['investValue']),
                      colour: kModuleColours['investments']!)),
            ]),
          ],
        ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final days = item['days'] as int?;
    final overdue = days != null && days < 0;
    final when = days == null
        ? ''
        : overdue
            ? '${-days} day${days == -1 ? '' : 's'} overdue'
            : days == 0
                ? 'Today'
                : 'in $days day${days == 1 ? '' : 's'}';
    final module = '${item['module'] ?? ''}';
    final colour = kModuleColours[module] ?? kBrand;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BrandCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
                // Overdue is red regardless of module. It is the one thing on
                // this screen that should not be lost in a palette.
                color: overdue ? kDanger : colour,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['title'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                if (when.isNotEmpty)
                  Text(when,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: overdue ? kDanger : null,
                          fontWeight: overdue ? FontWeight.w600 : null)),
              ],
            ),
          ),
          if (item['due'] != null)
            Text('${item['due']}',
                style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                  color: colour, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.colour});
  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) => BrandCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700, color: colour)),
          ],
        ),
      );
}
