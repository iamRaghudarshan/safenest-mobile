/// Finding a memory again.
///
/// The old version was a sheet with a text field: every keystroke ran a SQL
/// LIKE on the whole phrase, and the results were whatever matched, newest
/// first. It failed at the only thing a search has to do — you type two words
/// you half-remember and get a blank screen while the memory sits two rows down
/// the thread.
///
/// What this screen does instead, and each of them is a decision:
///
///   * IT WAITS FOR YOU TO STOP TYPING. 180ms. A query per character is four
///     queries for "croma", three of them thrown away, and on a long thread the
///     list flickers through four different answers while you type.
///   * IT SHOWS WHERE IT MATCHED, highlighted, and leads each card with the tag
///     that matched. Six results that all look alike is a list you have to read
///     one at a time.
///   * IT OFFERS THE SPELLING. Three letters of "Vij" offers "Vijay Sales",
///     taken from the tags, which is where the proper nouns already live spelt
///     correctly.
///   * IT FILTERS BY WHAT A MEMORY CARRIES — dates, money, places, people, a
///     photo — because "the one with the picture" is how people actually hunt,
///     and no amount of typing expresses it.
///   * IT SAYS WHEN IT WIDENED THE SEARCH. A typo match is shown under its own
///     heading, never mixed in: silently returning near misses is how somebody
///     decides the search returns nonsense.
///   * AND IT OFFERS TO ASK INSTEAD. "when does the warranty end" typed into a
///     search box is a question, and the answer screen is one tap away rather
///     than somewhere else in the app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../memory/ask.dart' show askTerms;
import '../memory/find.dart';
import 'life_memory_screen.dart' show kMemoryTint, chipColours;

/// How the screen reaches the memories. See `MemoryAskScreen.look` for why this
/// is a function and not the store.
typedef MemoryLookup = Future<List<Map<String, dynamic>>> Function(
    List<String> terms);

/// Long enough that a fast typist runs one query, short enough that it feels
/// instant. Measured from the two extremes being obviously wrong: no debounce
/// flickers, half a second feels broken.
const _settle = Duration(milliseconds: 180);

const _recentKey = 'memory.recentSearches';
const _recentMax = 6;

class MemorySearchScreen extends StatefulWidget {
  const MemorySearchScreen({
    super.key,
    required this.look,
    this.onAsk,
    this.debugNow,
    this.debugRecent,
  });

  final MemoryLookup look;

  /// Opens the Ask screen with the same words. Null hides the offer.
  final void Function(String question)? onAsk;

  final DateTime? debugNow;

  /// Recent searches for tests, instead of reading SharedPreferences — which a
  /// widget test's fake clock makes awkward and which has nothing to do with
  /// what these tests check.
  final List<String>? debugRecent;

  @override
  State<MemorySearchScreen> createState() => _MemorySearchScreenState();
}

