/// Finding a memory again.
///
/// SEARCHING AND ASKING ARE DIFFERENT JOBS and this is the first one. `ask.dart`
/// reads a question and writes a sentence; this takes words you half-remember
/// and puts the right memory at the top. Somebody searching already knows what
/// they are looking for — the failure mode is not a wrong answer, it is a blank
/// screen when the thing is right there.
///
/// Four rules, each of which the plain LIKE query got wrong:
///
///   * ALL THE WORDS, ANYWHERE. "washing croma" has to find a memory with both,
///     in either order, in the words or in a tag. A substring match on the
///     whole phrase finds nothing unless you type it exactly as you said it,
///     which is precisely what you have forgotten.
///   * RANKED, not newest-first. A phrase match beats scattered words, a
///     confirmed tag beats a passing mention, the start of a word beats the
///     middle, and recency only breaks ties.
///   * NEAR ENOUGH COUNTS. "Vijay Sles" and "warrenty" are what people actually
///     type on a phone. One wrong letter is allowed, at a cost, and the screen
///     says it widened the search rather than pretending it was exact.
///   * SAY WHERE IT MATCHED. Every hit carries the spans to highlight, because
///     a list of six memories that all look alike is a list you have to read
///     one by one.
///
/// Pure — no store, no clock of its own. Every rule here is pinned by a test.
library;

import 'package:flutter/foundation.dart';

/// Where a query word landed in a piece of text.
@immutable
class Span {
  const Span(this.start, this.end);
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is Span && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start..$end';
}

/// One memory that matched, and why.
@immutable
class Hit {
  const Hit({
    required this.row,
    required this.score,
    required this.spans,
    required this.matchedFacts,
    required this.fuzzy,
  });

  final Map<String, dynamic> row;
  final double score;

  /// Ranges in `row['body']` to highlight, in order and never overlapping.
  final List<Span> spans;

  /// The confirmed tags that matched, by value — shown first on the card so
  /// the reason a result is here is visible without reading the sentence.
  final Set<String> matchedFacts;

  /// True when at least one word matched only by allowing a typo. The screen
  /// says so: silently widening a search is how people conclude it returns
  /// nonsense.
  final bool fuzzy;

  int get id => row['id'] as int;

  @override
  String toString() => '#${row['id']}(${score.toStringAsFixed(2)})';
}

/// What a memory can be narrowed to. Not a free-text filter — these are the
/// kinds the reader can actually produce, so every chip either has results or
/// is not offered.
enum Narrow { all, dates, money, places, people, photos }

const _kindsFor = {
  Narrow.dates: {'expiry', 'date'},
  Narrow.money: {'amount'},
  Narrow.places: {'place', 'shop'},
  Narrow.people: {'person', 'thing'},
};

/// The words to look for in [query].
///
/// Almost nothing is dropped, unlike `ask.askTerms`. A search is literal: if
/// somebody typed "the blue suitcase" they mean those words, and deciding that
/// "the" is noise is how a search starts quietly disagreeing with the person
/// using it. Only one-character fragments go, because they match everything.
List<String> findTerms(String query) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in query.toLowerCase().split(RegExp(r'[^a-z0-9₹.,]+'))) {
    final w = raw.replaceAll(RegExp(r'^[.,]+|[.,]+$'), '');
    if (w.length < 2) continue;
    if (seen.add(w)) out.add(w);
  }
  return out;
}

