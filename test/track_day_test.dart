// Turning a day of GPS fixes into something a person can read.
//
// This is the whole of Track Me. Recording positions is easy and almost
// useless: a day is nine hundred points and nobody wants to look at nine
// hundred points. What anybody asks is "where was I at three?", "when did I
// leave home?", "how long was I at the office?" — and all three are answered by
// the same cut of the day into stays and journeys.
//
// It is pure, and it is tested hard, because the alternative is finding out it
// was wrong by reading your own history and not recognising it — by which time
// the raw points for that day may well have been thinned away.
import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/track/day.dart';

/// Bangalore-ish, so the numbers are recognisable rather than at 0,0 where
/// every degree of longitude is its full 111km and the maths flatters itself.
const home = (12.9279, 77.6271);
const office = (12.9716, 77.5946);

final start = DateTime(2026, 10, 3, 6, 0);

Fix at(int minutes, (double, double) place,
        {double jitter = 0, double accuracy = 10}) =>
    Fix(
      at: start.add(Duration(minutes: minutes)),
      lat: place.$1 + jitter,
      lon: place.$2 + jitter,
      accuracy: accuracy,
    );

/// Fixes every [every] minutes from [from] to [to], at one place.
List<Fix> sitting(int from, int to, (double, double) place,
    {int every = 5, double drift = 0}) {
  final out = <Fix>[];
  for (var m = from; m <= to; m += every) {
    // A little drift, because a phone indoors never reports the same point
    // twice and a test with identical points would not exercise the thing that
    // actually happens.
    final d = drift == 0 ? 0.0 : drift * ((m ~/ every) % 3 - 1);
    out.add(at(m, place, jitter: d));
  }
  return out;
}

/// A straight run between two places, [steps] fixes.
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

