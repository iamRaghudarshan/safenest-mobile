/// The daily summary: whether it comes, when, and what goes in it.
///
/// The web app has had this on Profile since the beginning and the phone had
/// only a link to the inbox — so the one setting a person most wants ON A PHONE
/// (what time to be told, and about what) could only be changed on the laptop.
///
/// Worth being exact about which of the two notification systems this is,
/// because they are easy to confuse now that both exist:
///
///   THIS      one message a day at a chosen hour, listing everything coming
///             due. Configured here, `NotificationPref` on the server.
///   REMINDERS the alarm on one reminder at its own `due_time`. Set on the
///             reminder itself; nothing here governs it.
///
/// So "Daily summary off" does not silence a reminder set for half past six,
/// and the copy says so — otherwise turning this off looks like it should, and
/// the person finds out it did not by being interrupted.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../screens/profile_screen.dart' show SettingsGroup, SettingsRow;

class NotificationSettingsSection extends StatefulWidget {
  const NotificationSettingsSection({super.key, this.initial});

  /// For tests, so the section can be laid out without a server.
  final Map<String, dynamic>? initial;

  @override
  State<NotificationSettingsSection> createState() =>
      _NotificationSettingsSectionState();
}

class _NotificationSettingsSectionState
    extends State<NotificationSettingsSection> {
  Map<String, dynamic>? _s;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _s = widget.initial;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<Session>().api.get('/api/notifications/settings');
      if (d is Map && mounted) setState(() => _s = Map<String, dynamic>.from(d));
    } catch (_) {
      // The section simply does not appear. A settings block that cannot load
      // is worse than no block: every switch in it would lie about its state.
    }
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final d = await context
          .read<Session>()
          .api
          .put('/api/notifications/settings', patch);
      if (d is Map && mounted) setState(() => _s = Map<String, dynamic>.from(d));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time() {
    final h = (_s?['sendHour'] as num?)?.toInt() ?? 9;
    final m = (_s?['sendMinute'] as num?)?.toInt() ?? 0;
    final suffix = h < 12 ? 'am' : 'pm';
    return '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _pickTime() async {
    final h = (_s?['sendHour'] as num?)?.toInt() ?? 9;
    final m = (_s?['sendMinute'] as num?)?.toInt() ?? 0;
    final picked = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: h, minute: m));
    if (picked == null) return;
    await _save({'sendHour': picked.hour, 'sendMinute': picked.minute});
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();

    final on = s['enabled'] == true;
    final available = s['available'] == true;
    final devices = (s['devices'] as num?)?.toInt() ?? 0;

    return SettingsGroup(
      title: 'Daily summary',
      footer: available
          ? 'One message a day listing what is coming due. A reminder you have '
              'given a time of its own still arrives at that time, whether this '
              'is on or off.'
          // push_enabled is false when the owner never configured VAPID keys.
          // Saying so is better than a switch that turns on and does nothing.
          : 'Push is not set up on your computer, so this cannot reach the '
              'phone. Anything due still appears in Notifications.',
      children: [
        SettingsRow(
          icon: Icons.wb_sunny_outlined,
          tint: kBrand,
          label: 'Send me a daily summary',
          trailing: Switch(
            value: on,
            onChanged: _busy ? null : (v) => _save({'enabled': v}),
          ),
        ),
        if (on) ...[
          SettingsRow(
            icon: Icons.schedule,
            tint: kModuleColours['reminders']!,
            label: 'Send it at',
            value: _time(),
            onTap: _busy ? null : _pickTime,
          ),
          SettingsRow(
            icon: Icons.credit_card_outlined,
            tint: kModuleColours['cards']!,
            label: 'Bills and instalments',
            trailing: Switch(
              value: s['includeBills'] == true,
              onChanged: _busy ? null : (v) => _save({'includeBills': v}),
            ),
          ),
          SettingsRow(
            icon: Icons.notifications_outlined,
            tint: kModuleColours['reminders']!,
            label: 'Reminders and tasks',
            trailing: Switch(
              value: s['includeReminders'] == true,
              onChanged: _busy ? null : (v) => _save({'includeReminders': v}),
            ),
          ),
          SettingsRow(
            icon: Icons.event_busy_outlined,
            tint: kModuleColours['insurance']!,
            label: 'Renewals and expiries',
            trailing: Switch(
              value: s['includeExpiry'] == true,
              onChanged: _busy ? null : (v) => _save({'includeExpiry': v}),
            ),
          ),
          if (available && devices == 0)
            SettingsRow(
              icon: Icons.phonelink_erase_outlined,
              tint: kWarn,
              label: 'No device is signed up for push yet',
              value: 'It waits in Notifications',
            ),
        ],
      ],
    );
  }
}
