/// Turning a day of GPS fixes into something a person can read.
///
/// THIS IS THE WHOLE MODULE. Recording positions is easy and almost useless: a
/// day is nine hundred points, and nobody wants to look at nine hundred points.
/// What anybody actually asks is "where was I at three?", "when did I leave
/// home?", "how long was I at the office?" — and the answer to all three is the
/// same structure, which is a day cut into STAYS (you were somewhere) and
/// JOURNEYS (you were going between two somewheres).
///
/// Everything here is pure: points in, a day out, `now` never consulted. That
/// matters more than usual, because the alternative is finding out it was wrong
/// by reading your own history and not recognising it — and by then the raw
/// points for that day may well have been thinned.
///
/// THE RULES, and why each is what it is:
///
///   * A STAY is points that stay inside [stayRadius] for at least
///     [shortestStay]. Both halves are needed. Distance alone makes a traffic
///     light a place; time alone makes a slow walk a place.
///   * GPS WANDERS WHEN YOU DO NOT. Sitting indoors, fixes drift tens of metres
///     — so a stay is anchored on its running centre, not on consecutive
///     distances, and a single far point does not end it.
///   * A BAD FIX IS DROPPED, not smoothed. Accuracy worse than [worstAccuracy]
///     is a guess from cell towers that can be a kilometre out, and averaging it
///     into a stay moves the place.
///   * A GAP IS NOT A JOURNEY. The phone goes flat, or sleeps in a basement. If
///     nothing is recorded for [longestGap] the day says it does not know,
///     rather than drawing a straight line through a city.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Points this close together are the same place.
///
/// 120m sounds generous and is not: a phone indoors, on a bad day, with the
/// screen off, drifts further than that, and a house and the shop across the
/// road are rarely two places anybody wants told apart in a timeline.
const stayRadius = 120.0;

/// Below this, you were passing through.
///
/// Ten minutes keeps traffic lights, petrol stations and a wait at a junction
/// out of the timeline, and keeps "popped into the chemist" in it.
const shortestStay = Duration(minutes: 10);

/// A fix worse than this is thrown away.
const worstAccuracy = 200.0;

/// Longer than this without a fix and the day admits it stopped watching.
const longestGap = Duration(minutes: 45);

@immutable
class Fix {
  const Fix({
    required this.at,
    required this.lat,
    required this.lon,
    this.accuracy = 0,
  });

  final DateTime at;
  final double lat;
  final double lon;

  /// Metres. 0 means the phone did not say, which is treated as good: refusing
  /// every fix that forgot to report its accuracy would empty the day.
  final double accuracy;

  @override
  String toString() =>
      '${at.toIso8601String()} $lat,$lon ±${accuracy.round()}m';
}

enum Part { stay, journey, gap }

@immutable
class Span {
  const Span({
    required this.kind,
    required this.from,
    required this.to,
    required this.lat,
    required this.lon,
    this.metres = 0,
    this.fixes = 0,
    this.path = const [],
  });

  final Part kind;
  final DateTime from;
  final DateTime to;

  /// Where it was, for a stay: the centre of its fixes. For a journey, the
  /// middle of the path — somewhere to put a pin when the whole line is too
  /// small to see.
  final double lat;
  final double lon;

  /// How far, for a journey. Along the path, not as the crow flies: the number
  /// people recognise is the one the road took.
  final double metres;

  /// How many fixes went into it, which is the honest measure of how much this
  /// is worth believing.
  final int fixes;

  /// The line to draw. Empty for a stay — a stay is a pin, not a line.
  final List<Fix> path;

  Duration get lasted => to.difference(from);

  @override
  String toString() => '$kind ${from.hour}:${from.minute}-${to.hour}:${to.minute}';
}

/// A whole day, in order.
@immutable
class Day {
  const Day({required this.spans, required this.metres});

  final List<Span> spans;

  /// Everything travelled that day.
  final double metres;

  bool get isEmpty => spans.isEmpty;

  Iterable<Span> get stays => spans.where((s) => s.kind == Part.stay);
  Iterable<Span> get journeys => spans.where((s) => s.kind == Part.journey);
}

// ------------------------------------------------------------------ making

