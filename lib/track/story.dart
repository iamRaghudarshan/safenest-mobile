/// Saying a day out loud.
///
/// `day.dart` cuts the fixes into stays and journeys; this turns those into the
/// sentences somebody actually asked for — "left home at 08:42, reached the
/// office at 09:31, seven hours there". A map answers "where" and answers
/// "when" very badly: you cannot see from a line on a map what time you left,
/// and that is usually the question.
///
/// NAMED PLACES COME FROM THE PERSON, never from a lookup. A reverse-geocode
/// would send the coordinates of somebody's house to a stranger's server to be
/// told what they already know, which is the one thing this module is built not
/// to do. Name "Home" once and every evening you have ever spent there is
/// named, because the naming is by proximity and applies backwards as well as
/// forwards.
///
/// Pure. `now` is passed in, places are passed in, and every sentence below is
/// pinned by a test — a timeline you read and do not recognise is worse than no
/// timeline, and the only way to notice is to have written down what it should
/// say.
library;

import 'package:flutter/foundation.dart';

import 'day.dart';

/// Somewhere with a name.
@immutable
class Named {
  const Named({
    required this.name,
    required this.lat,
    required this.lon,
    this.radius = 150,
  });

  final String name;
  final double lat;
  final double lon;

  /// How close counts as being here. Bigger than a stay's own radius on
  /// purpose: a house, its gate and the shop on the corner are one place to
  /// anybody describing their day.
  final double radius;
}

/// One line of the day.
@immutable
class Line {
  const Line({
    required this.span,
    required this.said,
    this.place,
  });

  final Span span;

  /// The sentence.
  final String said;

  /// The name, when the place has one.
  final String? place;

  @override
  String toString() => said;
}

/// The name for a stay, or null when nowhere named is close enough.
String? nameFor(Span span, List<Named> places) {
  String? best;
  var closest = double.infinity;
  for (final p in places) {
    final d = metresBetween(span.lat, span.lon, p.lat, p.lon);
    // WITHIN the place's own radius, and then the NEAREST of those. Taking the
    // first match instead puts "Home" on the office when somebody has named a
    // café between them with a generous radius.
    if (d <= p.radius && d < closest) {
      closest = d;
      best = p.name;
    }
  }
  return best;
}

/// The whole day, in sentences.
List<Line> tell(Day day, List<Named> places, {DateTime? now}) {
  final out = <Line>[];
  final at = now ?? DateTime.now();

  for (var i = 0; i < day.spans.length; i++) {
    final s = day.spans[i];
    final name = s.kind == Part.stay ? nameFor(s, places) : null;

    switch (s.kind) {
      case Part.stay:
        final where = name ?? 'somewhere you have not named';
        final last = i == day.spans.length - 1;
        // STILL THERE, not "left at", when the day is today and this is the end
        // of it. Saying "you left at 19:05" about a place somebody is sitting in
        // is the kind of wrongness that makes a whole timeline untrustworthy.
        final stillThere = last && _sameDay(s.to, at) && at.difference(s.to) < const Duration(minutes: 90);
        out.add(Line(
          span: s,
          place: name,
          said: stillThere
              ? 'At $where since ${_clock(s.from)} — ${_howLong(s.lasted)} so far'
              : '$where, ${_clock(s.from)} to ${_clock(s.to)} '
                  '(${_howLong(s.lasted)})',
        ));

      case Part.journey:
        final to = i + 1 < day.spans.length ? day.spans[i + 1] : null;
        final from = i > 0 ? day.spans[i - 1] : null;
        final fromName = from != null && from.kind == Part.stay
            ? nameFor(from, places)
            : null;
        final toName =
            to != null && to.kind == Part.stay ? nameFor(to, places) : null;

        if (fromName != null && toName != null) {
          out.add(Line(
            span: s,
            said: 'Left $fromName at ${_clock(s.from)}, reached $toName at '
                '${_clock(s.to)} — ${_howFar(s.metres)}, '
                '${_howLong(s.lasted)}',
          ));
        } else if (toName != null) {
          out.add(Line(
            span: s,
            said: 'Travelled to $toName, arriving ${_clock(s.to)} — '
                '${_howFar(s.metres)}',
          ));
        } else if (fromName != null) {
          out.add(Line(
            span: s,
            said: 'Left $fromName at ${_clock(s.from)} — ${_howFar(s.metres)}, '
                '${_howLong(s.lasted)}',
          ));
        } else {
          out.add(Line(
            span: s,
            said: 'Moving, ${_clock(s.from)} to ${_clock(s.to)} — '
                '${_howFar(s.metres)}',
          ));
        }

      case Part.gap:
        // SAYING IT STOPPED WATCHING. A gap drawn as nothing reads as a day
        // where nothing happened; a gap named is a day where the phone was
        // flat, or in a basement, or recording was off — all of which are
        // things somebody can account for.
        out.add(Line(
          span: s,
          said: 'Not recorded between ${_clock(s.from)} and ${_clock(s.to)} '
              '(${_howLong(s.lasted)})',
        ));
    }
  }
  return out;
}

