/// Reading facts out of something somebody said.
///
/// THIS IS NOT A MODEL AND DOES NOT PRETEND TO BE. It is a set of rules over
/// the words, and it is wrong often enough that the design never lets it act
/// alone: everything here is OFFERED on the confirm screen and kept only when
/// the person taps it. That is what makes a crude reader acceptable — a
/// warranty date it guesses wrongly costs one tap to drop, where a warranty
/// date it files silently is a reminder that fires on the wrong day two years
/// later with nobody able to say why.
///
/// It is pure: no I/O, no clock of its own, `now` is passed in. Every rule
/// below is pinned by a test, because this is the kind of code that rots the
/// moment somebody adds a pattern beside it.
library;

import 'package:flutter/foundation.dart';

/// What kind of thing was heard. The kind decides what the app can DO with it:
/// only [expiry] becomes a reminder, only [place] can be looked up on a map.
enum FactKind { expiry, date, amount, place, shop, person, thing }

@immutable
class Fact {
  const Fact({
    required this.kind,
    required this.value,
    this.at,
    required this.because,
  });

  final FactKind kind;

  /// What to show: "Jayanagar", "Warranty ends 14 Sep 2028".
  final String value;

  /// When the fact points at a moment — an expiry, a date. Null otherwise.
  final DateTime? at;

  /// THE WORDS THIS CAME FROM, kept so the confirm screen can say why it is
  /// suggesting something. "from 'two year warranty'" is the difference
  /// between a suggestion somebody can judge and one they have to trust.
  final String because;

  @override
  bool operator ==(Object other) =>
      other is Fact &&
      other.kind == kind &&
      other.value == value &&
      other.at == at;

  @override
  int get hashCode => Object.hash(kind, value, at);

  @override
  String toString() => '$kind:$value${at == null ? '' : '@$at'}';
}

/// Words that start a sentence or are too common to be a name, so a capital
/// letter on them means nothing.
const _notNames = {
  'i', 'the', 'a', 'an', 'and', 'but', 'it', 'its', 'this', 'that', 'these',
  'those', 'he', 'she', 'they', 'we', 'you', 'my', 'our', 'his', 'her',
  'their', 'bought', 'got', 'took', 'said', 'went', 'there', 'then', 'when',
  'where', 'what', 'who', 'why', 'how', 'if', 'so', 'for', 'from', 'with',
  'at', 'in', 'on', 'to', 'of', 'is', 'was', 'are', 'were', 'has', 'have',
  'had', 'will', 'would', 'can', 'could', 'should', 'no', 'not', 'yes',
  'today', 'tomorrow', 'yesterday', 'monday', 'tuesday', 'wednesday',
  'thursday', 'friday', 'saturday', 'sunday',
};

const _numberWords = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
};

const _months = {
  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
  'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
  'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10,
  'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
};

/// Everything worth offering about [text], said at [now].
///
/// Ordered by how much the app can do with it: an expiry first, because that
/// is the one that becomes a reminder and so the one most worth confirming.
List<Fact> readFacts(String text, DateTime now) {
  final out = <Fact>[];
  final seen = <String>{};

  void add(Fact f) {
    final key = '${f.kind}|${f.value.toLowerCase()}';
    if (seen.add(key)) out.add(f);
  }

  for (final f in _expiries(text, now)) {
    add(f);
  }
  for (final f in _amounts(text)) {
    add(f);
  }
  // WHAT EACH RULE CLAIMS IS REMEMBERED, and every later rule respects it. A
  // capitalised word already offered as "Croma, where it came from" must not
  // come back as a bare name: two suggestions for one word reads as the app
  // being unsure, and the person has to choose between two identical chips.
  //
  // The amounts claim their words too, and that one was found by running it:
  // "for Rs 32,400" offered the price AND a name called "Rs", because Rs is a
  // capitalised word that is not the first in its sentence. Every rule that
  // consumes words has to say so, or the next rule offers them again.
  final claimed = <String>{};
  void claim(Fact f) {
    for (final word in f.because.split(RegExp(r'[^A-Za-z0-9₹]+'))) {
      if (word.isNotEmpty) claimed.add(word.toLowerCase());
    }
  }

  for (final f in out) {
    claim(f);
  }
  for (final f in _placesAndShops(text)) {
    add(f);
    claim(f);
    for (final word in f.value.split(RegExp(r'\s+'))) {
      claimed.add(word.toLowerCase());
    }
  }
  for (final f in _names(text)) {
    if (claimed.contains(f.value.toLowerCase())) continue;
    add(f);
  }
  return out;
}

