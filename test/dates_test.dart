/// One date format for people, another for the server — and they must not swap.
///
/// The display format changed to dd-mm-yyyy. The WIRE format did not, and must
/// not: send "08-08-2026" where the API expects "2026-08-08" and the record
/// lands on a different day, or is rejected, and nothing on screen says so.
/// That is the failure worth a test.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/dates.dart';

void main() {
  final aug8 = DateTime(2026, 8, 8, 22, 26);
  final jan3 = DateTime(2026, 1, 3, 9, 5);

  group('what a person reads', () {
    test('dates are dd-mm-yyyy, zero padded', () {
      expect(fmtDate(aug8), '08-08-2026');
      // The single-digit day and month are the whole reason for padding: the
      // scanner used to print "3/1/2026", which is also a valid reading of
      // 1 March in half the world.
      expect(fmtDate(jan3), '03-01-2026');
    });

    test('a null date is empty, not the word null', () {
      expect(fmtDate(null), '');
      expect(fmtDateTime(null), '');
      expect(fmtTime(null), '');
    });

    test('date and time together', () {
      expect(fmtDateTime(aug8), '08-08-2026 · 10:26 PM');
      expect(fmtDateTime(jan3), '03-01-2026 · 9:05 AM');
    });

    test('twelve hour, with AM and PM', () {
      // Never 22:26. A 24-hour clock is something people convert in their
      // heads, and this is read by someone checking when a bill was paid.
      expect(fmtTime(aug8), '10:26 PM');
      expect(fmtTime(jan3), '9:05 AM');
      expect(fmtTime(aug8), isNot(contains('22')));
    });
  });

  group('what the server gets', () {
    test('the wire format is still ISO, NOT the display format', () {
      expect(wireDate(aug8), '2026-08-08');
      expect(wireDate(jan3), '2026-01-03');
      // Stated as its own assertion because this is the one that costs data if
      // it ever changes.
      expect(wireDate(aug8), isNot(fmtDate(aug8)));
    });
  });

  group('reading a date back', () {
    test('ISO from the server', () {
      expect(parseDate('2026-08-08'), DateTime(2026, 8, 8));
      expect(parseDate('2026-08-08T22:26:00')?.hour, 22);
    });

    test('dd-mm-yyyy as a person would type it', () {
      expect(parseDate('08-08-2026'), DateTime(2026, 8, 8));
      expect(parseDate('8/8/2026'), DateTime(2026, 8, 8));
    });

    test('nonsense is null, never a throw', () {
      // A date that cannot be read should leave a field blank, not take down
      // the screen it is on.
      expect(parseDate(''), isNull);
      expect(parseDate(null), isNull);
      expect(parseDate('not a date'), isNull);
      expect(parseDate('45-45-2026'), isNull);
    });
  });

  group('the activity log still reads naturally for recent things', () {
    test('relative for the last week', () {
      final now = DateTime.now();
      expect(relative(now), 'Just now');
      expect(relative(now.subtract(const Duration(minutes: 30))), '30m ago');
      expect(relative(now.subtract(const Duration(hours: 5))), '5h ago');
      expect(relative(now.subtract(const Duration(days: 1))), 'Yesterday');
    });

    test('and the plain date once it stops being recent', () {
      expect(relative(DateTime(2020, 3, 9)), '09-03-2020');
    });
  });
}

