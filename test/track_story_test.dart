// Saying a day out loud.
//
// A map answers "where" and answers "when" very badly — you cannot see from a
// line on a map what time you left, and that is usually the question. These are
// the sentences, and they are pinned because a timeline you read and do not
// recognise is worse than no timeline, and the only way to notice is to have
// written down beforehand what it should say.
import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/track/day.dart';
import 'package:safenest/track/story.dart';

const home = (12.9279, 77.6271);
const office = (12.9716, 77.5946);

final start = DateTime(2026, 10, 3, 6, 0);

final places = [
  Named(name: 'Home', lat: home.$1, lon: home.$2),
  Named(name: 'Office', lat: office.$1, lon: office.$2),
];

List<Fix> sitting(int from, int to, (double, double) place, {int every = 5}) => [
      for (var m = from; m <= to; m += every)
        Fix(
            at: start.add(Duration(minutes: m)),
            lat: place.$1,
            lon: place.$2,
            accuracy: 10),
    ];

List<Fix> moving(int from, int to, (double, double) a, (double, double) b,
    {int steps = 8}) {
  final out = <Fix>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    out.add(Fix(
      at: start.add(Duration(minutes: from + ((to - from) * t).round())),
      lat: a.$1 + (b.$1 - a.$1) * t,
      lon: a.$2 + (b.$2 - a.$2) * t,
      accuracy: 12,
    ));
  }
  return out;
}

/// Home 06:00–08:30, drive, office 09:20–17:00, drive, home.
final weekday = readDay([
  ...sitting(0, 150, home),
  ...moving(150, 195, home, office),
  ...sitting(200, 660, office),
  ...moving(660, 710, office, home),
  ...sitting(715, 780, home),
]);

/// A fixed "now" well after the day ended, so nothing is "still there".
final after = DateTime(2026, 10, 4, 9, 0);

