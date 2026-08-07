/// Profile — grouped settings rows, the way the web app's Profile screen reads.
///
/// It was a bare ListView with three tiles and no shape to it. The web app
/// groups its rows under headings with a footer explaining each group, which is
/// what makes a long settings screen navigable rather than a wall.
///
/// What is deliberately NOT here: the administration half — branding, web
/// address, licences, household, services. Those configure the machine, they are
/// done once, and they are done at the machine. Putting them on a phone would
/// mean maintaining two copies of the most consequential screens in the product
/// so that somebody could re-brand their app on a bus.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../widgets/brand_logo.dart';
import 'backup_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.brand});
  final Brand brand;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 20),
            child: Column(children: [
              const BrandLogo(size: 68),
              const SizedBox(height: 12),
              Text('${user?['name'] ?? 'Signed in'}',
                  style: theme.textTheme.titleMedium),
              Text('${user?['email'] ?? ''}', style: theme.textTheme.bodySmall),
              if (user?['role'] != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: kBrand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${user!['role']}',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: kBrand)),
                ),
              ],
            ]),
          ),

          _Group(
            title: 'Your photos',
            footer: 'Takes everything on this phone and copies it to your own '
                'computer. Photos already there are skipped.',
            children: [
              _Row(
                icon: Icons.backup_outlined,
                tint: kModuleColours['gallery']!,
                label: 'Back up this phone',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BackupScreen())),
              ),
            ],
          ),

          _Group(
            title: 'Reaching this app',
            footer: 'Everything you see is read from this computer and saved '
                'back to it. Nothing is kept on the phone but your sign-in.',
            children: [
              _Row(
                icon: Icons.dns_outlined,
                tint: kModuleColours['insurance']!,
                label: 'Your SafeNest',
                value: session.baseUrl ?? '—',
              ),
            ],
          ),

          _Group(
            title: 'Settings that live on the computer',
            footer: 'App name and icon, web address, licences and household are '
                'set in ${brand.name} on the computer itself. They are done once, '
                'and doing them there keeps one copy of each rather than two.',
            children: const [],
          ),

          _Group(
            title: '',
            children: [
              _Row(
                icon: Icons.logout,
                tint: kDanger,
                label: 'Sign out',
                danger: true,
                onTap: () => session.signOut(),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: Text(
              '${brand.name} keeps your records on your own computer. '
              'This app holds nothing of its own beyond your sign-in.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The web app's SettingsGroup — a titled card of rows with an explaining
/// footer underneath.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.footer});
  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
          if (children.isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(kRadius),
                boxShadow: softShadow(dark),
              ),
              child: Column(children: children),
            ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(footer!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// The web app's SettingsRow — a tinted glyph, a label, an optional value.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.tint,
    required this.label,
    this.value,
    this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final Color tint;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadius),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          Container(
            height: 30,
            width: 30,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 15,
                    color: danger ? kDanger : theme.colorScheme.onSurface)),
          ),
          if (value != null)
            Flexible(
              child: Text(value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall),
            ),
          if (onTap != null && !danger) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
          ],
        ]),
      ),
    );
  }
}
