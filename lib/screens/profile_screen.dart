/// Profile — the settings the web app has, minus the ones that belong to a
/// computer rather than to a person.
///
/// WHAT IS HERE, and it mirrors screens/Profile.tsx group for group:
///   Account       edit your name, change your password
///   Appearance    light, dark or follow the phone
///   Photos        find duplicates, find similar
///   My data       notifications, activity log
///   Your licence  read-only, from the copy you signed in to
///   App           version, and what this app is keeping on the phone
///
/// WHAT IS NOT, and deliberately: user management, licence ISSUING, app name and
/// icon, web address, household, services, storage and "this computer". Those
/// configure the machine, are done once, and are done at the machine. Building
/// them twice is how the two halves drift, and the more consequential half is
/// always the one nobody is looking at.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/brand_logo.dart';
import 'activity_screen.dart';
import 'backup_screen.dart';
import 'notifications_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.brand,
    this.themeMode = ThemeMode.system,
    this.onThemeChanged,
  });

  final Brand brand;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _licence;

  @override
  void initState() {
    super.initState();
    _loadLicence();
  }

  Future<void> _loadLicence() async {
    try {
      final d = await context.read<Session>().api.get('/api/licence/status');
      if (d is Map && mounted) {
        setState(() => _licence = Map<String, dynamic>.from(d));
      }
    } catch (_) {
      // The publisher's own installation is not licensed, so this 404s there.
      // Absent is a perfectly good answer; the group simply does not appear.
    }
  }

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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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

          SettingsGroup(title: 'Account', children: [
            SettingsRow(
              icon: Icons.edit_outlined,
              tint: kBrand,
              label: 'Edit profile',
              onTap: () => _editName(context, '${user?['name'] ?? ''}'),
            ),
            SettingsRow(
              icon: Icons.lock_outline,
              tint: kModuleColours['vault']!,
              label: 'Change password',
              onTap: () => _changePassword(context),
            ),
          ]),

          SettingsGroup(
            title: 'Appearance',
            footer: 'Follow the phone and it changes with your system setting at '
                'sunset, the same as everything else.',
            children: [
              for (final m in ThemeMode.values)
                SettingsRow(
                  icon: m == ThemeMode.light
                      ? Icons.light_mode_outlined
                      : m == ThemeMode.dark
                          ? Icons.dark_mode_outlined
                          : Icons.brightness_auto_outlined,
                  tint: kModuleColours['reminders']!,
                  label: m == ThemeMode.system
                      ? 'Follow the phone'
                      : m == ThemeMode.light
                          ? 'Light'
                          : 'Dark',
                  trailing: widget.themeMode == m
                      ? const Icon(Icons.check, size: 18, color: kBrand)
                      : null,
                  onTap: () => widget.onThemeChanged?.call(m),
                ),
            ],
          ),

          SettingsGroup(
            title: 'Photos',
            footer: 'Backing up copies everything on this phone to your own '
                'computer. Photos already there are skipped.',
            children: [
              SettingsRow(
                icon: Icons.backup_outlined,
                tint: kModuleColours['gallery']!,
                label: 'Back up this phone',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BackupScreen())),
              ),
            ],
          ),

          SettingsGroup(title: 'My data', children: [
            SettingsRow(
              icon: Icons.notifications_outlined,
              tint: kModuleColours['reminders']!,
              label: 'Notifications',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NotificationsScreen())),
            ),
            SettingsRow(
              icon: Icons.receipt_long_outlined,
              tint: kModuleColours['insurance']!,
              label: 'Activity log',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const ActivityScreen())),
            ),
          ]),

          if (_licence != null && _licence!['state'] != null)
            SettingsGroup(
              title: 'Your licence',
              footer: 'Issued for the copy on your computer. It covers this app '
                  'too — there is no separate licence for the phone.',
              children: [
                SettingsRow(
                  icon: Icons.card_membership_outlined,
                  tint: _licenceTint(),
                  label: '${_licence!['name'] ?? 'Licensed copy'}',
                  value: '${_licence!['state'] ?? ''}',
                ),
                if (_licence!['expires_on'] != null)
                  SettingsRow(
                    icon: Icons.event_outlined,
                    tint: theme.colorScheme.outline,
                    label: 'Valid until',
                    value: '${_licence!['expires_on']}',
                  ),
                if (_licence!['key_id'] != null)
                  SettingsRow(
                    icon: Icons.tag,
                    tint: theme.colorScheme.outline,
                    label: 'Licence number',
                    value: '${_licence!['key_id']}',
                  ),
              ],
            ),

          SettingsGroup(
            title: 'This app',
            footer: 'Everything you see is read from ${widget.brand.name} on your '
                'computer and saved back to it. This app keeps only your sign-in '
                'and a list of which photos it has already sent.',
            children: [
              SettingsRow(
                icon: Icons.dns_outlined,
                tint: kModuleColours['insurance']!,
                label: 'Your SafeNest',
                value: session.baseUrl ?? '—',
              ),
              const SettingsRow(
                icon: Icons.info_outline,
                tint: Color(0xFF9A9DB5),
                label: 'Version',
                value: '0.4.0',
              ),
            ],
          ),

          SettingsGroup(title: '', children: [
            SettingsRow(
              icon: Icons.logout,
              tint: kDanger,
              label: 'Sign out',
              danger: true,
              onTap: () => session.signOut(),
            ),
          ]),
        ],
      ),
    );
  }

  Color _licenceTint() {
    switch ('${_licence?['state'] ?? ''}'.toUpperCase()) {
      case 'OK':
        return kOk;
      case 'EXPIRING':
      case 'GRACE':
        return kWarn;
      default:
        return kDanger;
    }
  }

  Future<void> _editName(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final session = context.read<Session>();
    final messenger = ScaffoldMessenger.of(context);

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 0, 22, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Edit profile', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Your name'),
          ),
          const SizedBox(height: 18),
          BrandButton(label: 'Save', onPressed: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (save != true) return;
    try {
      await session.api.put('/api/auth/profile', {'name': controller.text.trim()});
      await session.refreshUser();
      messenger.showSnackBar(const SnackBar(content: Text('Saved')));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final cur = TextEditingController();
    final next = TextEditingController();
    final session = context.read<Session>();
    final messenger = ScaffoldMessenger.of(context);

    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 0, 22, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Change password', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Changing it signs out every other device, including the computer. '
            'That is deliberate — it is what makes a change worth making.',
            textAlign: TextAlign.center,
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: cur,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 18),
          BrandButton(label: 'Change it', onPressed: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (go != true) return;
    try {
      await session.api.post('/api/auth/change-password', {
        'current_password': cur.text,
        'new_password': next.text,
      });
      messenger.showSnackBar(const SnackBar(
          content: Text('Password changed — sign in again with the new one')));
      // token_version was just bumped on the server, so this session is dead.
      // Signing out here is honest; leaving it would mean every later call
      // failing with 401 and no explanation.
      await session.signOut();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The web app's SettingsGroup — a titled card of rows with an explaining
/// footer. The footer is what makes a long settings screen readable, so it is
/// part of the component rather than an afterthought.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });
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
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
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

/// The web app's SettingsRow — tinted glyph, label, optional value, 52px tall.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final Color tint;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
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
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          if (onTap != null && trailing == null && !danger) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
          ],
        ]),
      ),
    );
  }
}
