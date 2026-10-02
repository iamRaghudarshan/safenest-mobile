/// Asking your own memory a question, and getting a sentence back.
///
/// WHAT THIS IS, SAID PLAINLY. There is no language model here. It reads the
/// question for what KIND of answer is wanted, scores everything you have ever
/// told the app for how well it bears on that, and then writes one sentence
/// from the best of it — and SHOWS THE WORDS IT USED underneath. That last part
/// is not a nicety: a flat sentence with no evidence is indistinguishable from
/// a guess, and this thing guesses often enough that hiding the source would
/// make it untrustworthy rather than merely limited.
///
/// Why not a model. A real one would read the question better than any rules
/// can, and the decision was to ship without one for now: the small ones worth
/// bundling are ~1 GB on a phone, and the good ones mean sending a lifetime of
/// private memories to somebody else's computer, which is the exact opposite of
/// what SafeNest is for. So the honest version is this: narrow, inspectable,
/// and right about the handful of questions people actually ask their own
/// records — where, when, how much, who, how many, did I ever.
///
/// It is PURE. No store, no clock of its own, `now` passed in. Retrieval
/// happens outside and hands the candidate rows in. That is what lets every
/// claim below be pinned by a test rather than discovered on a phone.
library;

import 'package:flutter/foundation.dart';

/// What the question wants back. Getting this right is most of the work: the
/// same memory answers "where did I buy it" with a shop and "how much was it"
/// with a number, and a system that cannot tell the two apart can only ever
/// recite the whole sentence back.
enum Wondering {
  where,
  when,
  howMuch,
  who,
  howMany,
  whether,
  what,

  /// No question word at all — "washing machine warranty". Treated as a search
  /// that gets a sentence, because that is what people type when they are not
  /// in the mood to form a question.
  anything,
}

/// How much the answer deserves to be believed, and the words it is said with.
///
/// Three levels rather than a percentage. A number implies a calibration this
/// has none of, and "92%" would be a lie about a rule-based scorer; "I think"
/// and "the closest I can find" are honest about the same thing.
enum Sureness { certain, likely, unsure, nothing }

@immutable
class Cited {
  const Cited({
    required this.memoryId,
    required this.body,
    required this.saidAt,
    required this.facts,
    required this.score,
    required this.coverage,
  });

  final int memoryId;

  /// The words, verbatim. What makes the answer checkable.
  final String body;
  final DateTime saidAt;

  /// The confirmed facts of that memory: `{kind, value, at}` maps as the store
  /// returns them.
  final List<Map<String, dynamic>> facts;
  final double score;

  /// The share of the question's words this row actually matched, 0..1.
  ///
  /// SCORE AND COVERAGE ARE DIFFERENT QUESTIONS and conflating them is how a
  /// yes-or-no answers yes to something it half-read. Score says "of the rows I
  /// have, this is the most relevant"; coverage says "and it genuinely mentions
  /// what you asked about". A memory about buying a kettle scores top for "did
  /// I ever buy a fridge" simply because nothing else mentions buying — its
  /// coverage is a half, and that is what stops it becoming a yes.
  final double coverage;

  @override
  String toString() => '#$memoryId($score)';
}

@immutable
class Answer {
  const Answer({
    required this.said,
    required this.sureness,
    required this.evidence,
    required this.wondering,
  });

  /// The sentence to show. Always a sentence — never a bare value, because
  /// "Vijay Sales" on its own does not say whether it answered the question or
  /// merely found the word.
  final String said;
  final Sureness sureness;

  /// Best first. The screen numbers these and the sentence refers to them.
  final List<Cited> evidence;
  final Wondering wondering;

  bool get found => sureness != Sureness.nothing;

  @override
  String toString() => said;
}

// ----------------------------------------------------------------- reading