/// One sentence for the whole day, for a list of days.
String summarise(Day day, List<Named> places) {
  if (day.isEmpty) return 'Nothing recorded';
  final named = <String>[];
  for (final s in day.stays) {
    final n = nameFor(s, places);
    if (n != null && !named.contains(n)) named.add(n);
  }
  final far = _howFar(day.metres);
  if (named.isEmpty) {
    final n = day.stays.length;
    return n == 0
        ? 'On the move — $far'
        : '$n place${n == 1 ? '' : 's'} — $far';
  }
  if (named.length == 1) return '${named.first} — $far';
  if (named.length == 2) return '${named[0]} and ${named[1]} — $far';
  return '${named.take(2).join(', ')} and ${named.length - 2} more — $far';
}

/// The answer to "where was I on the 14th at three?".
String answerFor(Day day, DateTime at, List<Named> places) {
  final span = whereAt(day, at);
  if (span != null) {
    switch (span.kind) {
      case Part.stay:
        final name = nameFor(span, places);
        return name == null
            ? 'You were somewhere you have not named — there since '
                '${_clock(span.from)}'
            : 'You were at $name, and had been since ${_clock(span.from)}';
      case Part.journey:
        return 'You were on the move — ${_clock(span.from)} to '
            '${_clock(span.to)}, ${_howFar(span.metres)}';
      case Part.gap:
        return 'Nothing was recorded then — the phone was not reporting '
            'between ${_clock(span.from)} and ${_clock(span.to)}';
    }
  }

  // NOTHING COVERS IT. The nearest thing is a far better answer than a blank:
  // "not then, but an hour earlier you were at the office" is usually enough.
  final near = nearestTo(day, at);
  if (near == null) return 'Nothing was recorded that day.';
  final name = near.kind == Part.stay ? nameFor(near, places) : null;
  final which = at.isBefore(near.from) ? 'later' : 'earlier';
  return 'Nothing was recorded at that time. The nearest is '
      '$which that day: ${name ?? 'somewhere you have not named'}, '
      '${_clock(near.from)} to ${_clock(near.to)}.';
}

// ------------------------------------------------------------------ words

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _howLong(Duration d) {
  final mins = d.inMinutes;
  if (mins < 1) return 'under a minute';
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  // "7 hours" rather than "7 hours 0 min". The zero reads as precision the
  // figure does not have.
  if (m == 0) return '$h hour${h == 1 ? '' : 's'}';
  return '${h}h ${m}m';
}

String _howFar(double metres) {
  if (metres < 1000) return '${metres.round()} m';
  final km = metres / 1000;
  // One decimal below ten kilometres, none above: "23.4 km" from a phone's GPS
  // claims a precision that is not there.
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}
