/// Reminders that ring on this phone, like an alarm.
///
/// NOT PUSH, and that is the point. Push would mean handing the titles of
/// somebody's reminders — "HDFC card due", "Insurance lapses today" — to
/// Google's servers so they could be delivered back to a phone six feet from
/// the computer that already knows them. This app's whole argument is that
/// records stay on the owner's machine, and a reminder is a record.
///
/// So: the phone fetches reminders it is already entitled to see, and schedules
/// them locally. They fire with the phone in flight mode. Nothing about them
/// leaves the device, and there is no third party in the path at all.
///
/// AN ALARM, NOT A CHIME. A reminder for a bill due today is worth more than
/// the single notification sound that a bank advert also gets, and it is lost
/// behind exactly that. These use a full-screen, looping alert on Android and a
/// time-sensitive interruption on iOS, and they keep going until dismissed.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'dates.dart';

class Alarms {
  Alarms._();
  static final Alarms instance = Alarms._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// The channel an alarm-style reminder uses.
  ///
  /// Separate from anything quieter on purpose: a channel's importance and
  /// sound are fixed on Android when it is FIRST created, and can never be
  /// raised afterwards by the app — only by the person, in system settings. A
  /// reminder created on a default channel is therefore permanently a quiet
  /// notification, whatever the code later asks for.
  static const _channelId = 'safenest.reminders.alarm';

