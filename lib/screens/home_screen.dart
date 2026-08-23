/// The shell — the web app's tab bar, tab for tab.
///
/// The first version had four tabs of my own invention (Photos, Documents,
/// Records, You) and opened on a photo grid. The web app has SIX and opens on a
/// dashboard, so the two products did not even share a shape: nothing was where
/// somebody who uses the laptop version would reach for it.
///
///   Home · Modules · Expenses · Reminders · Gallery · Profile
///
/// PERMISSION-GATED, as in App.tsx: a tab with a `mod` is only shown when that
/// module is allowed, because `guard()` refuses at the API. Showing a tab that
/// answers 403 reads as the app being broken rather than the account being
/// limited.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../customize.dart';
import '../modules.dart';
import '../session.dart';
import '../theme.dart';
import '../update.dart';
import 'dashboard_screen.dart';
import 'documents_screen.dart';
import 'notes_screen.dart';
import 'habits_screen.dart';
import 'module_list_screen.dart';
import 'modules_screen.dart';
import 'photos_home.dart';
import 'search_screen.dart';
import 'vault_screen.dart';
import 'profile_screen.dart';

class _Tab {
  const _Tab(this.key, this.label, this.icon, this.activeIcon, this.colour,
      [this.mod]);
  final String key;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Each tab keeps its own colour in the bottom bar, always — not a wall of
  /// grey with one tinted item. It makes the bar read at a glance and matches
  /// the colourful module tiles.
  final Color colour;

  /// Hidden unless this module is permitted — the `mod` field in App.tsx.
  final String? mod;
}

/// Every tab that MAY go in the bottom bar — the six standard ones plus a few
/// more the person can add. Each has a screen (see _screenFor). Which of these
/// actually show, and in what order, is the person's choice (Customize.navBar);
/// the default is _defaultBar.
const _allTabs = <_Tab>[
  _Tab('home', 'Home', Icons.home_outlined, Icons.home, Color(0xFF0176D3)),
  _Tab('modules', 'Modules', Icons.grid_view_outlined, Icons.grid_view,
      Color(0xFF6366F1)),
  _Tab('expenses', 'Expenses', Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet, Color(0xFFF59E0B), 'expenses'),
  _Tab('reminders', 'Reminders', Icons.notifications_outlined,
      Icons.notifications, Color(0xFF8B5CF6), 'reminders'),
  _Tab('gallery', 'Gallery', Icons.photo_library_outlined, Icons.photo_library,
      Color(0xFFF43F5E), 'gallery'),
  _Tab('profile', 'Profile', Icons.person_outline, Icons.person,
      Color(0xFF10B981)),
  // Addable extras — off by default, each opens its own screen as a tab.
  _Tab('notes', 'Notes', Icons.lightbulb_outline, Icons.lightbulb,
      Color(0xFFF5B301), 'notes'),
  _Tab('documents', 'Documents', Icons.folder_outlined, Icons.folder,
      Color(0xFF0D9488), 'documents'),
  _Tab('habits', 'Habits', Icons.local_fire_department_outlined,
      Icons.local_fire_department, Color(0xFFF97316), 'habits'),
  _Tab('vault', 'Vault', Icons.lock_outline, Icons.lock,
      Color(0xFF64748B), 'vault'),
];