void main() {
  group('an ordinary weekday', () {
    // Home until 8:30, a drive, the office until 17:00, a drive, home.
    final fixes = [
      ...sitting(0, 150, home, drift: 0.0004),
      ...moving(150, 195, home, office),
      ...sitting(200, 660, office, drift: 0.0003),
      ...moving(660, 710, office, home),
      ...sitting(715, 780, home, drift: 0.0004),
    ];
    final day = readDay(fixes);

    test('it comes out as places and the travel between them', () {
      expect(day.stays.length, 3, reason: 'home, office, home');
      expect(day.journeys.length, 2);
    });

    test('in time order, with nothing overlapping', () {
      for (var i = 1; i < day.spans.length; i++) {
        expect(day.spans[i].from.isBefore(day.spans[i - 1].to), isFalse,
            reason: 'span $i starts before the one before it ended');
      }
    });

    test('the morning at home is one stay, not thirty', () {
      // A phone indoors drifts tens of metres with the screen off. Anchoring on
      // consecutive distances rather than the running centre turns a quiet
      // morning into a list of thirty places.
      final first = day.spans.first;
      expect(first.kind, Part.stay);
      expect(first.lasted.inMinutes, greaterThanOrEqualTo(145));
    });

    test('the office is the longest thing in the day', () {
      final longest = day.stays
          .reduce((a, b) => a.lasted > b.lasted ? a : b);
      expect(metresBetween(longest.lat, longest.lon, office.$1, office.$2),
          lessThan(stayRadius));
      expect(longest.lasted.inHours, greaterThanOrEqualTo(7));
    });

    test('the drive is one journey, not eleven', () {
      // Every time the car slows the cluster breaks. Without merging, a commute
      // reads as eleven journeys separated by nothing.
      final out = day.journeys.first;
      expect(out.metres, greaterThan(3000));
      expect(out.path.length, greaterThan(4));
    });

    test('and the day knows how far you went', () {
      expect(day.metres, greaterThan(8000));
    });
  });

  group('what is NOT a place', () {
    test('a traffic light is not somewhere you went', () {
      // Distance alone makes a junction a place. Both halves of the rule are
      // needed: close together AND for long enough.
      final fixes = [
        ...moving(0, 20, home, office, steps: 6),
        // Three minutes stopped at a junction.
        at(21, office), at(22, office), at(23, office),
        ...moving(24, 40, office, home, steps: 6),
      ];
      final day = readDay(fixes);
      expect(day.stays, isEmpty);
    });

    test('a slow walk is not a place either', () {
      // Time alone makes a slow walk a place. These fixes are an hour apart in
      // time and hundreds of metres apart in space.
      final out = <Fix>[];
      for (var i = 0; i < 12; i++) {
        out.add(Fix(
          at: start.add(Duration(minutes: i * 5)),
          lat: home.$1 + i * 0.004,
          lon: home.$2,
          accuracy: 10,
        ));
      }
      expect(readDay(out).stays, isEmpty);
    });

    test('ten minutes in one spot IS a place', () {
      final day = readDay(sitting(0, 12, home, every: 3));
      expect(day.stays.length, 1);
    });

    test('nine minutes is not', () {
      final day = readDay(sitting(0, 9, home, every: 3));
      expect(day.stays, isEmpty);
    });
  });

  group('bad data', () {
    test('a fix the phone is not sure about is dropped, not averaged in', () {
      // Accuracy worse than 200m is a guess from cell towers that can be a
      // kilometre out. Averaging it into a stay MOVES THE PLACE, which is worse
      // than not having it: the timeline then says you were somewhere you have
      // never been.
      final good = sitting(0, 60, home, every: 5);
      final withJunk = [
        ...good,
        Fix(at: start.add(const Duration(minutes: 30)),
            lat: home.$1 + 0.05, lon: home.$2 + 0.05, accuracy: 1500),
      ];
      final clean = readDay(good).stays.first;
      final dirty = readDay(withJunk).stays.first;
      expect(metresBetween(clean.lat, clean.lon, dirty.lat, dirty.lon),
          lessThan(1.0));
    });

    test('a fix with impossible coordinates is thrown away', () {
      final day = readDay([
        ...sitting(0, 30, home, every: 5),
        Fix(at: start.add(const Duration(minutes: 10)), lat: 999, lon: 999),
      ]);
      expect(day.stays.length, 1);
    });

    test('points out of order are still read correctly', () {
      // A store that returns them any other way would otherwise produce a
      // plausible-looking and completely wrong timeline.
      final ordered = sitting(0, 60, home, every: 5);
      final jumbled = [...ordered.reversed];
      expect(readDay(jumbled).stays.length, readDay(ordered).stays.length);
    });

    test('an empty day is empty, not an error', () {
      expect(readDay(const []).isEmpty, isTrue);
      expect(readDay(const []).metres, 0);
    });

    test('a single fix is not a day', () {
      expect(readDay([at(0, home)]).spans, isEmpty);
    });
  });

  group('when the phone stops watching', () {
    test('a long silence is a gap, not a journey', () {
      // Flat battery, a basement, permission withdrawn. Drawing a line across
      // it would invent a journey that may never have happened — and across a
      // city that line is a lie about where somebody was.
      final day = readDay([
        ...sitting(0, 60, home, every: 5),
        ...sitting(300, 360, office, every: 5),
      ]);
      expect(day.spans.where((s) => s.kind == Part.gap), hasLength(1));
      expect(day.metres, 0, reason: 'nothing was measured across the gap');
    });

    test('a short silence is not', () {
      final day = readDay([
        ...sitting(0, 60, home, every: 5),
        ...moving(80, 110, home, office),
        ...sitting(115, 180, office, every: 5),
      ]);
      expect(day.spans.where((s) => s.kind == Part.gap), isEmpty);
    });

    test('the gap sits between the two things it separates', () {
      final day = readDay([
        ...sitting(0, 60, home, every: 5),
        ...sitting(300, 360, office, every: 5),
      ]);
      final i = day.spans.indexWhere((s) => s.kind == Part.gap);
      expect(i, 1);
      expect(day.spans[0].kind, Part.stay);
      expect(day.spans[2].kind, Part.stay);
    });
  });

  group('answering where you were', () {
    final day = readDay([
      ...sitting(0, 150, home, drift: 0.0004),
      ...moving(150, 195, home, office),
      ...sitting(200, 660, office, drift: 0.0003),
    ]);

    test('a time inside a stay is answered by that stay', () {
      // 10:00 — the middle of the office.
      final span = whereAt(day, DateTime(2026, 10, 3, 10, 0));
      expect(span, isNotNull);
      expect(span!.kind, Part.stay);
      expect(metresBetween(span.lat, span.lon, office.$1, office.$2),
          lessThan(stayRadius));
    });

    test('a time mid-journey is answered by the journey', () {
      final span = whereAt(day, DateTime(2026, 10, 3, 8, 45));
      expect(span?.kind, Part.journey);
    });

    test('the exact moment a stay began belongs to that stay', () {
      // A strict comparison on one side answers null here, which reads as "we
      // were not tracking" for a moment that is on the record.
      final first = day.spans.first;
      expect(whereAt(day, first.from), isNotNull);
      expect(whereAt(day, first.to), isNotNull);
    });

    test('a time nothing covers answers null rather than guessing', () {
      expect(whereAt(day, DateTime(2026, 10, 3, 23, 30)), isNull);
    });

    test('...and the nearest thing is offered instead', () {
      // "You were not being tracked then, but an hour earlier you were here" is
      // a far better answer than a blank screen.
      final near = nearestTo(day, DateTime(2026, 10, 3, 23, 30));
      expect(near, isNotNull);
      expect(near!.kind, Part.stay);
    });

    test('nearest works before the day started too', () {
      final near = nearestTo(day, DateTime(2026, 10, 3, 1, 0));
      expect(near, isNotNull);
      expect(near!.from, day.spans.first.from);
    });

    test('an empty day has no nearest', () {
      expect(nearestTo(const Day(spans: [], metres: 0), DateTime(2026, 1, 1)),
          isNull);
    });
  });

  group('the distance arithmetic', () {
    test('two identical points are no distance apart', () {
      expect(metresBetween(home.$1, home.$2, home.$1, home.$2), lessThan(0.01));
    });

    test('home to office is about five kilometres', () {
      final m = metresBetween(home.$1, home.$2, office.$1, office.$2);
      expect(m, greaterThan(4500));
      expect(m, lessThan(6500));
    });

    test('longitude is scaled by latitude', () {
      // The reason this is haversine and not the flat approximation: a degree of
      // longitude is 111km at the equator and 78km in Bangalore, and getting
      // that wrong moves a hundred-metre boundary by a street.
      final equator = metresBetween(0, 0, 0, 1);
      final here = metresBetween(13, 0, 13, 1);
      expect(here, lessThan(equator * 0.99));
    });
  });
}
