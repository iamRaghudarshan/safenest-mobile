/// Asking your own memories a question.
///
/// The design brief in one line: it must never be able to sound confident about
/// something it does not know. So every answer arrives with three things and
/// not one — HOW SURE it is, in words rather than a percentage; the SENTENCE;
/// and THE WORDS IT USED, numbered, underneath. The evidence is not an optional
/// detail view behind a tap, because an answer somebody cannot check is one they
/// have to take on trust, and `ask.dart` is a set of rules, not a mind.
///
/// It also says, at the bottom of every answer, that nothing left the phone.
/// That is the honest selling point of answering this way: a model good enough
/// to read the question properly would mean posting a lifetime of private
/// memories to somebody else's computer.
library;

import 'package:flutter/material.dart';

import '../memory/ask.dart';
import 'life_memory_screen.dart' show kMemoryTint, chipColours;

/// How the screen gets at the memories.
///
/// A function rather than the store, for the reason written up in
/// `LifeMemoryScreen.debugRows`: a widget test runs with a fake clock that never
/// delivers real file-IO callbacks, so a screen that opens a database hangs
/// instead of failing. This way the live screen passes
/// `store.memoriesMatchingAny` and a test passes a list.
typedef MemoryLookup = Future<List<Map<String, dynamic>>> Function(
    List<String> terms);

class MemoryAskScreen extends StatefulWidget {
  const MemoryAskScreen({
    super.key,
    required this.look,
    this.debugNow,
    this.debugQuestion,
  });

  final MemoryLookup look;

  /// Fixed clock for tests. "3 weeks ago" is in every answer, so without this
  /// every expectation here would be written against the day it was run.
  final DateTime? debugNow;

  /// Asked as soon as the screen opens.
  ///
  /// For the layout sweep, which draws screens and never types into them. The
  /// empty state here is a text field and a paragraph; the ANSWER is a badge, a
  /// sentence, numbered evidence and a row of chips, and that is where a 320pt
  /// phone overflows. Without this the sweep would pass having drawn none of it.
  final String? debugQuestion;

  @override
  State<MemoryAskScreen> createState() => _MemoryAskScreenState();
}

class _MemoryAskScreenState extends State<MemoryAskScreen> {
  final _q = TextEditingController();
  final _focus = FocusNode();

  Answer? _answer;
  bool _thinking = false;
  List<String> _suggested = const [];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    final preset = widget.debugQuestion;
    if (preset != null) _ask(preset);
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime get _now => widget.debugNow ?? DateTime.now();

  Future<void> _loadSuggestions() async {
    try {
      // No terms means "recent", which is exactly the pool a suggestion should
      // be built from — and every suggestion is therefore answerable, which a
      // fixed list of example questions could never promise.
      final recent = await widget.look(const []);
      if (mounted) setState(() => _suggested = suggestedQuestions(recent));
    } catch (_) {
      // A suggestion that cannot be built is not worth a message. The box
      // works regardless, and that is the feature.
    }
  }

