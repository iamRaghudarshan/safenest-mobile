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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/brand_button.dart';
import '../widgets/motion.dart';
import '../widgets/nature_backdrop.dart';
import 'notifications_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onOpen,
    this.refreshTick = 0,
    this.initialData,
    this.initialBrief,
  });

  /// Opens another tab or module by key — 'expenses', 'gallery', 'modules'.
  final void Function(String key) onOpen;

  /// Home bumps this when a pushed module returns; a change re-reads the
  /// dashboard so a habit (or anything) added on another screen shows here.
  final int refreshTick;

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

  /// Unread items in the bell.
  ///
  /// The inbox has always been there and always had things in it — reminders
  /// that fired, the daily digest — and the only way to reach it was Profile →
  /// My data → Notifications. Nobody digs three levels into settings to find
  /// out whether something happened; a bell with a number on it is where
  /// everyone looks, so that is where it goes.
  int _unread = 0;

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

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    // A pushed module (a habit added, a bill paid) has returned; re-read so the
    // dues, snapshot and habits-today all reflect it. Tests pass no tick.
    if (widget.refreshTick != old.refreshTick && widget.initialData == null) {
      _load();
    }
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
    try {
      final n = await api.get('/api/notifications/inbox');
      final items = (n is Map ? n['items'] : null) as List? ?? const [];
      _unread = items.where((x) => (x is Map) && x['read'] != true).length;
    } catch (_) {/* a missing badge must not blank the home screen */}
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
            // The greeting now lives over a bounded crop of the app's own nature
            // world, so Home opens on something warm rather than a bare name and
            // a row of icons. A line of copy rotates gently beneath it — the
            // "slide" — and the search / notifications / profile controls move
            // into the banner's corner.
            _GreetingHero(
              name: name,
              greeting: _greeting,
              date: _brief?['date'] != null ? '${_brief!['date']}' : '',
              unread: _unread,
              onSearch: () => widget.onOpen('search'),
              onBell: () => Navigator.of(context)
                  .push(MaterialPageRoute(
                      builder: (_) => const NotificationsScreen()))
                  // Coming back re-reads the count: marking things read in there
                  // must clear the badge out here, or the number is a lie until
                  // the next refresh.
                  .then((_) => _load()),
              onProfile: () => widget.onOpen('profile'),
            ),
            const SizedBox(height: 14),

            // The "add an expense" nudge the web app opens with. Rises in gently
            // on first paint, the same entrance the rest of the kit uses.
            stagger(context, 0, BrandCard(
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
            )),
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

            // Habits today. The count lives in the same /api/dashboard payload
            // (moduleTotals/moduleAttention), so a habit added on its own screen
            // shows here as soon as _refreshTick re-reads it — the home page was
            // the one place a new habit never appeared.
            Builder(builder: (context) {
              final totals = (_data?['moduleTotals'] ?? const {}) as Map;
              final attn = (_data?['moduleAttention'] ?? const {}) as Map;
              final total = (totals['habits'] as num?)?.toInt() ?? 0;
              if (total == 0) return const SizedBox.shrink();
              final todo = (attn['habits'] as num?)?.toInt() ?? 0;
              final word = total == 1 ? 'habit' : 'habits';
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onOpen('habits'),
                  child: BrandCard(
                    child: Row(children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: kModuleColours['habits'],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.local_fire_department,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Habits',
                                style: theme.textTheme.titleSmall),
                            Text(
                                todo == 0
                                    ? 'All done for today · $total $word'
                                    : '$todo of $total to do today',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Icon(todo == 0 ? Icons.check_circle : Icons.chevron_right,
                          color: todo == 0
                              ? kOk
                              : theme.textTheme.bodySmall?.color),
                    ]),
                  ),
                ),
              );
            }),

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

/// The home banner: the greeting and the person's name over a bounded crop of
/// the app's painted nature world, with a line of copy that rotates gently
/// beneath (the "slide") and the search / notifications / profile controls in
/// the corner. No image assets — the scene is the same one painted app-wide.
class _GreetingHero extends StatefulWidget {
  const _GreetingHero({
    required this.name,
    required this.greeting,
    required this.date,
    required this.unread,
    required this.onSearch,
    required this.onBell,
    required this.onProfile,
  });

  final String name;
  final String greeting;
  final String date;
  final int unread;
  final VoidCallback onSearch;
  final VoidCallback onBell;
  final VoidCallback onProfile;

  @override
  State<_GreetingHero> createState() => _GreetingHeroState();
}

class _GreetingHeroState extends State<_GreetingHero> {
  // Kept to what this product actually promises, not motivational filler. A
  // line a person reads once and nods at, then it moves on.
  static const _lines = [
    'Everything in one place, on your own computer.',
    'Private by design — your records never leave here.',
    'Backed up, organised, and yours.',
    'Have a calm, organised day.',
  ];

  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 6s: long enough to read a line, gentle enough not to nag. A real clock is
    // fine here — this is the app, not the resume-sensitive build tooling.
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _lines.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 156,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: softShadow(dark),
      ),
      child: Stack(fit: StackFit.expand, children: [
        const NatureBackdrop(),
        // A soft scrim into the lower-left, where the words sit — so white text
        // stays readable whether the crop lands on sky, snow or lake.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Colors.black.withValues(alpha: 0.02),
                Colors.black.withValues(alpha: 0.42),
              ],
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Row(children: [
            _HeroIcon(icon: Icons.search, onTap: widget.onSearch),
            _HeroIcon(
                icon: Icons.notifications_outlined,
                onTap: widget.onBell,
                badge: widget.unread),
            const SizedBox(width: 2),
            Avatar(size: 36, onTap: widget.onProfile),
            const SizedBox(width: 6),
          ]),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.greeting} 👋'
                '${widget.date.isNotEmpty ? '  ·  ${widget.date}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 4)]),
              ),
              const SizedBox(height: 1),
              Text(
                widget.name.isEmpty ? 'Welcome' : widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
              ),
              const SizedBox(height: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: Text(
                  _lines[_i],
                  key: ValueKey<int>(_i),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      shadows: const [
                        Shadow(color: Colors.black45, blurRadius: 4)
                      ]),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// A white icon button for the hero corner, with the notifications count on it.
class _HeroIcon extends StatelessWidget {
  const _HeroIcon(
      {required this.icon, required this.onTap, this.badge = 0});

  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Stack(clipBehavior: Clip.none, children: [
        Icon(icon,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black38, blurRadius: 4)]),
        if (badge > 0)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 15),
              decoration: BoxDecoration(
                color: kDanger,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    height: 1.25,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ]),
    );
  }
}
