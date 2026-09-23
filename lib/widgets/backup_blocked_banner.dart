/// "Automatic backup is switched on but the phone will not let it run."
///
/// WHY THIS IS A BANNER AND NOT A LINE IN SETTINGS
/// The whole failure is invisible. Automatic backup that never runs looks
/// exactly like automatic backup with nothing to do: no error, no progress, no
/// notification, and the photo count simply stops moving. Somebody who has
/// switched it on and gone away has no reason to open a settings card, so a
/// sentence in there is only found by the person who already suspects.
///
/// This was reported twice — "stuck at 39", then "not working when the screen
/// is off" — and both times the app knew perfectly well what was wrong and
/// said nothing. So it says it where the photos are.
///
/// It is deliberately NOT a push notification. The condition can persist for
/// days, notifications repeat, and being nagged about Low Power Mode by a
/// backup app is how people turn the backup app off.
library;

import 'dart:io' show Platform;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';

import '../background.dart';

class BackupBlockedBanner extends StatefulWidget {
  const BackupBlockedBanner({super.key});

  @override
  State<BackupBlockedBanner> createState() => _BackupBlockedBannerState();
}

class _BackupBlockedBannerState extends State<BackupBlockedBanner>
    with WidgetsBindingObserver {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-checked on the way back in, so turning Low Power Mode off and
    // returning makes the banner go away by itself. A warning that outlives
    // the problem teaches people to ignore warnings.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    var show = false;
    try {
      // Only worth saying when automatic backup is actually expected to run.
      // Somebody who has never switched it on is not being let down by the
      // phone, and does not need telling about a setting they are not using.
      if (await BackgroundBackup.isEnabled()) {
        show = await Battery().isInBatterySaveMode;
      }
    } catch (_) {
      // A phone that will not answer is not a reason to assert a problem.
      show = false;
    }
    if (mounted && show != _show) setState(() => _show = show);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final ios = Platform.isIOS;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.battery_saver_outlined,
              color: theme.colorScheme.onErrorContainer, size: 22),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ios ? 'Backup is paused by Low Power Mode'
                      : 'Backup is paused by battery saver',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ios
                      ? 'iOS does not run background tasks in Low Power Mode. '
                          'Turn it off in Settings › Battery, then put the phone '
                          'on charge — your photos will carry on by themselves.'
                      : 'Battery saver stops background work. Turn it off, or '
                          'allow SafeNest to run in the background, and your '
                          'photos will carry on by themselves.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