class _MemorySearchScreenState extends State<MemorySearchScreen> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  /// Everything the screen has fetched for the current words. Filtering and
  /// ranking happen here, not in SQL, so changing a chip is instant and does
  /// not go back to the disk.
  List<Map<String, dynamic>> _pool = const [];

  /// A bounded sample of the whole thread, fetched once when the screen opens.
  ///
  /// IT DOES TWO JOBS, both of which the first cut got wrong by not having it.
  ///
  /// The filter chips are built from this, not from the current results — built
  /// from the results, "Money" disappeared the moment you typed a word that
  /// matched nothing with a price on it, so the filters rearranged themselves
  /// under your thumb as you typed.
  ///
  /// And it is what a typo is matched against. The store narrows with a LIKE on
  /// each word, so a misspelt word fetches nothing at all and there is nothing
  /// left to be approximately right about — the allowance for one wrong letter
  /// would have been dead code on a real database. When the narrow lookup comes
  /// back empty, the search is retried over this instead.
  List<Map<String, dynamic>> _all = const [];
  List<Hit> _hits = const [];
  List<String> _completions = const [];
  List<Narrow> _offered = const [Narrow.all];
  List<String> _recent = const [];

  Narrow _narrow = Narrow.all;
  bool _busy = false;
  bool _searched = false;

  DateTime get _now => widget.debugNow ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _recent = widget.debugRecent ?? const [];
    if (widget.debugRecent == null) _loadRecent();
    _loadAll();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recent = saved);
    } catch (_) {
      // A missing preference is not worth a message. The search works either
      // way, which is the point of it being a convenience.
    }
  }

  Future<void> _remember(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    final next = [q, ..._recent.where((r) => r.toLowerCase() != q.toLowerCase())]
        .take(_recentMax)
        .toList();
    setState(() => _recent = next);
    if (widget.debugRecent != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, next);
    } catch (_) {/* see _loadRecent */}
  }

  Future<void> _loadAll() async {
    try {
      final all = await widget.look(const []);
      if (!mounted) return;
      setState(() {
        _all = all;
        _pool = all;
        _offered = narrowsWorthOffering(all);
        _hits = findMemories('', all, _now, narrow: _narrow);
      });
    } catch (_) {
      if (mounted) setState(() => _all = const []);
    }
  }

  void _typed(String value) {
    _debounce?.cancel();
    _debounce = Timer(_settle, () => _run(value));
    // The completions are computed from what is already in hand, so they can
    // keep up with every keystroke without touching the disk.
    setState(() => _completions = completionsFor(value, _pool));
  }

  Future<void> _run(String query) async {
    setState(() => _busy = true);
    try {
      // THE NET IS CAST WIDER THAN THE MATCH. The store is asked for anything
      // containing ANY of the words; `findMemories` then requires all of them.
      // Narrowing in SQL instead would mean a typo could never be caught,
      // because the row with the misspelt word would never be fetched.
      final pool = await widget.look(findTerms(query));
      if (!mounted) return;
      var hits = findMemories(query, pool, _now, narrow: _narrow);

      // NOTHING CAME BACK, so try again over the whole thread. The store's
      // lookup is a LIKE per word, which a misspelling matches nothing at all —
      // so without this the allowance for one wrong letter could never fire on
      // a real database however well it was tested in isolation.
      if (hits.isEmpty && query.trim().isNotEmpty && _all.isNotEmpty) {
        hits = findMemories(query, _all, _now, narrow: _narrow);
      }

      setState(() {
        _pool = pool.isEmpty ? _all : pool;
        _hits = hits;
        // The chips come from the whole thread, never from the results: built
        // from the results they rearrange themselves under your thumb as you
        // type.
        _offered = narrowsWorthOffering(_all.isEmpty ? pool : _all);
        if (!_offered.contains(_narrow)) _narrow = Narrow.all;
        _completions = completionsFor(query, _all.isEmpty ? pool : _all);
        _busy = false;
        _searched = query.trim().isNotEmpty || _narrow != Narrow.all;
      });
      if (query.trim().isNotEmpty && _hits.isNotEmpty) _remember(query);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _hits = const [];
        });
      }
    }
  }

  void _refilter(Narrow n) {
    setState(() {
      _narrow = n;
      _hits = findMemories(_q.text, _pool, _now, narrow: n);
      _searched = _q.text.trim().isNotEmpty || n != Narrow.all;
    });
  }

  void _use(String text) {
    _q.text = text;
    _q.selection = TextSelection.collapsed(offset: text.length);
    _focus.unfocus();
    _debounce?.cancel();
    _run(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exact = [for (final h in _hits) if (!h.fuzzy) h];
    final near = [for (final h in _hits) if (h.fuzzy) h];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kMemoryTint,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: TextField(
          controller: _q,
          focusNode: _focus,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 16.5),
          cursorColor: Colors.white,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Anything you have told it',
            hintStyle: TextStyle(color: Colors.white70, fontSize: 16),
            border: InputBorder.none,
          ),
          onChanged: _typed,
          onSubmitted: (v) {
            _debounce?.cancel();
            _run(v);
          },
        ),
        actions: [
          if (_q.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () {
                _q.clear();
                _use('');
              },
            ),
        ],
      ),
      body: Column(children: [
        if (_offered.length > 1) _Chips(
          offered: _offered,
          chosen: _narrow,
          onPick: _refilter,
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            children: [
              // Completions first, because tapping one is faster than finishing
              // the word — and it spells the name the way the memory spells it.
              if (_completions.isNotEmpty && _q.text.trim().isNotEmpty) ...[
                for (final c in _completions)
                  _Completion(value: c, onTap: () => _use(c)),
                const SizedBox(height: 10),
              ],

              if (!_searched && _recent.isNotEmpty) ...[
                _Heading(text: 'RECENT', theme: theme),
                for (final r in _recent)
                  _Recent(text: r, onTap: () => _use(r)),
                const SizedBox(height: 14),
              ],

              if (_searched) ...[
                _Count(
                  n: exact.length,
                  narrow: _narrow,
                  theme: theme,
                ),
                const SizedBox(height: 8),
              ],

              for (final h in exact) _Result(hit: h, now: _now),

              if (near.isNotEmpty) ...[
                const SizedBox(height: 6),
                // UNDER ITS OWN HEADING, never mixed in. Silently returning near
                // misses is how somebody decides the search returns nonsense.
                _Heading(
                    text: exact.isEmpty
                        ? 'NOTHING EXACT — DID YOU MEAN'
                        : 'CLOSE, BUT NOT EXACT',
                    theme: theme),
                for (final h in near) _Result(hit: h, now: _now),
              ],

              if (_searched && _hits.isEmpty && !_busy)
                _Nothing(
                  query: _q.text,
                  narrow: _narrow,
                  theme: theme,
                  onAsk: widget.onAsk,
                ),

              if (_searched && _hits.isNotEmpty && widget.onAsk != null &&
                  _looksLikeAQuestion(_q.text)) ...[
                const SizedBox(height: 10),
                _AskInstead(
                  question: _q.text,
                  onTap: () => widget.onAsk!(_q.text),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

/// Worth offering the Ask screen for.
///
/// A question mark, or a question word at the front. Deliberately narrow: an
/// offer that appears under every search is an offer nobody reads.
bool _looksLikeAQuestion(String s) {
  final q = s.trim().toLowerCase();
  if (q.contains('?')) return true;
  return RegExp(r'^(when|where|who|what|which|why|how|did|do|does|have|has|is|was)\b')
      .hasMatch(q);
}

// ================================================================ pieces

class _Chips extends StatelessWidget {
  const _Chips({
    required this.offered,
    required this.chosen,
    required this.onPick,
  });

  final List<Narrow> offered;
  final Narrow chosen;
  final void Function(Narrow) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        children: [
          for (final n in offered)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: InkWell(
                onTap: () => onPick(n),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: n == chosen
                        ? kMemoryTint
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(narrowLabel(n),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: n == chosen
                              ? Colors.white
                              : theme.colorScheme.onSurface)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text, required this.theme});
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: theme.colorScheme.onSurfaceVariant)),
      );
}

class _Count extends StatelessWidget {
  const _Count({required this.n, required this.narrow, required this.theme});
  final int n;
  final Narrow narrow;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final what = narrow == Narrow.all
        ? ''
        : ' in ${narrowLabel(narrow).toLowerCase()}';
    return Text(
        n == 0
            ? 'Nothing$what'
            : n == 1
                ? '1 memory$what'
                : '$n memories$what',
        style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant));
  }
}

class _Completion extends StatelessWidget {
  const _Completion({required this.value, required this.onTap});
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(children: [
          Icon(Icons.north_west,
              size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Icon(Icons.history,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ]),
      ),
    );
  }
}