/// Rank [rows] for [query]. Best first; non-matching rows are dropped.
///
/// [narrow] filters by what a memory carries rather than by its words, so
/// "everything with a price on it" is one tap and not a query nobody would
/// think to type.
List<Hit> findMemories(
  String query,
  List<Map<String, dynamic>> rows,
  DateTime now, {
  Narrow narrow = Narrow.all,
  bool allowTypos = true,
}) {
  final terms = findTerms(query);
  final phrase = query.trim().toLowerCase();
  final out = <Hit>[];

  for (final row in rows) {
    if (row['id'] is! int) continue;
    if (!_passes(row, narrow)) continue;

    final body = '${row['body'] ?? ''}';
    final low = body.toLowerCase();
    final facts = _factsOf(row);

    // No words typed at all — a bare filter. Everything that passes the filter
    // is a result, ordered by recency, which is the only sensible order when
    // nothing was asked for.
    if (terms.isEmpty) {
      out.add(Hit(
        row: row,
        score: _recency(row, now),
        spans: const [],
        matchedFacts: const {},
        fuzzy: false,
      ));
      continue;
    }

    var score = 0.0;
    var matchedAll = true;
    var usedTypo = false;
    final spans = <Span>[];
    final matchedFacts = <String>{};

    for (final term in terms) {
      final where = _findTerm(low, term);
      final inFacts = _factHit(facts, term);
      if (where.isEmpty && inFacts == null && allowTypos && term.length >= 4) {
        // ONE WRONG LETTER, and only for a word long enough that the allowance
        // cannot turn into "matches anything". Costed, never free.
        final near = _nearMiss(low, term);
        if (near != null) {
          spans.add(near);
          score += 0.6;
          usedTypo = true;
          continue;
        }
        final nearFact = _factNearMiss(facts, term);
        if (nearFact != null) {
          matchedFacts.add(nearFact);
          score += 0.7;
          usedTypo = true;
          continue;
        }
        matchedAll = false;
        break;
      }
      if (where.isEmpty && inFacts == null) {
        matchedAll = false;
        break;
      }
      if (inFacts != null) {
        matchedFacts.add(inFacts);
        // A CONFIRMED TAG BEATS A PASSING MENTION, because somebody tapped it.
        score += 1.8;
      }
      for (final s in where) {
        spans.add(s);
      }
      if (where.isNotEmpty) {
        // The start of a word beats the middle of one: "mach" matching
        // "machine" is what was meant, matching "stomach" is a coincidence.
        score += _atWordStart(low, where.first.start) ? 1.4 : 0.8;
      }
    }

    if (!matchedAll) continue;

    // THE WHOLE PHRASE, IN ORDER, is much stronger evidence than the same words
    // scattered through a paragraph — it means they remembered how they said it.
    if (terms.length > 1 && low.contains(phrase)) score += 2.5;

    // All of a short memory matching beats a few words of a long one. Without
    // this the longest memory wins every search simply by containing more.
    score *= 1.0 + 0.3 * (terms.length / (1 + _words(low) / 25.0)).clamp(0, 1);

    score += _recency(row, now);
    if (usedTypo) score *= 0.55;

    out.add(Hit(
      row: row,
      score: score,
      spans: _tidy(spans),
      matchedFacts: matchedFacts,
      fuzzy: usedTypo,
    ));
  }

  out.sort((a, b) {
    // Exact before approximate, whatever the score. A near miss listed above a
    // real match reads as the search being broken.
    if (a.fuzzy != b.fuzzy) return a.fuzzy ? 1 : -1;
    final c = b.score.compareTo(a.score);
    if (c != 0) return c;
    return '${b.row['said_at']}'.compareTo('${a.row['said_at']}');
  });
  return out;
}

bool _passes(Map<String, dynamic> row, Narrow narrow) {
  if (narrow == Narrow.all) return true;
  if (narrow == Narrow.photos) {
    final p = row['photo_path'];
    return p is String && p.isNotEmpty;
  }
  final want = _kindsFor[narrow]!;
  return _factsOf(row).any((f) => want.contains('${f['kind']}'));
}

/// Recency, as a small addition rather than the ordering. Something said this
/// morning is slightly more likely to be what you are hunting for; something
/// said in 2021 that matches every word is still the answer.
double _recency(Map<String, dynamic> row, DateTime now) {
  final at = DateTime.tryParse('${row['said_at']}');
  if (at == null) return 0;
  final days = now.difference(at).inDays.abs();
  return 0.5 / (1.0 + days / 60.0);
}

int _words(String s) => s.split(RegExp(r'\s+')).length;

/// Every place [term] appears in [low].
List<Span> _findTerm(String low, String term) {
  final out = <Span>[];
  var from = 0;
  while (true) {
    final i = low.indexOf(term, from);
    if (i < 0) break;
    out.add(Span(i, i + term.length));
    from = i + term.length;
    if (out.length >= 8) break;
  }
  return out;
}

bool _atWordStart(String low, int at) =>
    at == 0 || !RegExp(r'[a-z0-9]').hasMatch(low[at - 1]);

String? _factHit(List<Map<String, dynamic>> facts, String term) {
  for (final f in facts) {
    if ('${f['value']}'.toLowerCase().contains(term)) return '${f['value']}';
  }
  return null;
}

/// A word in [low] that is [term] with one letter wrong.
Span? _nearMiss(String low, String term) {
  var at = 0;
  for (final word in low.split(RegExp(r'(?=[^a-z0-9])|(?<=[^a-z0-9])'))) {
    if (word.length >= term.length - 1 &&
        word.length <= term.length + 1 &&
        _withinOne(word, term)) {
      return Span(at, at + word.length);
    }
    at += word.length;
  }
  return null;
}