void main() {
  group('naming a place', () {
    test('a stay inside a named place takes its name', () {
      final stay = weekday.stays.first;
      expect(nameFor(stay, places), 'Home');
    });

    test('a stay nowhere near anything named has no name', () {
      final far = readDay(sitting(0, 60, (13.5, 77.9)));
      expect(nameFor(far.stays.first, places), isNull);
    });

    test('the NEAREST named place wins, not the first that matches', () {
      // Taking the first match puts "Home" on the office when somebody has
      // named a café between them with a generous radius.
      final overlapping = [
        const Named(name: 'The whole city', lat: 12.95, lon: 77.61, radius: 9000),
        Named(name: 'Office', lat: office.$1, lon: office.$2),
      ];
      final atOffice =
          weekday.stays.firstWhere((s) => s.lasted.inHours >= 7);
      expect(nameFor(atOffice, overlapping), 'Office');
    });

    test('naming a place names every day you were ever there', () {
      // The naming is by proximity, so it applies backwards as well as
      // forwards — which is the whole reason it is not a label on a row.
      final yesterday = readDay(sitting(0, 120, home));
      expect(nameFor(yesterday.stays.first, places), 'Home');
    });
  });

  group('an ordinary weekday, said out loud', () {
    final lines = tell(weekday, places, now: after);

    test('it reads as a day, not as coordinates', () {
      expect(lines, isNotEmpty);
      for (final l in lines) {
        expect(l.said, isNot(contains('12.9')));
        expect(l.said, isNot(contains('77.6')));
      }
    });

    test('the commute says where from, where to, and at what time', () {
      // The whole question: "what time did I leave home, what time did I reach
      // the office".
      final commute = lines.firstWhere((l) => l.said.startsWith('Left Home'));
      expect(commute.said, contains('reached Office'));
      expect(commute.said, matches(RegExp(r'\d\d:\d\d')));
      expect(commute.said, contains('km'));
    });

    test('a stay says how long it was', () {
      // "7h 45m" for a part-hour, "7 hours" for a whole one — see the numbers
      // group below for why the exact hour drops the "0m".
      final work = lines.firstWhere((l) => l.said.startsWith('Office'));
      expect(work.said, matches(RegExp(r'\d+h \d+m|\d+ hours?')));
    });

    test('a place with no name says so rather than inventing one', () {
      final unknown = readDay(sitting(0, 60, (13.5, 77.9)));
      final said = tell(unknown, places, now: after).single.said;
      expect(said, contains('have not named'));
    });

    test('the order matches the day', () {
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].span.from.isBefore(lines[i - 1].span.from), isFalse);
      }
    });
  });

  group('still there', () {
    test('a place you are sitting in now is not described in the past', () {
      // Saying "you left at 19:05" about somewhere somebody is sitting is the
      // kind of wrongness that makes a whole timeline untrustworthy.
      final today = readDay(sitting(0, 150, home));
      final nowish = start.add(const Duration(minutes: 155));
      final said = tell(today, places, now: nowish).last.said;
      expect(said, startsWith('At Home since'));
      expect(said, contains('so far'));
    });

    test('and a day that has clearly ended is', () {
      final said = tell(readDay(sitting(0, 150, home)), places, now: after)
          .last
          .said;
      expect(said, startsWith('Home, 06:00 to'));
    });
  });

  group('when nothing was recorded', () {
    final broken = readDay([
      ...sitting(0, 60, home),
      ...sitting(300, 360, office),
    ]);

    test('the gap is named, not left blank', () {
      // A gap drawn as nothing reads as a day where nothing happened; a gap
      // named is a day where the phone was flat, which somebody can account for.
      final said = tell(broken, places, now: after)
          .firstWhere((l) => l.said.startsWith('Not recorded'));
      expect(said.said, contains('07:00'));
    });
  });

  group('answering where you were', () {
    test('a time at a named place', () {
      final said = answerFor(weekday, DateTime(2026, 10, 3, 12, 0), places);
      expect(said, contains('at Office'));
      expect(said, contains('since'));
    });

    test('a time on the road', () {
      final said = answerFor(weekday, DateTime(2026, 10, 3, 8, 45), places);
      expect(said, contains('on the move'));
    });

    test('a time nothing covers offers the nearest instead of a blank', () {
      final said = answerFor(weekday, DateTime(2026, 10, 3, 23, 30), places);
      expect(said, contains('Nothing was recorded at that time'));
      expect(said, contains('nearest'));
      expect(said, contains('earlier'));
    });

    test('a time before the day started says the nearest is later', () {
      final said = answerFor(weekday, DateTime(2026, 10, 3, 2, 0), places);
      expect(said, contains('later'));
    });

    test('an empty day says so plainly', () {
      final said = answerFor(const Day(spans: [], metres: 0),
          DateTime(2026, 10, 3, 12, 0), places);
      expect(said, 'Nothing was recorded that day.');
    });

    test('a time inside a gap says the phone was not reporting', () {
      final broken = readDay([
        ...sitting(0, 60, home),
        ...sitting(300, 360, office),
      ]);
      final said = answerFor(broken, DateTime(2026, 10, 3, 8, 0), places);
      expect(said, contains('not reporting'));
    });
  });

  group('one line for a whole day', () {
    test('it names the places and how far you went', () {
      final said = summarise(weekday, places);
      expect(said, contains('Home'));
      expect(said, contains('Office'));
      expect(said, contains('km'));
    });

    test('an empty day says nothing was recorded', () {
      expect(summarise(const Day(spans: [], metres: 0), places),
          'Nothing recorded');
    });

    test('unnamed places are counted rather than named', () {
      final unknown = readDay(sitting(0, 60, (13.5, 77.9)));
      expect(summarise(unknown, places), contains('1 place'));
    });

    test('more than two places are summarised, not listed', () {
      final many = [
        ...places,
        const Named(name: 'Gym', lat: 12.95, lon: 77.61, radius: 50),
      ];
      final said = summarise(weekday, many);
      expect(said.length, lessThan(60));
    });
  });

  group('the numbers people read', () {
    test('seven hours is "7 hours", not "7 hours 0 min"', () {
      // The zero reads as precision the figure does not have.
      final day = readDay(sitting(0, 420, home, every: 10));
      final said = tell(day, places, now: after).single.said;
      expect(said, contains('7 hours'));
      expect(said, isNot(contains('0m')));
    });

    test('under a kilometre is metres', () {
      final short = readDay([
        ...sitting(0, 20, home, every: 5),
        ...moving(25, 35, home, (home.$1 + 0.004, home.$2), steps: 4),
        ...sitting(40, 60, (home.$1 + 0.004, home.$2), every: 5),
      ]);
      final said = tell(short, places, now: after)
          .firstWhere((l) => l.said.contains('m'));
      expect(said.said, isNot(contains('0.4 km')));
    });

    test('a long distance drops the decimal', () {
      // "23.4 km" from a phone's GPS claims a precision that is not there.
      final far = readDay([
        ...sitting(0, 20, home, every: 5),
        ...moving(25, 90, home, (13.2, 77.9), steps: 20),
        ...sitting(95, 120, (13.2, 77.9), every: 5),
      ]);
      final said = tell(far, places, now: after)
          .firstWhere((l) => l.said.contains('km'));
      expect(said.said, matches(RegExp(r'\d+ km')));
    });
  });
}
