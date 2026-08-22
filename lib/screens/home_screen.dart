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
  const _Tab(this.key, this.label, this.icon, this.activeIcon, [this.mod]);
  final String key;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Hidden unless this module is permitted — the `mod` field in App.tsx.
  final String? mod;
}

const _tabs = <_Tab>[
  _Tab('home', 'Home', Icons.home_outlined, Icons.home),
  _Tab('modules', 'Modules', Icons.grid_view_outlined, Icons.grid_view),
  _Tab('expenses', 'Expenses', Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet, 'expenses'),
  _Tab('reminders', 'Reminders', Icons.notifications_outlined,
      Icons.notifications, 'reminders'),
  _Tab('gallery', 'Gallery', Icons.photo_library_outlined, Icons.photo_library,
      'gallery'),
  _Tab('profile', 'Profile', Icons.person_outline, Icons.person),
];

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
    // Offer a newer Android build from the customer's own server, if there is
    // one. Post-frame so there is a Navigator to show the prompt on and so it
    // never delays the home screen appearing; Android-only and silent on error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkForUpdate(context, context.read<Session>());
    });
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
    if (allowed == null) return _tabs;
    return _tabs.where((t) => t.mod == null || allowed.contains(t.mod)).toList();
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
      case 'profile':
        return ProfileScreen(
          brand: widget.brand,
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.activeIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