/// One result, with the matched words lit up.
class _Result extends StatelessWidget {
  const _Result({required this.hit, required this.now});
  final Hit hit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = '${hit.row['body']}';
    final facts = (hit.row['facts'] as List?) ?? const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
          _lit(body, hit.spans, theme),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(spacing: 6, runSpacing: 6, children: [
            // THE TAG THAT MATCHED COMES FIRST and is outlined, so the reason
            // this result is here is visible without reading the sentence.
            for (final f in _ordered(facts, hit.matchedFacts))
              _Tag(
                kind: '${f['kind']}',
                value: '${f['value']}',
                matched: hit.matchedFacts.contains('${f['value']}'),
              ),
          ]),
        ],
        const SizedBox(height: 8),
        Text(_when(hit.row['said_at'] as String?, now),
            style: TextStyle(
                fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }

  List<Map> _ordered(List facts, Set<String> matched) {
    final hit = <Map>[];
    final rest = <Map>[];
    for (final f in facts) {
      if (f is! Map) continue;
      (matched.contains('${f['value']}') ? hit : rest).add(f);
    }
    return [...hit, ...rest];
  }

  /// The body with every matched span highlighted.
  TextSpan _lit(String body, List<Span> spans, ThemeData theme) {
    const base = TextStyle(fontSize: 13.5, height: 1.5);
    if (spans.isEmpty) return TextSpan(text: body, style: base);
    final parts = <TextSpan>[];
    var at = 0;
    for (final s in spans) {
      // Guarded against a span that ran past the end: the spans come from the
      // lowercased body, and a locale where lowercasing changes a string's
      // LENGTH would otherwise crash the whole list rather than mis-highlight
      // one word.
      if (s.start < at || s.end > body.length) continue;
      if (s.start > at) {
        parts.add(TextSpan(text: body.substring(at, s.start), style: base));
      }
      parts.add(TextSpan(
        text: body.substring(s.start, s.end),
        style: base.copyWith(
          fontWeight: FontWeight.w800,
          backgroundColor: kMemoryTint.withValues(alpha: 0.16),
        ),
      ));
      at = s.end;
    }
    if (at < body.length) {
      parts.add(TextSpan(text: body.substring(at), style: base));
    }
    return TextSpan(children: parts);
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.kind, required this.value, required this.matched});
  final String kind;
  final String value;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final c = chipColours(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.back,
        borderRadius: BorderRadius.circular(13),
        border: matched ? Border.all(color: c.ink, width: 1.4) : null,
      ),
      child: Text(value,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: c.ink)),
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing({
    required this.query,
    required this.narrow,
    required this.theme,
    required this.onAsk,
  });

  final String query;
  final Narrow narrow;
  final ThemeData theme;
  final void Function(String)? onAsk;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 26, 10, 10),
        child: Column(children: [
          Icon(Icons.search_off,
              size: 30, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
              narrow == Narrow.all
                  ? 'Nothing you have told it matches that.'
                  : 'Nothing in ${narrowLabel(narrow).toLowerCase()} matches '
                      'that — try Everything.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, height: 1.5)),
          const SizedBox(height: 6),
          Text('It looks in your own words as well as the tags, and it allows '
              'for a wrong letter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: theme.colorScheme.onSurfaceVariant)),
          if (onAsk != null && query.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _AskInstead(question: query, onTap: () => onAsk!(query)),
          ],
        ]),
      );
}

class _AskInstead extends StatelessWidget {
  const _AskInstead({required this.question, required this.onTap});
  final String question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            color: kMemoryTint.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(children: [
            const Icon(Icons.auto_awesome_outlined,
                size: 17, color: kMemoryTint),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Ask it instead, and get an answer',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kMemoryTint)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: kMemoryTint),
          ]),
        ),
      );
}

String _when(String? iso, DateTime now) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month - 1]}'
      '${d.year == now.year ? '' : ' ${d.year}'}';
}

/// The words a typed question should be handed to the Ask screen as.
///
/// Exported so the caller does not have to know; it is `ask.askTerms` that
/// decides what a question is about, and the search box and the answer screen
/// disagreeing about that is exactly the seam where things rot.
List<String> questionTerms(String s) => askTerms(s);