/// Words too common to narrow anything down, plus the question words
/// themselves — "where" is how the question is classified, not a thing to
/// search for.
const _noise = {
  'a', 'an', 'the', 'and', 'or', 'but', 'if', 'then', 'than', 'so', 'is',
  'was', 'are', 'were', 'be', 'been', 'am', 'do', 'does', 'did', 'done',
  'have', 'has', 'had', 'i', 'me', 'my', 'mine', 'we', 'our', 'us', 'you',
  'your', 'it', 'its', 'this', 'that', 'these', 'those', 'he', 'she', 'they',
  'them', 'their', 'his', 'her', 'of', 'to', 'in', 'on', 'at', 'for', 'from',
  'with', 'by', 'about', 'as', 'into', 'over', 'under', 'again', 'ever',
  'any', 'some', 'all', 'what', 'when', 'where', 'who', 'whom', 'whose',
  'which', 'why', 'how', 'much', 'many', 'long', 'tell', 'show', 'find',
  'get', 'know', 'remember', 'said', 'say', 'says', 'there', 'here', 'thing',
  'things', 'anything', 'something', 'please', 'can', 'could', 'would',
  'should', 'will', 'shall', 'may', 'might', 'now', 'up', 'out', 'back',
  // Words that describe the ASKING rather than the thing asked about. Without
  // these, "how many times did I mention Amma" searches for "mention", finds
  // nothing, and answers none — the question is about Amma.
  'mention', 'mentions', 'mentioned', 'times', 'time', 'told', 'talk',
  'talked', 'noted', 'note', 'recorded', 'ago', 'last', 'first', 'most',
  'recent', 'recently', 'everything', 'detail', 'details',
  // Words that CLASSIFY the question rather than narrow it. "how much have I
  // spent in all" has no subject at all — the whole question is the word
  // "spent", and treating it as something to search the words for finds
  // nothing and reports that nothing was ever spent. readWondering reads these
  // off the raw question before this list is applied, so dropping them here
  // loses nothing.
  'cost', 'costs', 'price', 'priced', 'paid', 'pay', 'spent', 'spend',
  'total', 'altogether', 'overall', 'sum', 'worth', 'expensive',
};

/// The words worth looking for in [question].
///
/// Used to narrow the candidate rows BEFORE scoring, which is why it lives
/// here beside the scorer rather than in the store: the two have to agree about
/// what counts as a word, and splitting that across two files is how a search
/// starts quietly missing things.
List<String> askTerms(String question) {
  final out = <String>[];
  for (final raw in question.toLowerCase().split(RegExp(r"[^a-z0-9₹']+"))) {
    final w = raw.replaceAll(RegExp(r"^'+|'+$"), '');
    if (w.length < 2) continue;
    if (_noise.contains(w)) continue;
    // A SHORTENED STEM, not a stemmer. "warranty" and "warranties",
    // "machine" and "machines" have to find each other, and five characters of
    // prefix does that for ordinary English without a dictionary. Anything
    // cleverer here would need a table per language, and this app is used in
    // two.
    out.add(w);
  }
  // Deduplicated but order kept: the first content word of a question is
  // usually its subject, and ties are broken by it below.
  final seen = <String>{};
  return [for (final w in out) if (seen.add(w)) w];
}

/// The stem a term and a candidate word are compared on.
String stemOf(String w) => w.length <= 5 ? w : w.substring(0, 5);

/// What kind of answer [question] is after.
Wondering readWondering(String question) {
  final q = question.toLowerCase();

  // Order matters. "how much" and "how many" both start "how", and "when does
  // the warranty at Croma expire" contains "at" — so the most specific shape
  // is tested first and the loosest last.
  if (RegExp(r'\bhow (?:much|many) (?:times|often)\b').hasMatch(q) ||
      RegExp(r'\bhow many\b').hasMatch(q)) {
    return Wondering.howMany;
  }
  if (RegExp(r'\bhow much\b').hasMatch(q) ||
      RegExp(r'\b(?:cost|price|paid|pay|spent|spend|total)\b').hasMatch(q)) {
    return Wondering.howMuch;
  }
  if (RegExp(r'\bwhen\b').hasMatch(q) ||
      RegExp(r'\b(?:expir\w*|due|renew\w*|warrant\w*|how long)\b')
          .hasMatch(q)) {
    return Wondering.when;
  }
  if (RegExp(r'\bwhere\b').hasMatch(q) ||
      RegExp(r'\b(?:which (?:shop|store|place)|what place)\b').hasMatch(q)) {
    return Wondering.where;
  }
  if (RegExp(r'\bwho(?:m|se)?\b').hasMatch(q)) return Wondering.who;
  // "did I ever", "have I", "is there" — a yes-or-no, and worth its own kind
  // because the answer is NO as often as yes and no other kind can say no.
  if (RegExp(r'^\s*(?:did|do|does|have|has|had|was|were|is|are|am)\b')
      .hasMatch(q)) {
    return Wondering.whether;
  }
  if (RegExp(r'\b(?:what|which|why)\b').hasMatch(q)) return Wondering.what;
  return Wondering.anything;
}

