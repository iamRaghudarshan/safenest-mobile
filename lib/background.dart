/// Backing up without anybody pressing a button.
///
/// WHY THIS IS OPT-IN AND NOT ON BY DEFAULT
/// The comment at the top of backup_screen.dart is the product's position and
/// it still stands: an app that copies somebody's entire camera roll the moment
/// it is installed is exactly what people are right to distrust. So this ships
/// switched OFF. What changes is that somebody who WANTS the behaviour every
/// other phone backup has can now have it, instead of being told to remember to
/// open a screen and tap.
///
/// WHAT EACH PLATFORM ACTUALLY PROMISES, which is not the same thing
/// Android WorkManager is a real scheduler. It survives reboots, it enforces
/// the wifi and charging constraints itself, and a periodic task genuinely
/// recurs. What it will not do is run more often than about every 15 minutes,
/// and Doze will stretch that on an idle phone.
///
/// iOS BGTaskScheduler promises nothing about WHEN. The system decides, from
/// how often the app is opened, whether it is charging, and its own battery
/// budget. It can be hours. It can be never, if the person never opens the app.
/// There is no API that changes this and no entitlement that buys more; an app
/// that claimed "your photos back up automatically" on iOS and left it there
/// would be lying. The settings row says so in as many words.
///
/// This is why the manual button stays exactly where it is on both platforms.
/// Automatic backup is a convenience on top of it, never a replacement for it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'backup.dart';
import 'offline/store.dart';

/// One unique name, so re-registering replaces rather than stacks. A second
/// copy of this task would mean two backups racing over one library.
const _taskName = 'safenest.backup.auto';
const _uniqueName = 'safenest-auto-backup';

/// Settings, in plain preferences: none of these is a credential.
const kAutoEnabled = 'backup.auto';
const kAutoWifiOnly = 'backup.auto.wifiOnly';
const kAutoChargingOnly = 'backup.auto.chargingOnly';
/// When the last automatic run finished, so the settings row can say something
/// truthful instead of implying a schedule iOS never agreed to.
const kAutoLastRun = 'backup.auto.lastRun';
const kAutoLastResult = 'backup.auto.lastResult';

/// Same keys Session uses. Read directly here because a background isolate has
/// no Session, no provider tree and no widgets — it is a fresh Dart isolate
/// with nothing but the plugins.
const _kUrl = 'server.url';
const _kToken = 'server.token';
const _secure = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  // first_unlock and not first_unlock_this_device_only: a background task can
  // run while the phone is locked, and a key the OS refuses to hand over then
  // would make every scheduled run fail with a credential error the person
  // never caused.
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

/// The entry point the OS calls. Must be top level and must carry the pragma,
/// or tree-shaking removes it from a release build and every scheduled run
/// fails with "callback not found" — which looks exactly like the feature
/// simply not working.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      return await _runOnce();
    } catch (e) {
      // Never throw out of here. A thrown task is retried with backoff by
      // WorkManager, and a permanent fault (signed out, server gone) would
      // then be retried forever on somebody's battery.
      debugPrint('[auto-backup] failed: $e');
      return true;
    }
  });
}

Future<bool> _runOnce() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kAutoEnabled) != true) {
    // Switched off between scheduling and running. Cancel rather than just
    // returning, so a phone whose owner turned this off does not keep waking
    // for a task that will do nothing.
    await Workmanager().cancelByUniqueName(_uniqueName);
    return true;
  }

  final url = await _secure.read(key: _kUrl);
  final token = await _secure.read(key: _kToken);
  if (url == null || url.isEmpty || token == null || token.isEmpty) {
    // Signed out. Not an error and not worth retrying.
    await _note(prefs, 'Not signed in');
    return true;
  }

  final store = OfflineStore();
  final service = BackupService(Api(baseUrl: url, token: token), ledger: store);
  try {
    await service.runFullBackup();
    final p = service.progress;
    await _note(prefs,
        p.failed > 0
            ? '${p.done} backed up, ${p.failed} could not be sent'
            : p.done > 0
                ? '${p.done} backed up'
                : 'Nothing new');
  } finally {
    // The service holds a wakelock for the length of a run and releases it in
    // its own finally; disposing here releases the listeners this isolate made.
    service.dispose();
  }
  return true;
}

Future<void> _note(SharedPreferences prefs, String result) async {
  await prefs.setString(kAutoLastResult, result);
  await prefs.setInt(kAutoLastRun, DateTime.now().millisecondsSinceEpoch);
}

class BackgroundBackup {
  /// Called once from main(). Registering the dispatcher is cheap and does not
  /// schedule anything — [apply] does that.
  static Future<void> initialise() async {
    try {
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    } catch (e) {
      // A platform without the plugin (or a test) must not stop the app
      // starting. Automatic backup is a convenience; the manual button is the
      // feature, and it is untouched by this failing.
      debugPrint('[auto-backup] initialise failed: $e');
    }
  }

  /// Bring the OS schedule in line with the saved settings. Safe to call as
  /// often as you like — it replaces rather than stacks.
  static Future<void> apply() async {
    final prefs = await SharedPreferences.getInstance();
    final on = prefs.getBool(kAutoEnabled) ?? false;
    try {
      await Workmanager().cancelByUniqueName(_uniqueName);
      if (!on) return;
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _taskName,
        // The floor Android enforces anyway. Asking for less does not get less.
        frequency: const Duration(hours: 1),
        initialDelay: const Duration(minutes: 15),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(
          // unmetered = wifi. The alternative is uploading somebody's whole
          // camera roll over their mobile data without being asked, which is
          // the complaint every phone backup has had at some point.
          networkType: (prefs.getBool(kAutoWifiOnly) ?? true)
              ? NetworkType.unmetered
              : NetworkType.connected,
          requiresCharging: prefs.getBool(kAutoChargingOnly) ?? false,
          // Not requiresDeviceIdle: on Android that means the screen has been
          // off for a while AND the user is not interacting, which on a phone
          // in daily use can be most of a day. It reads as "never runs".
          requiresBatteryNotLow: true,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 10),
      );
    } catch (e) {
      debugPrint('[auto-backup] schedule failed: $e');
    }
  }

  static Future<void> setEnabled(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAutoEnabled, on);
    await apply();
  }

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(kAutoEnabled) ?? false;

  /// What actually happened last time, for the settings row. Returns null when
  /// it has never run — which on iOS is a real and common state, and is worth
  /// showing rather than implying a schedule that was never promised.
  static Future<({DateTime at, String result})?> lastRun() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(kAutoLastRun);
    if (ms == null) return null;
    return (
      at: DateTime.fromMillisecondsSinceEpoch(ms),
      result: prefs.getString(kAutoLastResult) ?? 'Done',
    );
  }
}
