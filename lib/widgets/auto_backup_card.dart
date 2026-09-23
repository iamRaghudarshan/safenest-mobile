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
  ({DateTime at, String result})? _last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final last = await BackgroundBackup.lastRun();
    if (!mounted) return;
    setState(() {
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
      ? 'iOS decides when this runs — usually while charging, and it can be '
          'many hours. It is a convenience, not a guarantee, so keep using the '
          'button above when you want something backed up now.'
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
            SwitchListTile(
              value: _wifiOnly,
              onChanged: (v) async {
                setState(() => _wifiOnly = v);
                await _set(kAutoWifiOnly, v);
              },
              secondary: const Icon(Icons.wifi),
              title: const Text('Only on Wi-Fi'),
              subtitle: Text(
                _wifiOnly
                    ? 'Waits for Wi-Fi. A camera roll is measured in gigabytes.'
                    : 'Will use mobile data. Watch your allowance.',
                style: theme.textTheme.bodySmall,
              ),
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