/// The fact kinds that answer each kind of question, best first.
List<String> kindsFor(Wondering w) => switch (w) {
      Wondering.where => const ['shop', 'place'],
      Wondering.when => const ['expiry', 'date'],
      Wondering.howMuch => const ['amount'],
      Wondering.who => const ['person'],
      _ => const [],
    };

// ---------------------------------------------------------------- scoring

/// Score every row for how well it bears on [question], best first.
///
/// Separate from composing the sentence so the screen can show evidence even
/// when no sentence can be written — "I cannot answer that, but here is what
/// mentions it" is a far better reply than silence.
List<Cited> weigh(
  String question,
  List<Map<String, dynamic>> rows,
  DateTime now, {
  Wondering? wondering,
}) {
  final terms = askTerms(question);
  final want = kindsFor(wondering ?? readWondering(question));
  final out = <Cited>[];

  for (final r in rows) {
    final id = r['id'];
    if (id is! int) continue;
    final body = '${r['body'] ?? ''}';
    final facts = _factsOf(r);
    final saidAt = DateTime.tryParse('${r['said_at']}') ?? now;

    final haystack = body.toLowerCase();
    final factWords =
        facts.map((f) => '${f['value']}'.toLowerCase()).join(' ');

    var hits = 0;
    var factHits = 0;
    var weighed = 0.0;
    for (var i = 0; i < terms.length; i++) {
      final stem = stemOf(terms[i]);
      final inBody = haystack.contains(stem);
      final inFacts = factWords.contains(stem);
      if (!inBody && !inFacts) continue;
      hits += 1;
      if (inFacts) factHits += 1;
      // THE FIRST CONTENT WORD COUNTS FOR MORE. "warranty on the washing
      // machine" is a question about the washing machine, and without this the
      // word "warranty" — which appears on every warranty memory there is —
      // weighs as much as the thing being asked about. And a match in a
      // CONFIRMED fact beats one in the words, because somebody tapped it; a
      // word in the body might be an aside.
      weighed += (i == 0 ? 1.6 : 1.0) * (inFacts ? 1.5 : 1.0);
    }
    if (hits == 0 && terms.isNotEmpty) continue;

    var score = weighed;

    // Nothing to search for — a bare "how much have I spent" — so everything
    // is a candidate and the only ordering left is recency and whether the row
    // can answer at all.
    if (terms.isEmpty) score = 0.4;

    // ALL THE WORDS, not some of them. Two of two beats three of six, and
    // without this a long question is answered by whichever memory happens to
    // repeat one of its words most often.
    if (terms.isNotEmpty) score *= 0.5 + 0.5 * (hits / terms.length);

    // Does it carry the kind of fact the question wants? Decisive, not a
    // tiebreak: a memory that mentions the washing machine and has the price
    // confirmed is the answer to "how much", and one that merely mentions it is
    // not.
    if (want.isNotEmpty) {
      final has = facts.any((f) => want.contains('${f['kind']}'));
      score *= has ? 1.9 : 0.75;
      // Among the wanted kinds, the first is the better fit — a shop answers
      // "where did you buy it" more exactly than a place does.
      if (has && facts.any((f) => '${f['kind']}' == want.first)) {
        score *= 1.12;
      }
    }

    // Recency, gently. What you said last week is more likely to be what you
    // meant than what you said in 2021 — but only gently, because the whole
    // point of this module is that old things keep mattering.
    final days = now.difference(saidAt).inDays.abs();
    score *= 1.0 + 0.25 * (1.0 / (1.0 + days / 120.0));

    if (factHits > 0) score *= 1.05;

    out.add(Cited(
      memoryId: id,
      body: body,
      saidAt: saidAt,
      facts: facts,
      score: score,
      coverage: terms.isEmpty ? 1.0 : hits / terms.length,
    ));
  }

  out.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : b.saidAt.compareTo(a.saidAt);
  });
  return out;
}

List<Map<String, dynamic>> _factsOf(Map<String, dynamic> row) {
  final raw = row['facts'];
  if (raw is! List) return const [];
  return [
    for (final f in raw)
      if (f is Map) {
        for (final e in f.entries) '${e.key}': e.value,
      }
  ];
}