/// Cut [fixes] into stays, journeys and gaps.
///
/// [fixes] must be for one day and in time order; `readDay` sorts and filters
/// defensively anyway, because a store that returns them any other way would
/// otherwise produce a plausible-looking and completely wrong timeline.
Day readDay(List<Fix> fixes) {
  final good = [
    for (final f in fixes)
      if (f.accuracy <= worstAccuracy && f.lat.abs() <= 90 && f.lon.abs() <= 180)
        f
  ]..sort((a, b) => a.at.compareTo(b.at));

  if (good.isEmpty) return const Day(spans: [], metres: 0);

  final spans = <Span>[];
  var cluster = <Fix>[good.first];

  void flush(List<Fix> group) {
    if (group.isEmpty) return;
    final lasted = group.last.at.difference(group.first.at);
    final c = _centre(group);
    if (group.length > 1 && lasted >= shortestStay) {
      spans.add(Span(
        kind: Part.stay,
        from: group.first.at,
        to: group.last.at,
        lat: c.$1,
        lon: c.$2,
        fixes: group.length,
      ));
    } else {
      // TOO SHORT TO BE A PLACE, so it belongs to the movement around it. Held
      // back and merged below rather than emitted, because two passing clusters
      // either side of a road are one journey, not two.
      spans.add(Span(
        kind: Part.journey,
        from: group.first.at,
        to: group.last.at,
        lat: c.$1,
        lon: c.$2,
        metres: _along(group),
        fixes: group.length,
        path: List.unmodifiable(group),
      ));
    }
  }

  for (var i = 1; i < good.length; i++) {
    final f = good[i];
    final since = f.at.difference(good[i - 1].at);

    if (since > longestGap) {
      // THE PHONE STOPPED WATCHING. Flat battery, a basement, permission
      // withdrawn. Drawing a line across it would invent a journey that may
      // never have happened.
      flush(cluster);
      spans.add(Span(
        kind: Part.gap,
        from: good[i - 1].at,
        to: f.at,
        lat: good[i - 1].lat,
        lon: good[i - 1].lon,
      ));
      cluster = [f];
      continue;
    }

    final c = _centre(cluster);
    if (metresBetween(c.$1, c.$2, f.lat, f.lon) <= stayRadius) {
      cluster.add(f);
    } else {
      flush(cluster);
      cluster = [f];
    }
  }
  flush(cluster);

  final merged = _merge(spans);
  return Day(
    spans: List.unmodifiable(merged),
    metres: merged.fold(0.0, (a, s) => a + s.metres),
  );
}

/// Join neighbouring journeys, and drop the empty ones a split leaves behind.
///
/// Without this a drive to work reads as eleven journeys separated by nothing,
/// because every time the car slowed the cluster broke.
List<Span> _merge(List<Span> spans) {
  final out = <Span>[];
  for (final s in spans) {
    if (out.isNotEmpty &&
        s.kind == Part.journey &&
        out.last.kind == Part.journey) {
      final a = out.removeLast();
      final path = [...a.path, ...s.path];
      final c = path.isEmpty ? (a.lat, a.lon) : _centre(path);
      out.add(Span(
        kind: Part.journey,
        from: a.from,
        to: s.to,
        lat: c.$1,
        lon: c.$2,
        metres: _along(path),
        fixes: a.fixes + s.fixes,
        path: List.unmodifiable(path),
      ));
      continue;
    }
    out.add(s);
  }

  // A journey of one fix that goes nowhere is an artefact of the split, not a
  // movement. Keeping it would put "0 m, less than a minute" between two stays.
  return [
    for (final s in out)
      if (!(s.kind == Part.journey && s.metres < 30 && s.fixes <= 2)) s
  ];
}

(double, double) _centre(List<Fix> group) {
  var lat = 0.0, lon = 0.0;
  for (final f in group) {
    lat += f.lat;
    lon += f.lon;
  }
  return (lat / group.length, lon / group.length);
}

double _along(List<Fix> path) {
  var total = 0.0;
  for (var i = 1; i < path.length; i++) {
    total += metresBetween(
        path[i - 1].lat, path[i - 1].lon, path[i].lat, path[i].lon);
  }
  return total;
}

/// Great-circle distance in metres.
///
/// Haversine rather than the flat approximation. Over a kilometre the two agree
/// to within a metre and the flat one is faster — but this is also used to
/// decide whether two places are the SAME place, at the scale of a hundred
/// metres, and at that scale getting the latitude scaling wrong moves a
/// boundary by a street.
double metresBetween(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180.0;

// --------------------------------------------------------------- answering

/// What you were doing at [at], or null if the day does not know.
///
/// The question this module exists for: "where was I on the 14th at three?"
Span? whereAt(Day day, DateTime at) {
  for (final s in day.spans) {
    // Inclusive at both ends. A question asked at exactly the moment a stay
    // began should be answered by that stay, not by a null because the
    // comparison was strict on one side.
    if (!at.isBefore(s.from) && !at.isAfter(s.to)) return s;
  }
  return null;
}

/// The nearest span to [at] when nothing covers it, so the screen can say "you
/// were not being tracked then, but half an hour earlier you were here".
Span? nearestTo(Day day, DateTime at) {
  Span? best;
  var gap = Duration(days: 3650);
  for (final s in day.spans) {
    final d = at.isBefore(s.from)
        ? s.from.difference(at)
        : at.isAfter(s.to)
            ? at.difference(s.to)
            : Duration.zero;
    if (d < gap) {
      gap = d;
      best = s;
    }
  }
  return best;
}