/// "two year warranty", "warranty for 3 years", "1 year guarantee",
/// "warranty till Sep 2028", "expires on 14 March 2027".
Iterable<Fact> _expiries(String text, DateTime now) sync* {
  final low = text.toLowerCase();

  // An explicit date wins over a duration: somebody who says the date knows it.
  final explicit = RegExp(
      r'(?:warranty|guarantee|expir\w*|valid|renew\w*)[^.]{0,24}?'
      r'(\d{1,2})?\s*([a-z]{3,9})\s+(\d{4})');
  for (final m in explicit.allMatches(low)) {
    final month = _months[m.group(2)!];
    if (month == null) continue;
    final year = int.parse(m.group(3)!);
    final day = int.tryParse(m.group(1) ?? '') ?? 1;
    final when = DateTime(year, month, day);
    yield Fact(
      kind: FactKind.expiry,
      value: 'Warranty ends ${_pretty(when)}',
      at: when,
      because: m.group(0)!.trim(),
    );
  }

  // A duration, in digits or in words, on either side of the word — people
  // say both "two year warranty" and "warranty is two years".
  final nums = _numberWords.keys.join('|');
  final dur = RegExp('(?:(\\d{1,2})|($nums))[\\s-]*'
      '(year|years|yr|yrs|month|months)\\b[^.]{0,20}?'
      '(warranty|guarantee|service|amc)'
      '|(warranty|guarantee|amc)[^.]{0,20}?'
      '(?:(\\d{1,2})|($nums))[\\s-]*'
      '(year|years|yr|yrs|month|months)\\b');
  for (final m in dur.allMatches(low)) {
    final digits = m.group(1) ?? m.group(6);
    final word = m.group(2) ?? m.group(7);
    final unit = m.group(3) ?? m.group(8);
    final n = digits != null
        ? int.tryParse(digits)
        : (word == null ? null : _numberWords[word]);
    if (n == null || unit == null) continue;
    final when = unit.startsWith('month')
        ? DateTime(now.year, now.month + n, now.day)
        : DateTime(now.year + n, now.month, now.day);
    yield Fact(
      kind: FactKind.expiry,
      value: 'Warranty ends ${_pretty(when)}',
      at: when,
      because: m.group(0)!.trim(),
    );
  }
}

/// Rupees, in any of the shapes a person types or a transcriber produces.
Iterable<Fact> _amounts(String text) sync* {
  final re = RegExp(
      r'(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)'
      r'|([\d,]{3,})\s*(?:rupees|rs\b)',
      caseSensitive: false);
  for (final m in re.allMatches(text)) {
    final raw = (m.group(1) ?? m.group(2))!.replaceAll(',', '');
    final n = double.tryParse(raw);
    if (n == null || n < 1) continue;
    yield Fact(
      kind: FactKind.amount,
      value: '₹${_grouped(n)}',
      because: m.group(0)!.trim(),
    );
  }
}

/// "from Vijay Sales", "at Lalbagh", "in Jayanagar".
///
/// `from` means where a thing CAME from and `in`/`at` means where you were —
/// a different kind, because "bought it from Jayanagar" and "took this in
/// Jayanagar" are not the same claim and only one of them is a shop.
Iterable<Fact> _placesAndShops(String text) sync* {
  // A FULL STOP ENDS THE NAME. The dot is allowed inside a word — "St.Marks",
  // "A.M.Road" — only when a letter follows it, so a sentence boundary cannot
  // be swallowed. Without that, "took this in Jayanagar. Two year warranty"
  // offered a place called "Jayanagar. Two", which looked right in the source
  // and absurd on screen.
  const word = r'[A-Z][\w&-]*(?:\.(?=\w)[\w&-]*)*';
  final re = RegExp('\\b(from|at|in|near)\\s+((?:$word)(?:\\s+$word){0,3})');
  for (final m in re.allMatches(text)) {
    final prep = m.group(1)!.toLowerCase();
    final name = m.group(2)!.trim();
    if (_notNames.contains(name.toLowerCase())) continue;
    // "It arrived in March" is a date, not a place. Without this the month
    // becomes somewhere you went, which is the sort of suggestion that makes
    // somebody stop reading the suggestions at all.
    if (_months.containsKey(name.toLowerCase())) continue;
    yield Fact(
      kind: prep == 'from' ? FactKind.shop : FactKind.place,
      value: name,
      because: m.group(0)!.trim(),
    );
  }
}

/// Capitalised words that are not the first word of a sentence.
///
/// Offered as "a name", not split into people and things: telling Amma from
/// Lalbagh needs knowledge this has none of, and guessing wrongly puts a
/// place in your list of people. One honest kind beats two confident ones.
Iterable<Fact> _names(String text) sync* {
  // Sentence starts are excluded by scanning each sentence after its first
  // word, which is where the capital means grammar rather than a name.
  for (final sentence in text.split(RegExp(r'[.!?\n]'))) {
    final words = sentence.trim().split(RegExp(r'\s+'));
    for (var i = 1; i < words.length; i++) {
      // A possessive is the commonest way a name appears — "Amma's recipe",
      // "Appa's bench". Stripping only non-word characters leaves "Amma's",
      // because the s IS a word character, so the apostrophe and what follows
      // it have to go first.
      final w = words[i]
          .replaceAll(RegExp(r"['’]s\b"), '')
          .replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
      if (w.length < 2) continue;
      if (!RegExp(r'^[A-Z][a-z]').hasMatch(w)) continue;
      if (_notNames.contains(w.toLowerCase())) continue;
      if (_months.containsKey(w.toLowerCase())) continue;
      // A word already covered by a place or shop phrase is not offered twice;
      // readFacts dedupes by value, and place wins because it ran first.
      yield Fact(kind: FactKind.person, value: w, because: w);
    }
  }
}

String _pretty(DateTime d) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${names[d.month - 1]} ${d.year}';
}

/// Indian grouping: 45000 -> 45,000 and 1250000 -> 12,50,000. Writing a lakh
/// with Western grouping is the tell that nobody local read the output.
String _grouped(double n) {
  final s = n == n.roundToDouble()
      ? n.round().toString()
      : n.toStringAsFixed(2);
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