// -------------------------------------------------------------- answering

/// The whole of it: read the question, weigh the rows, write the sentence.
Answer answerFrom(
  String question,
  List<Map<String, dynamic>> rows,
  DateTime now,
) {
  final wondering = readWondering(question);
  final ranked = weigh(question, rows, now, wondering: wondering);

  // NOTHING TO GO ON AT ALL. A question with no subject is answerable only when
  // its question word says what to do with everything — "how much in all",
  // "how many" — so a blank box or a sentence of pure filler asks for a real
  // question instead of reciting the most recent memory back, which is what it
  // did before this guard and read like a non sequitur.
  if (askTerms(question).isEmpty &&
      kindsFor(wondering).isEmpty &&
      wondering != Wondering.howMany) {
    return Answer(
      said: _nothingAtAll(''),
      sureness: Sureness.nothing,
      evidence: const [],
      wondering: wondering,
    );
  }

  if (ranked.isEmpty) {
    return Answer(
      said: wondering == Wondering.whether
          // The one kind that can be answered outright by having nothing. "No"
          // is a real answer; "I found nothing" is a shrug.
          ? 'No — nothing you have told me says so.'
          : _nothingAtAll(question),
      sureness: Sureness.nothing,
      evidence: const [],
      wondering: wondering,
    );
  }

  // How many rows the sentence is allowed to draw on. A counting or totalling
  // question needs all of them; everything else is answered by one memory, and
  // showing five is how an answer turns into a search result.
  final broad = wondering == Wondering.howMany || _isTotalling(question);
  final top = ranked.first;
  final used = broad
      ? ranked.where((c) => c.score >= ranked.first.score * 0.45).toList()
      : [top];

  final sureness = _howSure(ranked, wondering, broad: broad);

  final said = switch (wondering) {
    Wondering.howMany => _sayCount(ranked, question, now),
    Wondering.howMuch => _sayMoney(used, now, broad: broad),
    Wondering.when => _sayWhen(top, now),
    Wondering.where => _sayWhere(top, now),
    Wondering.who => _sayWho(top, now),
    Wondering.whether => _sayWhether(ranked, top, now),
    Wondering.what || Wondering.anything => _sayWords(top, now, sureness),
  };

  return Answer(
    said: said,
    sureness: sureness,
    // At most four, and the first is the one the sentence is built from. More
    // than four stops being evidence and becomes a list to read.
    evidence: broad
        ? used.take(4).toList()
        : ranked.take(ranked.length >= 3 ? 3 : ranked.length).toList(),
    wondering: wondering,
  );
}

bool _isTotalling(String q) => RegExp(
        r'\b(?:total|altogether|in all|overall|sum|how much have|how much did i spend)\b')
    .hasMatch(q.toLowerCase());

Sureness _howSure(List<Cited> ranked, Wondering w, {required bool broad}) {
  final top = ranked.first;
  if (top.score < 0.35) return Sureness.unsure;
  // Half the question unanswered is not an answer, however well it scored
  // against everything else. See Cited.coverage.
  if (top.coverage < 0.5) return Sureness.unsure;

  // DOES THE TOP ROW ACTUALLY CARRY THE ANSWER? This is the difference between
  // "it says Vijay Sales" and "it mentions the washing machine, so here are the
  // words". Without this check the sentence sounds equally confident either way,
  // which is the single worst thing a thing like this can do.
  final want = kindsFor(w);
  if (want.isNotEmpty) {
    final has = top.facts.any((f) => want.contains('${f['kind']}'));
    if (!has) return Sureness.unsure;
  }

  if (broad) return ranked.length > 1 ? Sureness.likely : Sureness.certain;

  // A clear winner reads as an answer; two rows neck and neck mean the question
  // picked out more than one thing and the sentence is a choice, not a fact.
  final runnerUp = ranked.length > 1 ? ranked[1].score : 0.0;
  if (runnerUp < top.score * 0.6) return Sureness.certain;
  return Sureness.likely;
}

String _nothingAtAll(String question) {
  final terms = askTerms(question);
  if (terms.isEmpty) {
    return 'Ask it something — where something came from, when a warranty '
        'ends, how much something cost, what somebody told you.';
  }
  return 'You have not told me anything about '
      '${_list(terms.take(3).toList())} yet. Say it once and it will be here '
      'the next time you ask.';
}

