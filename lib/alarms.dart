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

  /// Anything ELSE in the app that owns alarms, re-scheduled by [syncFrom].
  ///
  /// THIS EXISTS BECAUSE [syncFrom] CANCELS EVERYTHING. That is right for the
  /// reminders module — the server is the authority there — but it means
  /// whoever cancels has to know about every other alarm in the app, and Life
  /// Memory's warranty warnings are set from the phone's own database and have
  /// no server rows to be re-scheduled from. Without this hook, opening the
  /// Reminders screen silently cancelled every warranty warning, and the
  /// symptom would have been a notification that never arrived two years later
  /// with nothing at all to point at.
  ///
  /// Set once, in `main.dart`. A hook rather than a call at each site, because
  /// the call sites are where this gets forgotten.
  Future<void> Function()? alsoSchedule;

  /// The channel an alarm-style reminder uses.
  ///
  /// Separate from anything quieter on purpose: a channel's importance and
  /// sound are fixed on Android when it is FIRST created, and can never be
  /// raised afterwards by the app — only by the person, in system settings. A
  /// reminder created on a default channel is therefore permanently a quiet
  /// notification, whatever the code later asks for.
  static const _channelId = 'safenest.reminders.alarm';

  // ONE RING BY DEFAULT, and this was five.
  //
  // The idea was that an alarm keeps going where a notification chimes once, so
  // each reminder became a burst: the first at the due time, then repeats every
  // _burstGap. On the owner's phone that is not what it looked like. Android
  // does not replace a notification with the next ring, it STACKS them, so one
  // reminder left five separate entries in the shade — and the server sends its
  // own push for the same reminder, which made six. Reported, correctly, as
  // "reminders are coming multiple times".
  //
  // So the burst is opt-in now and off unless somebody asks for it. The
  // capability is kept because the case for it was real — a single chime is
  // easy to miss — but it is the kind of thing a person decides for themselves,
  // and the default has to be the one that does not look broken.
  //
  // The extra rings live in an id space far above any server reminder id so
  // they never collide with a real one.
  static const _burstGap = Duration(seconds: 30);
  static const _burstMax = 5;

  /// How many times one reminder rings. 1 is the default; up to [_burstMax].
  /// Set from Settings; see `notification_settings.dart`.
  int burstCount = 1;

  /// Whether this phone may set EXACT alarms, which Android 13+ gates behind
  /// its own permission.
  ///
  /// NOT A COSMETIC DIFFERENCE. Asking for an exact alarm without the
  /// permission does not degrade — it THROWS, and every ring is lost. That is
  /// what was happening on a test device: fourteen `exact_alarms_not_permitted`
  /// in the log and not one local reminder, with the only clue a debugPrint
  /// nobody reads. An inexact alarm arrives within a maintenance window rather
  /// than on the minute, which for a bill reminder is the difference between
  /// late and never.
  static const _extraBase = 1 << 28; // 268,435,456 — above any reminder row id
  bool? _canBeExact;

  int _extraId(int id, int k) => _extraBase + id * _burstMax + k;

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
  /// Whether an exact alarm can be set on this phone.
  ///
  /// Cached for the run: it is a platform call per reminder otherwise, and a
  /// sync of forty reminders would make forty of them. Cleared by
  /// [requestPermission], which is the only thing that can change the answer
  /// from inside the app.
  Future<bool> canScheduleExact() async {
    if (_canBeExact != null) return _canBeExact!;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      // iOS has no such gate, and neither does a test harness.
      _canBeExact = true;
      return true;
    }
    try {
      _canBeExact = await android.canScheduleExactNotifications() ?? false;
    } catch (_) {
      // An older Android, where the permission does not exist and everything is
      // exact. Treating a failed check as "no" would quietly make every
      // reminder inexact on the phones that never needed the check.
      _canBeExact = true;
    }
    return _canBeExact!;
  }

  /// Ask for what notifications need.
  ///
  /// [openSettingsForExactAlarms] is false by default, and that default is the
  /// whole point. The notification permission is a DIALOG — it appears over the
  /// app, it is answered in place, and asking at a sensible moment is good
  /// manners. The exact-alarm permission is not a dialog at all: on Android 13+
  /// `requestExactAlarmsPermission` launches a full system Settings ACTIVITY,
  /// which takes the person out of SafeNest entirely and drops them on a page
  /// about alarms they did not ask to see.
  ///
  /// It was being called from the Reminders list as it loaded, so simply having
  /// the Reminders tab in the nav bar threw people into Android Settings about
  /// forty-five seconds after launch, with nothing on screen to explain why. It
  /// is only asked for now where somebody has asked for it: the "Tap to allow"
  /// row in Settings, next to the switch that needs it.
  Future<bool> requestPermission(
      {bool openSettingsForExactAlarms = false}) async {
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
      _canBeExact = null; // the answer may have just changed
      // Exact alarms are their own permission on Android 13+. Without it a
      // reminder set for 18:30 is delivered "around" 18:30 — late rather than
      // never, since schedule() falls back to an inexact alarm — so it is worth
      // asking for, but only when somebody has asked to be asked.
      if (openSettingsForExactAlarms) {
        await android.requestExactAlarmsPermission();
      }
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
    final exact = await canScheduleExact();
    final rings = burstCount.clamp(1, _burstMax);
    for (var k = 0; k < rings; k++) {
      final at = when.add(_burstGap * k);
      try {
        await _plugin.zonedSchedule(
          k == 0 ? id : _extraId(id, k),
          title,
          body,
          tz.TZDateTime.from(at, tz.local),
          _alarmStyle(id),
          // EXACT ONLY IF ALLOWED. Asking for exact without the permission
          // throws and the reminder is simply never set — see canScheduleExact.
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
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
    // Every id the burst could ever have used, not just the ones this run set.
    // Turning the burst down from five to one must still clear the four rings a
    // previous run left in the queue, or they go off tomorrow with nothing left
    // that knows about them.
    for (var k = 1; k < _burstMax; k++) {
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
        body: t.isEmpty ? 'Due today' : 'Due at ${fmtClock(t)}',
        when: when,
      );
      set++;
    }
    // Everything else that owns an alarm, put back in the same breath that
    // cancelled it. Failures are swallowed deliberately: the reminders the
    // caller asked about are already set, and losing those too because a
    // warranty warning could not be scheduled would be the worse outcome.
    final also = alsoSchedule;
    if (also != null) {
      try {
        await also();
      } catch (e) {
        debugPrint('[alarms] could not re-schedule the rest: $e');
      }
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
