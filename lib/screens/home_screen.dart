/// The shell: Photos, Documents, Records, Profile.
///
/// Four destinations rather than the web app's ten modules, because a phone is
/// not a settings screen. The eight record modules — expenses, loans, cards,
/// insurance, investments, vault, reminders, to-dos — live behind Records rather
/// than each owning a tab; on a laptop a wide sidebar can afford ten entries and
/// a thumb cannot.
///
/// Photos is first, and deliberately so: it is the only thing here that the web
/// app could not do at all.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import 'photos_home.dart';
import 'backup_screen.dart';
import 'records_screen.dart';
import 'documents_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.brand});
  final Brand brand;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const PhotosHome(),
      const DocumentsScreen(),
      const RecordsScreen(),
      _Profile(brand: widget.brand),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      // A named route rather than a push from the gallery, so the backup screen
      // is reachable from anywhere later without threading a callback through.
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupScreen()),
              ),
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Back up'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: 'Photos'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: 'Documents'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Records'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'You'),
        ],
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.brand});
  final Brand brand;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text((user?['name'] ?? 'Signed in') as String),
            subtitle: Text((user?['email'] ?? '') as String),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Your SafeNest'),
            subtitle: Text(session.baseUrl ?? '—'),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Sign out',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => session.signOut(),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '${brand.name} keeps your records on your own computer. '
              'This app holds nothing of its own beyond your sign-in.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
