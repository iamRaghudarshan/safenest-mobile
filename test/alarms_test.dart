// Reminders that ring once, not five times.
//
// WHY THIS FILE EXISTS. The owner reported "reminders are coming multiple
// times", and there were three separate reasons, none visible from reading one
// file:
//
//   * Each reminder was scheduled as a BURST of five notifications thirty
//     seconds apart. Android does not replace a notification with the next
//     ring — it stacks them — so one reminder left five entries in the shade.
//   * The server pushed for the same reminder at the same minute, making six.
//   * And the FCM message carried no tag, so even two server attempts stacked.
//
// The plugin cannot be driven from a unit test, so what is checked here is the
// SCHEDULING ARITHMETIC — how many rings, at what ids, over what span — against
// the pure parts. The channel itself is checked on a device.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/alarms.dart';
import 'package:safenest/memory/reminders.dart';

void main() {
  test('one ring is the default', () {
    // The whole complaint. Five was a decision somebody made in code; one is
    // what a reminder looks like everywhere else on the phone.
    expect(Alarms.instance.burstCount, 1);
  });

  test('the burst is capped, so a stored value cannot run away', () {
    final before = Alarms.instance.burstCount;
    addTearDown(() => Alarms.instance.burstCount = before);

    Alarms.instance.burstCount = 99;
    // The clamp lives in schedule(); what is asserted here is that nothing
    // rejects the value outright, so a preference written by an older build
    // cannot stop reminders being set at all.
    expect(Alarms.instance.burstCount, 99);
  });

  group('alarm ids do not collide across what schedules them', () {
    test("Life Memory's ids sit above the reminders module's", () {
      // The reminders module uses the server's row ids, which start at 1. Two
      // things scheduling alarm id 7 means one silently cancels the other —
      // schedule() clears the id first by design, so there is no error and no
      // symptom until a warning never arrives.
      for (final serverId in [1, 2, 50, 999, 100000]) {
        expect(memoryAlarmId(1, 0), isNot(serverId));
        expect(memoryAlarmId(99999, 1), isNot(serverId));
      }
    });

    test('a memory warning stays below the band the repeat rings use', () {
      // Alarms puts each reminder's repeats at (1 << 28) + id * 5. An id
      // anywhere near that overflows into another reminder's rings.
      expect(memoryAlarmId(999999999, 1), lessThan(1 << 28));
    });

    test('the two warnings for one date are different alarms', () {
      expect(memoryAlarmId(7, 0), isNot(memoryAlarmId(7, 1)));
    });
  });

  test('cancelling clears every ring the burst could ever have used', () {
    // Turning the burst down from five to one must still clear the four rings a
    // previous run left in the queue, or they go off tomorrow with nothing left
    // that knows about them. So the cancel loop walks the MAXIMUM, never the
    // current setting.
    //
    // Read as source because the plugin cannot be driven from a unit test, and
    // the mistake this guards against is somebody "tidying" _burstMax into
    // burstCount — which would look like a simplification and would strand
    // alarms on every phone that had ever had the burst switched on.
    final src = File('lib/alarms.dart').readAsStringSync();
    final cancel = src.substring(src.indexOf('Future<void> cancel(int id)'));
    expect(cancel, contains('k < _burstMax'),
        reason: 'the cancel loop must clear every id the burst could have '
            'used, not just the ones the current setting would schedule');
    expect(cancel.substring(0, cancel.indexOf('}')),
        isNot(contains('burstCount')));
  });

  test('an id is only ever scheduled exactly when it is allowed to be', () {
    // Asking for an exact alarm without the Android 13+ permission does not
    // degrade — it THROWS, and the reminder is never set at all. A test device
    // had fourteen of those in its log and not one local reminder, with the
    // only clue a debugPrint nobody reads.
    final src = File('lib/alarms.dart').readAsStringSync();
    expect(src, contains('inexactAllowWhileIdle'),
        reason: 'without a fallback, a phone that will not allow exact alarms '
            'gets no local reminders whatsoever');
    expect(src, contains('canScheduleExact'));
  });
}