String _sayWhere(Cited c, DateTime now) {
  final shop = _firstFact(c, 'shop');
  final place = _firstFact(c, 'place');
  final what = shop ?? place;
  if (what == null) return _sayWords(c, now, Sureness.unsure);
  final verb = shop != null ? 'came from' : 'was';
  return 'It $verb ${what['value']}${shop != null ? '' : ' there'} — '
      'you said so ${_ago(c.saidAt, now)}.';
}

String _sayWhen(Cited c, DateTime now) {
  final f = _firstFact(c, 'expiry') ?? _firstFact(c, 'date');
  final at = f == null ? null : DateTime.tryParse('${f['at']}');
  if (f == null || at == null) return _sayWords(c, now, Sureness.unsure);

  final away = at.difference(now);
  final tail = away.isNegative
      ? 'which was ${_ago(at, now)} — it has passed'
      : 'which is ${_inWords(away)} from now';
  // The value already reads as a sentence fragment ("Warranty ends 14 Sep
  // 2028"), so it is used as written rather than rebuilt — the person saw and
  // tapped those exact words.
  return '${f['value']}, $tail.';
}

String _sayMoney(List<Cited> used, DateTime now, {required bool broad}) {
  final amounts = <({double value, Cited from})>[];
  for (final c in used) {
    for (final f in c.facts) {
      if ('${f['kind']}' != 'amount') continue;
      final n = _rupees('${f['value']}');
      if (n != null) amounts.add((value: n, from: c));
    }
  }
  if (amounts.isEmpty) {
    return _sayWords(used.first, now, Sureness.unsure);
  }
  if (!broad || amounts.length == 1) {
    final one = amounts.first;
    return '₹${_grouped(one.value)} — ${_ago(one.from.saidAt, now)}.';
  }
  final total = amounts.fold<double>(0, (a, b) => a + b.value);
  // SAID AS A SUM OF PARTS, not as a bare total. A total is only as right as
  // the rows it came from, and somebody who can see it is four memories can
  // tell at a glance whether a fifth is missing.
  return '₹${_grouped(total)} in all, across ${amounts.length} things you '
      'noted${amounts.length > 4 ? '' : ' — ${_list([
          for (final a in amounts) '₹${_grouped(a.value)}'
        ])}'}.';
}

String _sayWho(Cited c, DateTime now) {
  final people = [
    for (final f in c.facts)
      if ('${f['kind']}' == 'person') '${f['value']}'
  ];
  if (people.isEmpty) return _sayWords(c, now, Sureness.unsure);
  return '${_list(people)} — ${_ago(c.saidAt, now)} you said '
      '“${_short(c.body)}”.';
}

String _sayCount(List<Cited> ranked, String question, DateTime now) {
  // Only rows that genuinely matched are counted, so "how many times did I
  // mention Amma" cannot be inflated by whatever happened to rank third.
  final real =
      ranked.where((c) => c.score >= 0.3 && c.coverage >= 0.6).toList();
  final n = real.length;
  if (n == 0) return 'None that you have told me about.';
  final terms = askTerms(question);
  final about = terms.isEmpty ? '' : ' about ${_list(terms.take(2).toList())}';
  if (n == 1) {
    return 'Once$about — ${_ago(real.first.saidAt, now)}.';
  }
  return '$n times$about, the most recent ${_ago(real.first.saidAt, now)}.';
}

String _sayWhether(List<Cited> ranked, Cited top, DateTime now) {
  // A yes-or-no is the one kind that can be answered NO, and saying no is the
  // most useful thing this ever does: it is the difference between "I have no
  // record of that" and a silent empty screen that could mean either.
  if (top.score < 0.4 || top.coverage < 0.6) {
    return 'Not that I can find — nothing you have told me says so. The '
        'nearest is “${_short(top.body)}”, ${_ago(top.saidAt, now)}.';
  }
  return 'Yes — ${_ago(top.saidAt, now)} you said “${_short(top.body)}”.';
}

String _sayWords(Cited c, DateTime now, Sureness s) {
  final lead = s == Sureness.certain
      ? 'You said'
      : s == Sureness.likely
          ? 'The nearest thing you said'
          : 'I cannot answer that from what you have told me. The closest is';
  return '$lead, ${_ago(c.saidAt, now)}: “${_short(c.body)}”.';
}

