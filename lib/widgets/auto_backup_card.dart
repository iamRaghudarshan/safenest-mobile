/// The controls for automatic backup.
///
/// The wording here is doing real work and should not be tidied into something
/// breezier. Every phone backup people have used claims photos "back up
/// automatically", and on iOS that is not a thing a third-party app can
/// promise: BGTaskScheduler decides when, and can decide never. Saying so
/// costs one line and saves the support message that begins "it says automatic
/// but nothing has backed up in a week".
library;

import 'dart:io' show Platform;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background.dart';

class AutoBackupCard extends StatefulWidget {
  const AutoBackupCard({super.key});

  @override
  State<AutoBackupCard> createState() => _AutoBackupCardState();
}

class _AutoBackupCardState extends State<AutoBackupCard> {
  bool _on = false;
  bool _wifiOnly = true;
  bool _chargingOnly = false;
  bool _loaded = false;
  bool _saver = false;
  ({DateTime at, String result})? _last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final last = await BackgroundBackup.lastRun();
    // Best effort. A phone that will not answer this question is not a reason
    // to show nothing; it just means the warning cannot be offered.
    bool saver = false;
    try {
      saver = await Battery().isInBatterySaveMode;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _saver = saver;
      _on = prefs.getBool(kAutoEnabled) ?? false;
      _wifiOnly = prefs.getBool(kAutoWifiOnly) ?? true;
      _chargingOnly = prefs.getBool(kAutoChargingOnly) ?? false;
      _last = last;
      _loaded = true;
    });
  }

  Future<void> _set(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    // Re-apply rather than only saving: the constraints live in the OS
    // schedule, not in this file, so a setting changed here means nothing
    // until the task is registered again with the new ones.
    await BackgroundBackup.apply();
  }

  String get _cadence => Platform.isIOS
      ? 'iOS decides when this runs, usually while the phone is idle or '
          'charging. Each turn is limited, so a big library finishes over '
          'several — it picks up where it stopped. Use the button above when '
          'you want something backed up now.'
      : 'Runs about once an hour in the background, and starts again by itself '
          'after the phone restarts.';

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: _on,
            onChanged: (v) async {
              setState(() => _on = v);
              await BackgroundBackup.setEnabled(v);
            },
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Back up by itself'),
            subtitle: Text(
              _on
                  ? _cadence
                  : 'Off. Photos are backed up only when you press the button '
                      'above.',
              style: theme.textTheme.bodySmall,
            ),
            isThreeLine: _on,
          ),
          if (_on) ...[
            const Divider(height: 1),
            // Two named choices rather than one switch. "Only on Wi-Fi — off"
            // makes you work out what the other state is, and the wrong guess
            // here spends somebody's data allowance on a camera roll. Naming
            // both sides is the difference between choosing and finding out.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Row(children: [
                const Icon(Icons.wifi, size: 20),
                const SizedBox(width: 12),
                Text('Back up over', style: theme.textTheme.titleSmall),
              ]),
            ),
            // RadioGroup, not the per-tile groupValue/onChanged pair: those were
            // deprecated after Flutter 3.32 and this project's analyze is kept
            // clean, so a warning here would be noise the next person has to
            // decide about.
            RadioGroup<bool>(
              groupValue: _wifiOnly,
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _wifiOnly = v);
                await _set(kAutoWifiOnly, v);
              },
              child: Column(children: [
                RadioListTile<bool>(
                  value: true,
                  dense: true,
                  title: const Text('Wi-Fi only'),
                  subtitle: Text('Waits for Wi-Fi. A camera roll is measured in '
                      'gigabytes, so this is the safe choice.',
                      style: theme.textTheme.bodySmall),
                ),
                RadioListTile<bool>(
                  value: false,
                  dense: true,
                  title: const Text('Wi-Fi or mobile data'),
                  subtitle: Text('Backs up wherever there is a connection. Your '
                      'data allowance pays for it.',
                      style: theme.textTheme.bodySmall),
                ),
              ]),
            ),
            SwitchListTile(
              value: _chargingOnly,
              onChanged: (v) async {
                setState(() => _chargingOnly = v);
                await _set(kAutoChargingOnly, v);
              },
              secondary: const Icon(Icons.battery_charging_full),
              title: const Text('Only while charging'),
              subtitle: Text(
                _chargingOnly
                    ? 'Waits until the phone is plugged in.'
                    : 'Runs on battery too, but not when it is low.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            // The reason it is not running, when there is one. iOS suspends
            // BGTaskScheduler outright in Low Power Mode and Android's battery
            // saver restricts background work the same way. The task is not
            // broken in either case — it is not being allowed to start, and
            // until now nothing on screen said so, which left the person to
            // guess. It was reported as "not working when the screen is off".
            if (_saver) ...[
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: Icon(Icons.battery_saver_outlined,
                    color: theme.colorScheme.error, size: 20),
                title: Text(
                  Platform.isIOS ? 'Low Power Mode is on' : 'Battery saver is on',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  Platform.isIOS
                      ? 'iOS does not run background tasks in Low Power Mode, so '
                          'this will not back up on its own until you turn it off.'
                      : 'Battery saver stops background work, so this may not run '
                          'until you turn it off.',
                  style: theme.textTheme.bodySmall,
                ),
                isThreeLine: true,
              ),
            ],
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 20),
              // The honest status line. "Enabled" is not the same as "it has
              // run", and on iOS the gap between the two can be days — so show
              // what actually happened rather than what was switched on.
              title: Text(
                _last == null
                    ? 'Has not run yet'
                    : '${_last!.result} · ${_ago(_last!.at)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
