/// Profile — the settings the web app has, minus the ones that belong to a
/// computer rather than to a person.
///
/// WHAT IS HERE, and it mirrors screens/Profile.tsx group for group:
///   Account        edit your name, change your password
///   Appearance     light, dark or follow the phone
///   Photos         back up this phone
///   Customization  Manage lists — the categories and banks the forms offer
///   Daily summary  whether it comes, at what hour, and what goes in it
///   My data        notifications, activity log
///   Your licence   read-only, from the copy you signed in to
///   App            version, and what this app is keeping on the phone
///
/// The middle two were missing for a long time and should not have been.
/// "Manage lists" is not a settings nicety — the categories and banks it edits
/// are what every record form offers, so without it the phone could pick from
/// those lists and never change them. The daily-summary settings are wanted on a
/// PHONE most of all, because the phone is the thing the message arrives on, and
/// they were reachable only from the laptop.
///
/// WHAT IS NOT, and deliberately: user management, licence ISSUING, app name and
/// icon, web address, household, services, storage and "this computer". Those
/// configure the machine, are done once, and are done at the machine. Building
/// them twice is how the two halves drift, and the more consequential half is
/// always the one nobody is looking at.
///
/// The test for whether something belongs here is not "does the web app have
/// it". It is "would somebody reasonably do this from a phone". Managing lists
/// and choosing when to be interrupted pass it; issuing a licence to a customer
/// does not.
library;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../customize.dart';
import '../dates.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/notification_settings.dart';
import 'masters_screen.dart';
import '../widgets/brand_button.dart';
import '../widgets/avatar.dart';
import '../widgets/edit_profile_sheet.dart';
import 'activity_screen.dart';
import 'storage_screen.dart';
import 'backup_screen.dart';
import 'notifications_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.brand,
    this.themeMode = ThemeMode.system,
    this.onThemeChanged,
    this.onCustomiseNav,
  });

  final Brand brand;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeChanged;

  /// Opens the "arrange the bottom bar" sheet. Provided by the home shell, which
  /// owns the tab list; null when Profile is shown outside it.
  final VoidCallback? onCustomiseNav;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _licence;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadLicence();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      // Build number as well as version: two builds can share a version number
      // while only one of them has the fix, and the build is what identifies
      // which one somebody is actually running.
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }
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
      // A near-opaque surface over the nature backdrop: Profile is dense with
      // text and switches, and the scene showing through them read as clutter.
      // Kept just shy of solid so a hint of the backdrop still frames the edges.
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.94),
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          // A hero card: the person's photo, name and email on a brand gradient,
          // the whole thing tappable to edit. The web app's avatar-opens-edit,
          // made the anchor of the screen it belongs to.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _editProfile(context),
                borderRadius: BorderRadius.circular(22),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kBrand, Color(0xFF6366F1)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                          color: kBrand.withValues(alpha: 0.32),
                          blurRadius: 18,
                          offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                        child: Avatar(size: 62, onTap: () => _editProfile(context)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${user?['name'] ?? 'Signed in'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('${user?['email'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 13)),
                            if (user?['role'] != null) ...[
                              const SizedBox(height: 9),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.verified_user,
                                      size: 12, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text('${user!['role']}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ]),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_outlined,
                          color: Colors.white70, size: 20),
                    ]),
                  ),
                ),
              ),
            ),
          ),

          SettingsGroup(title: 'Account', children: [
            SettingsRow(
              icon: Icons.edit_outlined,
              tint: kBrand,
              label: 'Edit profile',
              value: 'Name and photo',
              onTap: () => _editProfile(context),
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
            title: 'Personalise',
            footer: 'Make the app yours. These are saved on this phone and take '
                'effect straight away.',
            children: [
              // Bottom icons: colourful gradient chips, or plain icons.
              SettingsRow(
                icon: Icons.dashboard_customize_outlined,
                tint: kModuleColours['investments']!,
                label: 'Colourful bottom icons',
                trailing: Customize.colourfulNav
                    ? const Icon(Icons.check, size: 18, color: kBrand)
                    : null,
                onTap: () async {
                  await Customize.setNavStyle(Customize.navStyleColour);
                  if (mounted) setState(() {});
                },
              ),
              SettingsRow(
                icon: Icons.dashboard_outlined,
                tint: kModuleColours['vault']!,
                label: 'Plain bottom icons',
                trailing: !Customize.colourfulNav
                    ? const Icon(Icons.check, size: 18, color: kBrand)
                    : null,
                onTap: () async {
                  await Customize.setNavStyle(Customize.navStylePlain);
                  if (mounted) setState(() {});
                },
              ),
              // Background: the animated nature scene, or a plain screen.
              SettingsRow(
                icon: Icons.landscape_outlined,
                tint: kModuleColours['todos']!,
                label: 'Nature background',
                trailing: Customize.natureBackground
                    ? const Icon(Icons.check, size: 18, color: kBrand)
                    : null,
                onTap: () async {
                  await Customize.setBackground(Customize.backgroundNature);
                  if (mounted) setState(() {});
                },
              ),
              SettingsRow(
                icon: Icons.crop_square,
                tint: kModuleColours['documents']!,
                label: 'Plain background',
                trailing: !Customize.natureBackground
                    ? const Icon(Icons.check, size: 18, color: kBrand)
                    : null,
                onTap: () async {
                  await Customize.setBackground(Customize.backgroundPlain);
                  if (mounted) setState(() {});
                },
              ),
              // Rearrange the bottom bar — same sheet as a long-press on the bar.
              if (widget.onCustomiseNav != null)
                SettingsRow(
                  icon: Icons.reorder,
                  tint: kModuleColours['reminders']!,
                  label: 'Rearrange the bottom bar',
                  onTap: widget.onCustomiseNav,
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

          // The web app's "Customization" group. It has been there since the
          // beginning and the phone had no way in at all — the lists were
          // seeded, used by the forms, and unreachable.
          SettingsGroup(
            title: 'Customization',
            footer: 'These are the categories and banks the forms offer you.',
            children: [
              SettingsRow(
                icon: Icons.category_outlined,
                tint: kModuleColours['expenses']!,
                label: 'Manage lists',
                value: 'Categories, banks',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MastersScreen())),
              ),
            ],
          ),

          // The daily-summary settings the web app has had all along. Most
          // wanted on a phone of all places — it is the device the message
          // actually arrives on — and it was only changeable at the laptop.
          const NotificationSettingsSection(),

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
            // Reading how much space photos take, and which drive they are on,
            // configures nothing — it is the question you ask from a phone,
            // usually just before backing up a few hundred more. Changing the
            // location stays on the computer.
            SettingsRow(
              icon: Icons.pie_chart_outline,
              tint: kModuleColours['investments']!,
              label: 'Storage',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StorageScreen(appName: widget.brand.name))),
            ),
          ]),

          // ONLY on a licensed copy. It used to appear whenever the server
          // answered with a state at all — and the publisher's own
          // installation answers `{licensed: false, state: "ok"}`. So this
          // machine showed a "Your licence" box reading "Licensed copy — ok",
          // with no date and no number, which is not a licence and not
          // information.
          if (_licence != null && _licence!['licensed'] == true)
            SettingsGroup(
              title: 'Your licence',
              // Read-only on the phone, and it says so: the key lives on the
              // customer's computer and can only be changed there (Profile →
              // Licence → Update licence key on the desktop). A phone that could
              // change the licence would be a second place to get it wrong.
              footer: 'Issued for the copy on your computer. It covers this app '
                  'too — there is no separate licence for the phone. To change '
                  'the licence key, use ${widget.brand.name} on your computer; '
                  'it cannot be changed from the phone.',
              children: [
                SettingsRow(
                  icon: Icons.card_membership_outlined,
                  tint: _licenceTint(),
                  label: '${_licence!['name'] ?? 'Licensed copy'}',
                  value: _licenceState(),
                ),
                if (_licence!['email'] != null &&
                    '${_licence!['email']}'.isNotEmpty)
                  SettingsRow(
                    icon: Icons.person_outline,
                    tint: theme.colorScheme.outline,
                    label: 'Registered to',
                    value: '${_licence!['email']}',
                  ),
                SettingsRow(
                  icon: Icons.event_outlined,
                  tint: theme.colorScheme.outline,
                  label: 'Valid until',
                  // dd-mm-yyyy, not the raw ISO column this printed before.
                  // And a perpetual licence SAYS so: the row used to be hidden
                  // when there was no expiry date, so the customer who paid
                  // outright was the one told nothing at all.
                  value: _licence!['expires_on'] == null
                      ? 'Never expires'
                      : fmtDate(parseDate('${_licence!['expires_on']}')),
                ),
                // Days left only makes sense for a dated licence; a perpetual one
                // has none, and the server sends no meaningful count.
                if (_licence!['perpetual'] != true &&
                    _licence!['days_left'] != null &&
                    (_licence!['days_left'] as num) >= 0)
                  SettingsRow(
                    icon: Icons.hourglass_bottom_outlined,
                    tint: _licenceTint(),
                    label: 'Days remaining',
                    value: '${_licence!['days_left']}',
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
                'and a list of which photos it has already sent. '
                'Tap the address to switch between your home network and your '
                'web address — at home the phone reaches the computer directly, '
                'which is faster and never leaves the house.',
            children: [
              SettingsRow(
                icon: Icons.dns_outlined,
                tint: kModuleColours['insurance']!,
                label: 'Address',
                value: session.baseUrl ?? '—',
                onTap: () => _changeAddress(context, session.baseUrl ?? ''),
              ),
              SettingsRow(
                icon: Icons.info_outline,
                tint: const Color(0xFF9A9DB5),
                label: 'Version',
                value: _version.isEmpty ? '…' : _version,
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

  /// The state in words, not the server's own token.
  ///
  /// It printed whatever the API said — "ok", "GRACE", "EXPIRING" — which are
  /// names for the code's benefit. "GRACE" in particular tells the one person
  /// who needs to act nothing about what is happening to them, and it is the
  /// state where writing has already stopped working.
  String _licenceState() {
    final days = _licence?['days_left'];
    switch ('${_licence?['state'] ?? ''}'.toUpperCase()) {
      case 'OK':
        return days is int && days > 0 ? '$days days left' : 'Active';
      case 'EXPIRING':
        return days is int ? 'Expires in $days days' : 'Expiring soon';
      case 'GRACE':
        return 'Expired — renew to save changes';
      case 'EXPIRED':
        return 'Expired';
      case 'REVOKED':
        return 'Withdrawn';
      case 'INVALID':
        return 'Not valid';
      case 'MISSING':
        return 'No licence found';
      default:
        return 'Active';
    }
  }

  Future<void> _changeAddress(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
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
          Text('Address of your SafeNest',
              style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'On your own Wi-Fi use the computer’s address, like '
            '192.168.1.5:8080 — the phone then talks to it directly and nothing '
            'leaves the house. Away from home, use your web address.',
            textAlign: TextAlign.center,
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: 'safenest.example.com',
            ),
          ),
          const SizedBox(height: 18),
          BrandButton(label: 'Use this address',
              onPressed: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (go != true) return;
    try {
      final kept = await session.changeAddress(controller.text);
      messenger.showSnackBar(SnackBar(
        content: Text(kept
            ? 'Now using that address'
            : 'That is a different SafeNest — sign in again'),
      ));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The full sheet: photo AND name.
  ///
  /// This used to be a single text field. The web app's row has always said
  /// "Change your name or photo", POST/DELETE /api/auth/avatar have always
  /// existed, and the Avatar widget here already renders avatar_url — so the
  /// phone could show a profile picture and had no way to set one.
  Future<void> _editProfile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const EditProfileSheet(),
    );
    if (saved == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Saved')));
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
        mainAxisSize: MainAxisSize.min,
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