  // An alarm keeps going; a notification chimes once. So each reminder is not a
  // single notification but a short BURST — the first at the due time, then
  // repeats every _burstGap until it is dismissed or the app is next opened
  // (syncFrom cancels everything and reschedules, clearing whatever has not yet
  // fired). Combined with the ~24s custom alarm tone, that is close to two minutes
  // of intermittent alarm rather than one lost chime. The extra rings live in an
  // id space far above any server reminder id so they never collide with a real
  // one.
  static const _burstCount = 5;
  static const _burstGap = Duration(seconds: 30);
  static const _extraBase = 1 << 28; // 268,435,456 — above any reminder row id
  int _extraId(int id, int k) => _extraBase + id * _burstCount + k;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    // IST, matching the server's single clock (ist.py). A phone in another zone
    // would otherwise fire a 6:30pm reminder at 6:30pm ITS time, which is not
    // the hour anybody chose.
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // Asked for at the moment somebody turns reminders on, not on first
        // launch. A permission prompt before anyone has seen what the app does
        // is the one most often refused.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    _ready = true;
  }

  /// Ask for permission, at the moment it makes sense to.
  Future<bool> requestPermission() async {
    await init();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
              alert: true, badge: true, sound: true, critical: false) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;
      // Exact alarms are their own permission on Android 13+. Without it a
      // reminder set for 18:30 is delivered "around" 18:30, which for a
      // medication reminder is not the same thing.
      await android.requestExactAlarmsPermission();
      return granted;
    }
    return false;
  }

  NotificationDetails _alarmStyle(int id) => NotificationDetails(
        android: const AndroidNotificationDetails(
          _channelId,
          'Reminders',
          channelDescription: 'Reminders you set, at the time you set them',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          // Keeps sounding and stays on screen until it is acted on. Without
          // ongoing:true it disappears by itself, which for a reminder set for
          // a reason is the same as never arriving.
          ongoing: true,
          autoCancel: false,
          playSound: true,
          // The bundled alarm tone (res/raw/alarm.wav) rather than the single
          // default chime a bank advert also gets — the whole point of "ring like
          // an alarm". Named without extension, the way Android raw resources are.
          sound: RawResourceAndroidNotificationSound('alarm'),
          enableVibration: true,
          fullScreenIntent: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // The bundled ~24s alarm tone (ios/Runner/alarm.wav), not the default
          // ~1s ding. iOS plays a custom notification sound for its own length up
          // to 30s, so this rings for real.
          sound: 'alarm.wav',
          // Time-sensitive breaks through a Focus mode. The louder-still level,
          // .critical, ALSO rings through the silent switch and Do Not Disturb —
          // but Apple gates it behind the Critical Alerts entitlement, which has
          // to be requested and approved (see requestPermission and the release
          // notes). Until that lands, timeSensitive is the strongest level a
          // normal build is allowed.
          interruptionLevel: InterruptionLevel.timeSensitive,
          // Group a reminder's whole burst into one stack rather than five loose
          // notifications.
          threadIdentifier: 'reminder-$id',
        ),
      );

  /// Schedule one reminder. Cancels any previous alarm with the same id first,
  /// so editing the time moves the alarm rather than leaving two.
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await init();
    // Clear this reminder's whole burst first, so editing the time moves every
    // ring rather than leaving stragglers from the old time behind.
    await cancel(id);
    // A time already past is not scheduled at all. flutter_local_notifications
    // would otherwise fire it immediately, so opening the app would set off
    // every reminder from the last month at once. The extras are all later than
    // `when`, so this one guard covers the whole burst.
    if (!when.isAfter(DateTime.now())) return;
    for (var k = 0; k < _burstCount; k++) {
      final at = when.add(_burstGap * k);
      try {
        await _plugin.zonedSchedule(
          k == 0 ? id : _extraId(id, k),
          title,
          body,
          tz.TZDateTime.from(at, tz.local),
          _alarmStyle(id),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          // absoluteTime: 18:30 means 18:30 in the app's clock (IST), not
          // whatever wall time the phone happens to be showing in another
          // country. The alternative interprets it against the device's zone and
          // a reminder set at home fires at the wrong hour abroad.
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        // A phone that refuses exact alarms must not take the app down with it.
        debugPrint('[alarms] could not schedule $id ring $k: $e');
      }
    }
  }

  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
    // ...and every extra ring of its burst, or a cancelled reminder would keep
    // going off from the repeats already in the queue.
    for (var k = 1; k < _burstCount; k++) {
      await _plugin.cancel(_extraId(id, k));
    }
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// Re-schedule from the reminders the server holds.
  ///
  /// Everything is cancelled first, because the authority is the server: a
  /// reminder deleted or re-timed on the computer must not keep ringing here
  /// from a schedule set days ago. That is the failure people would report as
  /// "it went off for something I already did".
  Future<int> syncFrom(List<Map<String, dynamic>> reminders) async {
    await init();
    await cancelAll();
    var set = 0;
    for (final r in reminders) {
      if (r['is_done'] == 1 || r['is_done'] == true) continue;
      final when = _whenOf(r);
      if (when == null) continue;
      final id = r['id'];
      if (id is! int) continue;
      // The server's reminder rows carry no free-text note — checked against a
      // live /api/reminders response rather than assumed — so the body says
      // when it was due, which is the useful thing at the moment it rings.
      final t = '${r['due_time'] ?? ''}'.trim();
      await schedule(
        id: id,
        title: '${r['title'] ?? 'Reminder'}',
        body: t.isEmpty ? 'Due today' : 'Due at $t',
        when: when,
      );
      set++;
    }
    return set;
  }

  /// A reminder's date and its optional hour.
  ///
  /// due_time is a VARCHAR(5) "HH:MM" on the server — see the project guide. A
  /// reminder with no time is treated as 9am rather than midnight: an alarm at
  /// 00:00 wakes somebody up for a bill.
  DateTime? _whenOf(Map<String, dynamic> r) {
    // parseDate, not raw DateTime.tryParse: the rest of the app reads dates that
    // way and it handles dd-mm-yyyy as well as ISO. A raw tryParse silently
    // returns null on anything but ISO, and a null here is a reminder that never
    // gets an alarm at all — a quiet way for every reminder to stop ringing if
    // the server's date wording ever changes.
    final date = parseDate('${r['due_date'] ?? ''}');
    if (date == null) return null;
    final t = '${r['due_time'] ?? ''}'.trim();
    var hour = 9, minute = 0;
    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(t)) {
      final bits = t.split(':');
      hour = int.parse(bits[0]);
      minute = int.parse(bits[1]);
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}