Map<String, dynamic>? _firstFact(Cited c, String kind) {
  for (final f in c.facts) {
    if ('${f['kind']}' == kind) return f;
  }
  return null;
}

String _short(String body) =>
    body.length <= 140 ? body : '${body.substring(0, 137)}…';

/// "₹12,50,000" back to a number.
double? _rupees(String value) {
  final m = RegExp(r'([\d,]+(?:\.\d{1,2})?)').firstMatch(value);
  if (m == null) return null;
  return double.tryParse(m.group(1)!.replaceAll(',', ''));
}

/// Indian grouping — the same rule facts.dart writes with, because an answer
/// that groups a lakh differently from the chip above it looks like two
/// different apps.
String _grouped(double n) {
  final s = n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);
  final dot = s.indexOf('.');
  var whole = dot < 0 ? s : s.substring(0, dot);
  final rest = dot < 0 ? '' : s.substring(dot);
  if (whole.length <= 3) return '$whole$rest';
  final last3 = whole.substring(whole.length - 3);
  var head = whole.substring(0, whole.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) parts.insert(0, head);
  return '${parts.join(',')},$last3$rest';
}

/// "yesterday", "three weeks ago", "in March 2023".
String _ago(DateTime then, DateTime now) {
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(then.year, then.month, then.day))
      .inDays;
  if (days < 0) return 'on ${_pretty(then)}';
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'last week';
  if (days < 60) return '${(days / 7).round()} weeks ago';
  if (days < 365) return '${(days / 30).round()} months ago';
  final years = days / 365;
  if (years < 1.6) return 'about a year ago';
  return 'in ${then.year}';
}

/// How far ahead something is, for a warranty that has not expired yet.
String _inWords(Duration away) {
  final days = away.inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'a day';
  if (days < 14) return '$days days';
  if (days < 60) return '${(days / 7).round()} weeks';
  if (days < 365) return '${(days / 30).round()} months';
  final years = days / 365;
  return years < 1.6
      ? 'about a year'
      : '${years.round()} years';
}

String _pretty(DateTime d) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${names[d.month - 1]} ${d.year}';
}

/// "a", "a and b", "a, b and c" — the Oxford comma left out because nobody
/// speaks with one.
String _list(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

/// Questions worth offering on an empty Ask screen.
///
/// Built from what the person has actually told it, never from a fixed list: a
/// suggestion that returns nothing teaches somebody the feature is broken.
List<String> suggestedQuestions(List<Map<String, dynamic>> rows) {
  final out = <String>[];
  String? shop, thing, person;
  var hasExpiry = false, hasAmount = false;

  for (final r in rows) {
    for (final f in _factsOf(r)) {
      switch ('${f['kind']}') {
        case 'expiry':
          hasExpiry = true;
          thing ??= _subjectOf('${r['body']}');
        case 'amount':
          hasAmount = true;
          thing ??= _subjectOf('${r['body']}');
        case 'shop':
          shop ??= '${f['value']}';
        case 'person':
          person ??= '${f['value']}';
      }
    }
  }

  if (hasExpiry) {
    out.add('When does the ${thing ?? 'warranty'} warranty end?');
  }
  if (hasAmount) out.add('How much did I spend in all?');
  if (shop != null) out.add('What did I buy from $shop?');
  if (person != null) out.add('What did $person tell me?');
  if (out.isEmpty && rows.isNotEmpty) {
    out.add('What did I say most recently?');
  }
  return out.take(4).toList();
}

/// A rough noun phrase for a memory — used only to make a suggested question
/// read naturally, so being wrong costs a slightly odd suggestion and nothing
/// more.
String? _subjectOf(String body) {
  final words = body.toLowerCase().split(RegExp(r'[^a-z]+'));
  for (var i = 0; i < words.length - 1; i++) {
    if (words[i].length >= 4 &&
        !_noise.contains(words[i]) &&
        words[i + 1].length >= 4 &&
        !_noise.contains(words[i + 1])) {
      return '${words[i]} ${words[i + 1]}';
    }
  }
  for (final w in words) {
    if (w.length >= 5 && !_noise.contains(w)) return w;
  }
  return null;
}
