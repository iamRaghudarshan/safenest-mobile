// Asking your own memory a question.
//
// Every rule in lib/memory/ask.dart is here, because the thing it replaces is a
// language model and the only honest way to ship rules instead is to be able to
// say exactly what they do. When one of these fails, the answer somebody reads
// on their phone has changed.
//
// The cases are written as questions a person would actually type, not as unit
// probes of helper functions — a scorer that passes a hundred synthetic checks
// and then answers "where did I buy the washing machine" with a date is a
// scorer that was tested at the wrong level.
import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/memory/ask.dart';

/// One row shaped as `OfflineStore.memories` returns it.
Map<String, dynamic> mem(
  int id,
  String body, {
  required DateTime at,
  List<Map<String, dynamic>> facts = const [],
}) =>
    {
      'id': id,
      'body': body,
      'said_at': at.toIso8601String(),
      'spoken': 0,
      'server_id': null,
      'facts': facts,
    };

Map<String, dynamic> fact(String kind, String value, {DateTime? at}) =>
    {'kind': kind, 'value': value, 'at': at?.toIso8601String()};

void main() {
  final now = DateTime(2026, 10, 2, 11, 0);
  final lastWeek = now.subtract(const Duration(days: 6));
  final lastYear = now.subtract(const Duration(days: 320));

  // A small life, with enough in it to get the answers wrong.
  final rows = [
    mem(1, 'Bought the washing machine from Vijay Sales for ₹32,400. '
        'Two year warranty.',
        at: lastWeek,
        facts: [
          fact('expiry', 'Warranty ends 26 Sep 2028',
              at: DateTime(2028, 9, 26)),
          fact('amount', '₹32,400'),
          fact('shop', 'Vijay Sales'),
        ]),
    mem(2, 'Amma says tamarind goes in first, never at the end.',
        at: lastYear, facts: [fact('person', 'Amma')]),
    mem(3, 'Took this at Lalbagh with Appa on the flower show weekend.',
        at: lastYear,
        facts: [fact('place', 'Lalbagh'), fact('person', 'Appa')]),
    mem(4, 'Got the mixer from Croma, ₹4,250.',
        at: now.subtract(const Duration(days: 40)),
        facts: [fact('amount', '₹4,250'), fact('shop', 'Croma')]),
  ];

  group('reading what the question wants', () {
    test('the question word decides the kind of answer', () {
      expect(readWondering('where did I buy the washing machine'),
          Wondering.where);
      expect(readWondering('when does the warranty end'), Wondering.when);
      expect(readWondering('how much was the mixer'), Wondering.howMuch);
      expect(readWondering('who told me about tamarind'), Wondering.who);
      expect(readWondering('how many times have I been to Lalbagh'),
          Wondering.howMany);
      expect(readWondering('did I ever buy a fridge'), Wondering.whether);
    });

    test('how much and how many are not confused', () {
      // Both start with the same word, and answering one with the other is the
      // most obviously wrong thing this could do.
      expect(readWondering('how much did I spend'), Wondering.howMuch);
      expect(readWondering('how many did I buy'), Wondering.howMany);
    });

    test('a question with no question word is still answered', () {
      expect(readWondering('washing machine warranty'), Wondering.when,
          reason: 'the word warranty is itself a question about a date');
      expect(readWondering('tamarind'), Wondering.anything);
    });

    test('the words to search for exclude the asking, not just the grammar',
        () {
      // "how many times did I mention Amma" is a question about Amma. Searching
      // for "mention" finds nothing and answers none, which is wrong in the
      // most confident possible way.
      expect(askTerms('how many times did I mention Amma'), ['amma']);
      expect(askTerms('where did I buy the washing machine'),
          ['buy', 'washing', 'machine']);
    });
  });

  group('answering', () {
    test('where names the shop, not the date', () {
      final a = answerFrom('where did I buy the washing machine', rows, now);
      expect(a.said, contains('Vijay Sales'));
      expect(a.sureness, Sureness.certain);
      expect(a.evidence.first.memoryId, 1);
    });

    test('when gives the date and how far off it is', () {
      final a = answerFrom('when does the washing machine warranty end',
          rows, now);
      expect(a.said, contains('26 Sep 2028'));
      expect(a.said, contains('from now'),
          reason: 'a bare date makes somebody count the years themselves');
      expect(a.sureness, Sureness.certain);
    });

    test('a warranty already gone says it has passed', () {
      final gone = [
        mem(9, 'Laptop, one year warranty.',
            at: DateTime(2023, 1, 1),
            facts: [
              fact('expiry', 'Warranty ends 1 Jan 2024', at: DateTime(2024, 1, 1))
            ]),
      ];
      final a = answerFrom('when does the laptop warranty end', gone, now);
      expect(a.said, contains('passed'));
    });

    test('how much gives one price when one thing was asked about', () {
      final a = answerFrom('how much was the mixer', rows, now);
      expect(a.said, contains('₹4,250'));
      expect(a.said, isNot(contains('in all')));
    });

    test('how much in all adds them up, and says what it added', () {
      // The aggregation is the whole point of the question, and showing the
      // parts is what makes the total checkable.
      final a = answerFrom('how much have I spent in all', rows, now);
      expect(a.said, contains('₹36,650'), reason: '32,400 + 4,250');
      expect(a.said, contains('2 things'));
      expect(a.evidence.length, greaterThanOrEqualTo(2));
    });

    test('a lakh is grouped the Indian way', () {
      final big = [
        mem(7, 'Paid ₹12,50,000 for it.',
            at: now, facts: [fact('amount', '₹12,50,000')]),
      ];
      final a = answerFrom('how much did I pay', big, now);
      expect(a.said, contains('₹12,50,000'));
      expect(a.said, isNot(contains('1,250,000')));
    });

    test('who names the person and quotes what they said', () {
      final a = answerFrom('who told me about tamarind', rows, now);
      expect(a.said, contains('Amma'));
      expect(a.said, contains('tamarind'));
    });

    test('how many counts only what genuinely matched', () {
      final a = answerFrom('how many times have I mentioned Amma', rows, now);
      expect(a.said, startsWith('Once'));
      expect(a.sureness, isNot(Sureness.nothing));
    });

    test('a yes-or-no about something never said answers NO', () {
      // The most useful thing this does. An empty screen could mean "no" or
      // "the search is broken"; a sentence cannot.
      final a = answerFrom('did I ever buy a fridge', rows, now);
      expect(a.said, startsWith('No'));
      expect(a.wondering, Wondering.whether);
    });

    test('a yes-or-no that half-matches does not become a yes', () {
      // "buy" matches the washing machine; "fridge" matches nothing. A system
      // that ranks by relevance alone says yes here, and it is wrong.
      final a = answerFrom('did I buy a fridge from Vijay Sales', rows, now);
      expect(a.said, isNot(startsWith('Yes')));
      expect(a.said, contains('Not that I can find'));
    });

    test('a yes-or-no that does match says yes and shows why', () {
      final a = answerFrom('did I buy a washing machine', rows, now);
      expect(a.said, startsWith('Yes'));
      expect(a.said, contains('washing machine'));
    });
  });

  group('knowing when it does not know', () {
    test('nothing at all says so, and names what it looked for', () {
      final a = answerFrom('where is the car insurance policy', rows, now);
      expect(a.found, isFalse);
      expect(a.sureness, Sureness.nothing);
      expect(a.said, contains('insurance'));
      expect(a.evidence, isEmpty);
    });

    test('a match with the wrong kind of fact is admitted, not dressed up',
        () {
      // Lalbagh is mentioned, so something comes back — but nothing in that
      // memory is a price, and the sentence must not imply otherwise.
      final a = answerFrom('how much did Lalbagh cost', rows, now);
      expect(a.sureness, Sureness.unsure);
      expect(a.said, contains('cannot answer that'));
      expect(a.evidence, isNotEmpty,
          reason: 'the words are still worth showing');
    });

    test('evidence comes back even when the sentence is a shrug', () {
      final a = answerFrom('how much did Lalbagh cost', rows, now);
      expect(a.evidence.first.body, contains('Lalbagh'));
    });

    test('an empty question asks for one rather than guessing', () {
      final a = answerFrom('   ', rows, now);
      expect(a.said, contains('Ask it something'));
    });
  });

  group('weighing', () {
    test('a confirmed fact outranks a passing mention', () {
      final mixed = [
        mem(1, 'Croma had a sale on, we did not buy anything.', at: now),
        mem(2, 'Got the kettle from Croma.',
            at: now, facts: [fact('shop', 'Croma')]),
      ];
      final ranked = weigh('where did the kettle come from', mixed, now);
      expect(ranked.first.memoryId, 2);
    });

    test('the first content word weighs most', () {
      // "warranty on the washing machine" is about the washing machine. Both
      // rows carry a warranty; only one is the right thing.
      final two = [
        mem(1, 'Fridge, three year warranty.',
            at: now,
            facts: [
              fact('expiry', 'Warranty ends 2 Oct 2029', at: DateTime(2029, 10, 2))
            ]),
        mem(2, 'Washing machine, two year warranty.',
            at: now,
            facts: [
              fact('expiry', 'Warranty ends 2 Oct 2028', at: DateTime(2028, 10, 2))
            ]),
      ];
      final a = answerFrom('washing machine warranty', two, now);
      expect(a.said, contains('2028'));
    });

    test('recency breaks a tie but does not overturn relevance', () {
      final two = [
        mem(1, 'Bought the mixer from Croma.',
            at: lastYear, facts: [fact('shop', 'Croma')]),
        mem(2, 'Walked past Croma today.', at: now),
      ];
      final ranked = weigh('where did the mixer come from', two, now);
      expect(ranked.first.memoryId, 1,
          reason: 'the newer row does not mention the mixer at all');
    });

    test('coverage is reported, not just a score', () {
      final ranked = weigh('fridge from Vijay Sales', rows, now);
      expect(ranked, isNotEmpty);
      expect(ranked.first.coverage, lessThan(1.0));
    });
  });

  group('suggested questions', () {
    test('they are built from what is actually there', () {
      final qs = suggestedQuestions(rows);
      expect(qs, isNotEmpty);
      // Every suggestion must be answerable, or it teaches somebody the
      // feature is broken.
      for (final q in qs) {
        final a = answerFrom(q, rows, now);
        expect(a.found, isTrue, reason: 'suggested but unanswerable: $q');
      }
    });

    test('an empty life suggests nothing rather than something hollow', () {
      expect(suggestedQuestions(const []), isEmpty);
    });
  });
}