  Future<void> _ask([String? preset]) async {
    final question = (preset ?? _q.text).trim();
    if (question.isEmpty) return;
    if (preset != null) _q.text = preset;
    _focus.unfocus();
    setState(() => _thinking = true);

    try {
      // RETRIEVAL AND SCORING SPLIT ON PURPOSE. The store narrows on the same
      // stems `askTerms` produces, then everything else happens in pure code —
      // so what the answer says can be argued with in a test rather than
      // reproduced on a phone.
      final rows = await widget.look(askTerms(question));
      final a = answerFrom(question, rows, _now);
      if (mounted) {
        setState(() {
          _answer = a;
          _thinking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _thinking = false;
          _answer = Answer(
            said: 'Something went wrong reading your memories. Nothing was '
                'lost — try asking again.',
            sureness: Sureness.nothing,
            evidence: const [],
            wondering: Wondering.anything,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answer = _answer;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kMemoryTint,
        foregroundColor: Colors.white,
        title: const Text('Ask your memories'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          TextField(
            controller: _q,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.search,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'When does the washing machine warranty end?',
              prefixIcon: const Icon(Icons.help_outline),
              suffixIcon: IconButton(
                tooltip: 'Ask',
                icon: const Icon(Icons.arrow_forward),
                onPressed: _ask,
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onSubmitted: (_) => _ask(),
          ),
          if (_thinking) ...[
            const SizedBox(height: 22),
            const Center(child: CircularProgressIndicator()),
          ] else if (answer != null) ...[
            const SizedBox(height: 18),
            _AnswerCard(answer: answer, now: _now),
          ] else ...[
            const SizedBox(height: 20),
            if (_suggested.isEmpty)
              _Primer(theme: theme)
            else ...[
              Text('TRY ONE OF THESE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              // Built from what is actually in there, never a fixed list: a
              // suggestion that returns nothing teaches somebody the whole
              // feature is broken.
              for (final q in _suggested)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Suggestion(question: q, onTap: () => _ask(q)),
                ),
              const SizedBox(height: 14),
              _Primer(theme: theme),
            ],
          ],
        ],
      ),
    );
  }
}

class _Primer extends StatelessWidget {
  const _Primer({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kMemoryTint.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lock_outline, size: 15, color: kMemoryTint),
            const SizedBox(width: 7),
            // Expanded, not bare. A Row gives an unwrapped Text all the width
            // it asks for and then overflows the Row — the stripe people
            // report as "the layout is broken". Caught by the sweep at 320pt,
            // which is the narrowest phone this ships to.
            Expanded(
              child: Text('Answered on this phone',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface)),
            ),
          ]),
          const SizedBox(height: 7),
          // Said plainly rather than implied. It is the reason this answers the
          // way it does, and it is also the limit — see ask.dart.
          Text(
              'It reads your own words and nothing else. No part of what you '
              'have told SafeNest is sent anywhere to answer a question. It '
              'understands where, when, how much, who, how many and '
              'did-I-ever — and it says so when it cannot answer.',
              style: TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: theme.colorScheme.onSurfaceVariant)),
        ]),
      );
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.question, required this.onTap});
  final String question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(children: [
          Expanded(
            child: Text(question,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
          const SizedBox(width: 8),
          Icon(Icons.north_east,
              size: 15, color: theme.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}

// ========================================================= the answer

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer, required this.now});
  final Answer answer;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _tone(answer.sureness);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tone.ink.withValues(alpha: 0.32)),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // HOW SURE, IN WORDS. A percentage would imply a calibration this has
          // none of; "I think" and "I cannot answer that" are honest about the
          // same thing and nobody has to interpret them.
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: tone.back, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                Icon(tone.glyph, size: 12, color: tone.ink),
                const SizedBox(width: 5),
                Text(tone.label,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: tone.ink)),
              ]),
            ),
          ]),
          const SizedBox(height: 11),
          Text(answer.said,
              style: const TextStyle(
                  fontSize: 15.5, height: 1.55, fontWeight: FontWeight.w600)),
        ]),
      ),
      if (answer.evidence.isNotEmpty) ...[
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Text('WHAT THAT CAME FROM',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
          Text('your own words',
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < answer.evidence.length; i++)
          _EvidenceCard(
            n: i + 1,
            cited: answer.evidence[i],
            now: now,
            // The first is the one the sentence was built from. Saying which
            // matters when three memories mention the same thing and only one
            // of them is the answer.
            used: i == 0,
          ),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Icon(Icons.lock_outline,
            size: 13, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Worked out on this phone. Nothing was sent anywhere.',
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ),
      ]),
    ]);
  }

  ({String label, IconData glyph, Color ink, Color back}) _tone(Sureness s) =>
      switch (s) {
        Sureness.certain => (
            label: 'FROM WHAT YOU SAID',
            glyph: Icons.check_circle_outline,
            ink: const Color(0xFF14543A),
            back: const Color(0xFFDCF0E5),
          ),
        Sureness.likely => (
            label: 'MOST LIKELY',
            glyph: Icons.info_outline,
            ink: const Color(0xFF1F4D6B),
            back: const Color(0xFFDEEAF2),
          ),
        Sureness.unsure => (
            label: 'NOT SURE',
            glyph: Icons.help_outline,
            ink: const Color(0xFF7A3D12),
            back: const Color(0xFFFBEBD9),
          ),
        Sureness.nothing => (
            label: 'NOTHING RECORDED',
            glyph: Icons.remove_circle_outline,
            ink: const Color(0xFF5A5A5A),
            back: const Color(0xFFEDEDED),
          ),
      };
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({
    required this.n,
    required this.cited,
    required this.now,
    required this.used,
  });

  final int n;
  final Cited cited;
  final DateTime now;
  final bool used;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
            color: used
                ? kMemoryTint.withValues(alpha: 0.45)
                : theme.colorScheme.outlineVariant),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 21,
          height: 21,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: used
                ? kMemoryTint
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text('$n',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: used ? Colors.white : theme.colorScheme.onSurface)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cited.body,
                style: const TextStyle(fontSize: 13, height: 1.5)),
            if (cited.facts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in cited.facts)
                  _Tag(kind: '${f['kind']}', value: '${f['value']}'),
              ]),
            ],
            const SizedBox(height: 7),
            Text(_said(cited.saidAt, now),
                style: TextStyle(
                    fontSize: 10.5,
                    color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  String _said(DateTime then, DateTime now) {
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(then.year, then.month, then.day))
        .inDays;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final date = '${then.day} ${months[then.month - 1]} ${then.year}';
    if (days == 0) return 'you said this today';
    if (days == 1) return 'you said this yesterday';
    return 'you said this on $date';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.kind, required this.value});
  final String kind;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = chipColours(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: c.back, borderRadius: BorderRadius.circular(12)),
      child: Text(value,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: c.ink)),
    );
  }
}