/// The bar as it ships, before anyone customises it.
const _defaultBar = ['home', 'modules', 'expenses', 'reminders', 'gallery', 'profile'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.brand,
    this.themeMode = ThemeMode.system,
    this.onThemeChanged,
  });
  final Brand brand;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  // Bumped when a pushed module returns, so the Home and Modules count tiles
  // re-read the dashboard instead of showing a number that is now stale.
  int _refreshTick = 0;
  Set<String>? _allowed;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    // The person's own tab order, if they have set one. Rebuild when it loads or
    // changes so the bar follows a reorder without a restart.
    Customize.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    Customize.revision.addListener(_onCustomize);
    // Offer a newer Android build from the customer's own server, if there is
    // one. Post-frame so there is a Navigator to show the prompt on and so it
    // never delays the home screen appearing; Android-only and silent on error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkForUpdate(context, context.read<Session>());
    });
  }

  @override
  void dispose() {
    Customize.revision.removeListener(_onCustomize);
    super.dispose();
  }

  void _onCustomize() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPermissions() async {
    try {
      final me = await context.read<Session>().api.get('/api/auth/me');
      final map = me is Map ? Map<String, dynamic>.from(me) : <String, dynamic>{};
      final user =
          map['user'] is Map ? Map<String, dynamic>.from(map['user'] as Map) : map;

      if (user['role'] == 'admin') {
        setState(() => _allowed = kAllModuleKeys);
        return;
      }
      final perms = map['modules'] ?? map['permissions'] ?? user['modules'];
      final allowed = <String>{};
      if (perms is List) {
        for (final p in perms) {
          if (p is String) allowed.add(p);
          if (p is Map && p['module_key'] != null && (p['can_view'] ?? 1) == 1) {
            allowed.add(p['module_key'] as String);
          }
        }
      } else if (perms is Map) {
        perms.forEach((k, v) {
          if (v == true || (v is Map && (v['can_view'] ?? 1) == 1)) allowed.add('$k');
        });
      }
      setState(() => _allowed = allowed.isEmpty
          ? kAllModuleKeys
          : allowed);
    } on ApiError {
      // Unreachable is not the same as forbidden. Showing everything means the
      // server still refuses what it should; hiding everything would leave a
      // person staring at two tabs wondering what happened to their app.
      setState(() => _allowed = kAllModuleKeys);
    }
  }

  List<_Tab> get _visible {
    final allowed = _allowed;
    final byKey = {for (final t in _allTabs) t.key: t};
    // The person's chosen bar, or the default set. Then drop anything this
    // account is not permitted to see.
    final chosen = Customize.navBar.isNotEmpty ? Customize.navBar : _defaultBar;
    final out = <_Tab>[];
    for (final k in chosen) {
      final t = byKey[k];
      if (t == null) continue;
      if (t.mod != null && allowed != null && !allowed.contains(t.mod)) continue;
      out.add(t);
    }
    // Never strand the person: Profile carries the customise screen, so it is
    // always reachable, and the bar is never empty.
    if (!out.any((t) => t.key == 'profile')) out.add(byKey['profile']!);
    if (out.isEmpty) {
      return [for (final k in _defaultBar) if (byKey[k] != null) byKey[k]!];
    }
    return out;
  }

  /// Jump to a tab by key, or push a module that has no tab of its own.
  ///
  /// Anything PUSHED (Habits, Documents, Gallery, Vault, a record list) can
  /// change a count while it is open — add a habit and the Home and Modules
  /// tiles were left showing the old number, because an IndexedStack keeps those
  /// tabs alive and they had loaded once. Bumping `_refreshTick` on return makes
  /// both re-read /api/dashboard, so a habit added on its own screen shows up the
  /// moment you come back.
  Future<void> _open(String key) async {
    final i = _visible.indexWhere((t) => t.key == key);
    if (i >= 0) {
      setState(() => _index = i);
      return;
    }
    final spec = moduleByKey(key);
    if (spec != null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ModuleListScreen(spec: spec)));
      if (mounted) setState(() => _refreshTick++);
      return;
    }
    // The screens that are not record modules. Gallery was missing here as well
    // as from the allow-set, so there was no second way in either: tapping
    // Gallery on the Modules grid, or the Dashboard shortcut, fell through this
    // method and did nothing at all. A tap that produces no result and no error
    // is the hardest kind of broken to report.
    switch (key) {
      case 'habits':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const HabitsScreen()));
        if (mounted) setState(() => _refreshTick++);
      case 'documents':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const DocumentsScreen()));
        if (mounted) setState(() => _refreshTick++);
      case 'gallery':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PhotosHome()));
      case 'vault':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const VaultScreen()));
      case 'notes':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const NotesScreen()));
        if (mounted) setState(() => _refreshTick++);
      case 'search':
        // The Dashboard has had a search button since it was written and this
        // switch had no case for it — no tab, no ModuleSpec, no branch — so it
        // fell straight through and did NOTHING. The same shape as the Gallery
        // tile: a control that is plainly there and silently inert.
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SearchScreen(onOpen: _open)));
    }
  }

  Widget _screenFor(_Tab t) {
    switch (t.key) {
      case 'home':
        return DashboardScreen(onOpen: _open, refreshTick: _refreshTick);
      case 'modules':
        return ModulesScreen(
            onOpen: _open, allowed: _allowed, refreshTick: _refreshTick);
      case 'expenses':
        return ModuleListScreen(spec: moduleByKey('expenses')!, embedded: true);
      case 'reminders':
        return ModuleListScreen(spec: moduleByKey('reminders')!, embedded: true);
      case 'gallery':
        return const PhotosHome();
      // The addable extras, when the person has put them in the bar. Each is the
      // same screen they open from the Modules grid.
      case 'notes':
        return const NotesScreen();
      case 'documents':
        return const DocumentsScreen();
      case 'habits':
        return const HabitsScreen();
      case 'vault':
        return const VaultScreen();
      case 'profile':
        return ProfileScreen(
          brand: widget.brand,
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
          onCustomiseNav: _customiseNav,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _visible;
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      // IndexedStack so each tab keeps its scroll position and its loaded data.
      // Rebuilding the gallery every time somebody checks Home would mean
      // scrolling back through thousands of photos.
      body: IndexedStack(
        index: index,
        children: [for (final t in tabs) _screenFor(t)],
      ),
      bottomNavigationBar: _ColourfulNavBar(
        tabs: tabs,
        index: index,
        onTap: (i) => setState(() => _index = i),
        // Press and hold anywhere on the bar to customise it.
        onCustomise: _customiseNav,
      ),
    );
  }

  /// Customise the bottom bar: add tabs, remove tabs, and drag to reorder.
  /// A hold on the bar opens this, as does Profile → Personalise. Stored on the
  /// phone (customize.dart), so it survives restarts and never leaves the device.
  Future<void> _customiseNav() async {
    final allowed = _allowed;
    // Only offer tabs this account may actually see.
    bool permitted(_Tab t) =>
        t.mod == null || allowed == null || allowed.contains(t.mod);
    final byKey = {for (final t in _allTabs) t.key: t};

    // Start from the current bar (chosen set, or default), keeping only permitted.
    final inBar = <String>[
      for (final k in (Customize.navBar.isNotEmpty ? Customize.navBar : _defaultBar))
        if (byKey[k] != null && permitted(byKey[k]!)) k,
    ];
    if (!inBar.contains('profile')) inBar.add('profile');

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final available = _allTabs
              .where((t) => permitted(t) && !inBar.contains(t.key))
              .toList();
          Widget chip(_Tab t) => Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.colour.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(t.activeIcon, color: t.colour, size: 20),
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text('Customise the bar', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await Customize.setNavBar(const []);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Reset'),
                  ),
                ]),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Add or remove tabs, and drag to reorder. '
                      '${Customize.navBarMin}–${Customize.navBarMax} tabs.',
                      style: theme.textTheme.bodySmall),
                ),
                const SizedBox(height: 10),
                // In the bar — reorderable, each removable (except Profile).
                Flexible(
                  child: ReorderableListView(
                    shrinkWrap: true,
                    buildDefaultDragHandles: true,
                    // ignore: deprecated_member_use
                    onReorder: (a, b) => setSheet(() {
                      if (b > a) b -= 1;
                      inBar.insert(b, inBar.removeAt(a));
                    }),
                    children: [
                      for (final k in inBar)
                        ListTile(
                          key: ValueKey(k),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: chip(byKey[k]!),
                          title: Text(byKey[k]!.label),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            // Profile stays — it is the way back to this screen.
                            if (k != 'profile' && inBar.length > Customize.navBarMin)
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: kDanger, size: 22),
                                onPressed: () =>
                                    setSheet(() => inBar.remove(k)),
                              ),
                            const Icon(Icons.drag_handle, size: 20),
                          ]),
                        ),
                    ],
                  ),
                ),
                if (available.isNotEmpty) ...[
                  const Divider(height: 22),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Add to the bar',
                        style: theme.textTheme.labelLarge),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in available)
                        ActionChip(
                          avatar: Icon(t.icon, size: 18, color: t.colour),
                          label: Text(t.label),
                          onPressed: inBar.length >= Customize.navBarMax
                              ? null
                              : () => setSheet(() => inBar.add(t.key)),
                        ),
                    ],
                  ),
                  if (inBar.length >= Customize.navBarMax)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('That is the most the bar holds — remove one first.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: kDanger)),
                    ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await Customize.setNavBar(inBar);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// A fully colourful bottom bar: EVERY tab is a gradient colour chip with a
/// white glyph, not a wall of grey with one tinted item. The selected chip is
/// larger with a glow and a bold coloured label; the bar itself picks up a faint
/// wash of the active tab's colour so the whole footer reads as alive. Press and
/// hold anywhere to rearrange the tabs.
class _ColourfulNavBar extends StatelessWidget {
  const _ColourfulNavBar(
      {required this.tabs,
      required this.index,
      required this.onTap,
      required this.onCustomise});
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onCustomise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colourful = Customize.colourfulNav;
    final active = tabs.isEmpty ? theme.colorScheme.primary : tabs[index].colour;
    return GestureDetector(
      onLongPress: onCustomise,
      child: Container(
        decoration: BoxDecoration(
          // Colourful: a faint wash of the active tab's colour up into the bar.
          // Plain: a flat surface, like a standard tab bar.
          color: colourful ? null : theme.colorScheme.surface,
          gradient: colourful
              ? LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    active.withValues(alpha: dark ? 0.24 : 0.12),
                    theme.colorScheme.surface,
                  ],
                )
              : null,
          border: Border(
              top: BorderSide(
                  color: colourful
                      ? active.withValues(alpha: 0.20)
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.30 : 0.06),
                blurRadius: 14,
                offset: const Offset(0, -3)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 70,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _NavItem(
                      tab: tabs[i],
                      selected: i == index,
                      onTap: () => onTap(i),
                      onLongPress: onCustomise,
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

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.tab,
      required this.selected,
      required this.onTap,
      required this.onLongPress});
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = tab.colour;
    final colourful = Customize.colourfulNav;

    // Plain style: a simple monochrome icon that tints to the tab's colour when
    // selected, sitting on a soft pill — a standard, quiet tab bar for people
    // who would rather not have the colour chips.
    final Widget glyph = colourful
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: selected ? 46.0 : 40.0,
            height: selected ? 46.0 : 40.0,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(colour, Colors.white, 0.24)!, colour],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                    color: colour.withValues(alpha: selected ? 0.45 : 0.24),
                    blurRadius: selected ? 12 : 6,
                    offset: Offset(0, selected ? 5 : 3)),
              ],
            ),
            child: Icon(selected ? tab.activeIcon : tab.icon,
                size: selected ? 24 : 22, color: Colors.white),
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
                horizontal: selected ? 16 : 10, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? colour.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(selected ? tab.activeIcon : tab.icon,
                size: 24,
                color: selected ? colour : theme.colorScheme.onSurfaceVariant),
          );

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          glyph,
          const SizedBox(height: 4),
          Text(
            tab.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? colour : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
