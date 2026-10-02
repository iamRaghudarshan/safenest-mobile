// Turning a confirmed date into a notification.
//
// The whole value of this module's warranty tagging is a notification two years
// from now, and there is no way to check that by hand — which is exactly why
// `remindersFor` is pure and all of it is here. Every one of these cases is
// something that would otherwise only be observable in 2028.
import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/memory/reminders.dart';

Map<String, dynamic> dated(
  int factId,
  String value,
  DateTime at, {
  String body = 'Bought the washing machine. Two year warranty.',
}) =>
    {
      'id': factId,
      'memory_id': 1,
      'kind': 'expiry',
      'value': value,
      'at': at.toIso8601String(),
      'body': body,
      'photo_path': null,
    };

void main() {
  final now = DateTime(2026, 10, 2, 9, 0);

  test('a date far ahead gets both warnings, soonest last', () {
    final out = remindersFor(
        [dated(5, 'Warranty ends 26 Sep 2028', DateTime(2028, 9, 26))], now);

    expect(out, hasLength(2));
    expect(out.first.when, DateTime(2028, 8, 27), reason: '30 days before');
    expect(out.last.when, DateTime(2028, 9, 19), reason: '7 days before');
  });

  test('it rings before the day, not on it', () {
    // A warranty that ends today is a warranty you cannot use: calling,
    // claiming or renewing all take longer than the morning it expires.
    final out = remindersFor(
        [dated(5, 'Warranty ends 26 Sep 2028', DateTime(2028, 9, 26))], now);
    for (final r in out) {
      expect(r.when.isBefore(DateTime(2028, 9, 26)), isTrue);
    }
  });

  test('a fortnight away gets the week warning only', () {
    // The month's notice is already behind us. Scheduling it anyway is how
    // every reminder from the last year goes off the next time the app opens.
    final out = remindersFor(
        [dated(5, 'Warranty ends 14 Oct 2026', DateTime(2026, 10, 14))], now);
    expect(out, hasLength(1));
    expect(out.single.when, DateTime(2026, 10, 7));
  });

  test('something already expired gets nothing at all', () {
    final out = remindersFor(
        [dated(5, 'Warranty ends 1 Jan 2024', DateTime(2024, 1, 1))], now);
    expect(out, isEmpty);
  });

  test('the words it came from are what rings', () {
    // In two years the only thing that will make a notification intelligible is
    // the sentence that caused it. "Warranty ends" alone is not enough to know
    // which appliance.
    final out = remindersFor(
        [
          dated(5, 'Warranty ends 26 Sep 2028', DateTime(2028, 9, 26),
              body: 'Bought the Bosch washing machine from Vijay Sales.')
        ],
        now);
    expect(out.first.title, 'Warranty ends 26 Sep 2028');
    expect(out.first.body, contains('Bosch washing machine'));
  });

  test('a very long memory is trimmed rather than truncated mid-notification',
      () {
    final long = 'x' * 400;
    final out = remindersFor(
        [dated(5, 'Warranty ends 26 Sep 2028', DateTime(2028, 9, 26), body: long)],
        now);
    expect(out.first.body.length, lessThanOrEqualTo(120));
    expect(out.first.body, endsWith('…'));
  });

  test('a memory with no words still says something', () {
    final out = remindersFor(
        [dated(5, 'Warranty ends 26 Sep 2028', DateTime(2028, 9, 26), body: '')],
        now);
    expect(out.first.body, isNotEmpty);
  });

  group('alarm ids', () {
    test('the two warnings for one date never collide', () {
      final out = remindersFor(
          [dated(5, 'Warranty ends 26 Sep 2028', DateTime(2028, 9, 26))], now);
      expect(out.first.id, isNot(out.last.id));
    });

    test('the same fact always gets the same ids, so re-syncing moves them',
        () {
      // Alarms.schedule cancels the id before setting it. An id that changed
      // between runs would leave the old alarm in place AND add a new one, so
      // the warning would arrive twice and keep doing so.
      final rows = [dated(5, 'Warranty ends 26 Sep 2028', DateTime(2028, 9, 26))];
      final a = remindersFor(rows, now);
      final b = remindersFor(rows, now.add(const Duration(days: 3)));
      expect([for (final r in a) r.id], [for (final r in b) r.id]);
    });

    test('they sit above the reminders module, which starts at 1', () {
      // Two things scheduling alarm id 7 means one silently cancels the other,
      // with no error and no symptom until a warranty warning never arrives.
      expect(memoryAlarmId(1, 0), greaterThan(1000000));
      expect(memoryAlarmId(7, 0), isNot(7));
    });

    test('they stay well inside the burst band and inside 32 bits', () {
      // Alarms gives each reminder repeat rings at (1 << 28) + id * 5, so an id
      // anywhere near that overflows into another reminder's rings.
      expect(memoryAlarmId(999999999, 1), lessThan(1 << 28));
      expect(memoryAlarmId(999999999, 1), greaterThan(0));
    });
  });

  test('several dates all come back, soonest first', () {
    final out = remindersFor([
      dated(5, 'Warranty ends 26 Sep 2028', DateTime(2028, 9, 26)),
      dated(6, 'Warranty ends 2 Mar 2027', DateTime(2027, 3, 2)),
    ], now);
    expect(out, hasLength(4));
    expect(out.first.when.isBefore(out.last.when), isTrue);
  });

  test('a row with a broken date is skipped, not crashed on', () {
    final out = remindersFor([
      {'id': 5, 'value': 'nonsense', 'at': 'not a date', 'body': 'x'},
      {'value': 'no id at all', 'at': '2028-09-26T00:00:00.000', 'body': 'x'},
    ], now);
    expect(out, isEmpty);
  });
}