String? _factNearMiss(List<Map<String, dynamic>> facts, String term) {
  for (final f in facts) {
    for (final word in '${f['value']}'.toLowerCase().split(RegExp(r'\s+'))) {
      if (_withinOne(word, term)) return '${f['value']}';
    }
  }
  return null;
}

/// Edit distance of one or less: one letter wrong, one missing, one extra, or
/// two swapped — which between them are nearly every typo made on a phone.
@visibleForTesting
bool withinOneEdit(String a, String b) => _withinOne(a, b);

bool _withinOne(String a, String b) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1) return false;
  // Find where they first disagree, then ask what single edit would fix it.
  // Counting differences as you go gets transpositions wrong — "tamarnid" for
  // "tamarind" differs in two places, and the check has to be made at the FIRST
  // of them, not the second. That is the bug this shape avoids.
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }

  if (a.length == b.length) {
    // One letter wrong…
    if (a.substring(i + 1) == b.substring(i + 1)) return true;
    // …or two swapped, which is the commonest typo there is.
    return i + 1 < a.length &&
        a[i] == b[i + 1] &&
        a[i + 1] == b[i] &&
        a.substring(i + 2) == b.substring(i + 2);
  }

  // One letter missing or one extra: drop it from the longer and compare.
  final longer = a.length > b.length ? a : b;
  final shorter = a.length > b.length ? b : a;
  return longer.substring(0, i) + longer.substring(i + 1) == shorter;
}

/// Merge overlapping highlights and put them in order, so the screen can walk
/// them straight through without checking for itself.
List<Span> _tidy(List<Span> spans) {
  if (spans.isEmpty) return const [];
  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final out = <Span>[sorted.first];
  for (final s in sorted.skip(1)) {
    final last = out.last;
    if (s.start <= last.end) {
      if (s.end > last.end) out[out.length - 1] = Span(last.start, s.end);
    } else {
      out.add(s);
    }
  }
  return out;
}

List<Map<String, dynamic>> _factsOf(Map<String, dynamic> row) {
  final raw = row['facts'];
  if (raw is! List) return const [];
  return [
    for (final f in raw)
      if (f is Map) {for (final e in f.entries) '${e.key}': e.value}
  ];
}

// --------------------------------------------------------- helping along

/// Completions to offer while somebody types.
///
/// Drawn from the CONFIRMED TAGS first — shops, places, people — because those
/// are the handful of proper nouns a person is most often hunting by, and they
/// are already spelt the way the memory spells them. That is what turns three
/// typed letters into the right answer with no typing at all.
List<String> completionsFor(
  String query,
  List<Map<String, dynamic>> rows, {
  int limit = 6,
}) {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return const [];
  final byValue = <String, int>{};
  for (final row in rows) {
    for (final f in _factsOf(row)) {
      final v = '${f['value']}'.trim();
      if (v.isEmpty) continue;
      final low = v.toLowerCase();
      if (low == q) continue;
      // The start of the value or the start of a word in it — not the middle.
      // A completion that does not begin with what you typed looks like a
      // mistake.
      final starts = low.startsWith(q) ||
          low.split(RegExp(r'\s+')).any((w) => w.startsWith(q));
      if (starts) byValue[v] = (byValue[v] ?? 0) + 1;
    }
  }
  final out = byValue.keys.toList()
    ..sort((a, b) {
      final c = byValue[b]!.compareTo(byValue[a]!);
      return c != 0 ? c : a.length.compareTo(b.length);
    });
  return out.take(limit).toList();
}

/// The filters worth showing, given what is actually stored.
///
/// A chip that returns nothing is a chip that teaches somebody the search is
/// broken, so one is only offered when something would come back.
List<Narrow> narrowsWorthOffering(List<Map<String, dynamic>> rows) {
  final out = <Narrow>[Narrow.all];
  for (final n in Narrow.values) {
    if (n == Narrow.all) continue;
    if (rows.any((r) => _passes(r, n))) out.add(n);
  }
  return out;
}

String narrowLabel(Narrow n) => switch (n) {
      Narrow.all => 'Everything',
      Narrow.dates => 'Dates',
      Narrow.money => 'Money',
      Narrow.places => 'Places & shops',
      Narrow.people => 'People',
      Narrow.photos => 'With a photo',
    };
