// Finding a memory again.
//
// The old search was a LIKE on the whole typed phrase, newest first. It failed
// in the way that matters most: you type two words you half-remember and get a
// blank screen, with the thing you want sitting two rows down the thread. Every
// case here is one of those.
import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/memory/find.dart';

Map<String, dynamic> mem(
  int id,
  String body, {
  required DateTime at,
  List<Map<String, dynamic>> facts = const [],
  String? photo,
}) =>
    {
      'id': id,
      'body': body,
      'said_at': at.toIso8601String(),
      'spoken': 0,
      'server_id': null,
      'photo_path': photo,
      'facts': facts,
    };

Map<String, dynamic> fact(String kind, String value, {String? at}) =>
    {'kind': kind, 'value': value, 'at': at};

void main() {
  final now = DateTime(2026, 10, 3, 11);

  final rows = [
    mem(1, 'Bought the washing machine from Vijay Sales for Rs 32,400. '
        'Two year warranty.',
        at: now.subtract(const Duration(days: 2)),
        facts: [
          fact('expiry', 'Warranty ends 3 Oct 2028', at: '2028-10-03'),
          fact('amount', '₹32,400'),
          fact('shop', 'Vijay Sales'),
        ]),
    mem(2, 'Amma says tamarind goes in first, never at the end.',
        at: now.subtract(const Duration(days: 300)),
        facts: [fact('person', 'Amma')]),
    mem(3, 'Got the mixer from Croma, it was on offer.',
        at: now.subtract(const Duration(days: 40)),
        facts: [fact('shop', 'Croma'), fact('amount', '₹4,250')]),
    mem(4, 'Took this at Lalbagh with Appa on the flower show weekend.',
        at: now.subtract(const Duration(days: 120)),
        photo: '/x/memories/m_1.jpg',
        facts: [fact('place', 'Lalbagh'), fact('person', 'Appa')]),
  ];

  List<int> ids(List<Hit> hits) => [for (final h in hits) h.id];

  group('all the words, in any order', () {
    test('two words from different parts of one memory', () {
      // THE CASE THE OLD SEARCH FAILED. A LIKE on "washing croma" matches
      // nothing; a LIKE on "washing" alone is what you had to type instead.
      expect(ids(findMemories('washing vijay', rows, now)), [1]);
    });

    test('order does not matter', () {
      expect(ids(findMemories('vijay washing', rows, now)), [1]);
    });

    test('a word in the tags and a word in the sentence', () {
      // "Croma" is a confirmed tag; "mixer" is only in the words. Both have to
      // count, or searching by what you tagged and what you said is two
      // different searches.
      expect(ids(findMemories('croma mixer', rows, now)), [3]);
    });

    test('a word that matches nothing rules the memory out', () {
      expect(findMemories('washing fridge', rows, now), isEmpty);
    });

    test('a single word still works, and finds every memory with it', () {
      expect(ids(findMemories('from', rows, now)), containsAll([1, 3]));
    });
  });

  group('ranking', () {
    test('the whole phrase beats the same words scattered', () {
      final two = [
        mem(1, 'the blue suitcase is in the loft', at: now),
        mem(2, 'the suitcase we lost was not blue, it was green', at: now),
      ];
      expect(ids(findMemories('blue suitcase', two, now)).first, 1);
    });

    test('a confirmed tag beats a passing mention', () {
      final two = [
        mem(1, 'Croma had a sale on, we did not buy anything.', at: now),
        mem(2, 'Got the kettle there.',
            at: now, facts: [fact('shop', 'Croma')]),
      ];
      expect(ids(findMemories('croma', two, now)).first, 2);
    });

    test('the start of a word beats the middle of one', () {
      final two = [
        mem(1, 'my stomach was off all day', at: now),
        mem(2, 'the machine arrived', at: now),
      ];
      expect(ids(findMemories('mach', two, now)).first, 2);
    });

    test('recency breaks a tie but does not overturn a better match', () {
      // Memory 2 is 300 days old and is still the only one about tamarind.
      expect(ids(findMemories('tamarind', rows, now)), [2]);
    });

    test('a short memory that matches wholly beats a long one that mentions it',
        () {
      final two = [
        mem(1, 'Lalbagh', at: now),
        mem(2, 'A very long account of a weekend that went on and on and '
            'eventually mentioned Lalbagh somewhere near the end of all of it '
            'after a great many other words had gone by',
            at: now),
      ];
      expect(ids(findMemories('lalbagh', two, now)).first, 1);
    });
  });

  group('near enough', () {
    test('one wrong letter still finds it', () {
      // What people actually type on a phone.
      final hits = findMemories('warrenty', rows, now);
      expect(ids(hits), [1]);
      expect(hits.single.fuzzy, isTrue,
          reason: 'the screen has to be able to say it widened the search');
    });

    test('a missing letter, an extra letter, and two swapped', () {
      expect(withinOneEdit('tamarin', 'tamarind'), isTrue);
      expect(withinOneEdit('tamarrind', 'tamarind'), isTrue);
      expect(withinOneEdit('tamarnid', 'tamarind'), isTrue);
      expect(withinOneEdit('marmalade', 'tamarind'), isFalse);
    });

    test('a typo in a tag counts too', () {
      final hits = findMemories('lalbgah', rows, now);
      expect(ids(hits), [4]);
      expect(hits.single.fuzzy, isTrue);
    });

    test('exact matches always come above approximate ones', () {
      // A near miss listed above a real match reads as the search being broken.
      final two = [
        mem(1, 'the crate in the loft', at: now),
        mem(2, 'Croma', at: now, facts: [fact('shop', 'Croma')]),
      ];
      final hits = findMemories('croma', two, now);
      expect(hits.first.id, 2);
      expect(hits.first.fuzzy, isFalse);
    });

    test('short words are never fuzzy, or everything matches everything', () {
      expect(findMemories('cat', rows, now), isEmpty);
    });

    test('typos can be turned off', () {
      expect(findMemories('warrenty', rows, now, allowTypos: false), isEmpty);
    });
  });

  group('saying where it matched', () {
    test('the spans point at the word in the body', () {
      final hit = findMemories('tamarind', rows, now).single;
      final body = '${hit.row['body']}';
      final s = hit.spans.single;
      expect(body.substring(s.start, s.end).toLowerCase(), 'tamarind');
    });

    test('overlapping matches are merged and ordered', () {
      final one = [mem(1, 'the washing machine washing again', at: now)];
      final hit = findMemories('washing wash', one, now).single;
      for (var i = 1; i < hit.spans.length; i++) {
        expect(hit.spans[i].start, greaterThan(hit.spans[i - 1].end - 1));
      }
    });

    test('the tag that matched is named, so the card can lead with it', () {
      final hit = findMemories('vijay', rows, now).single;
      expect(hit.matchedFacts, contains('Vijay Sales'));
    });
  });

  group('narrowing', () {
    test('only what is there is offered', () {
      final offered = narrowsWorthOffering(rows);
      expect(offered, contains(Narrow.money));
      expect(offered, contains(Narrow.photos));
      // Nothing here is... everything here is something, so check the inverse
      // on an emptier set.
      expect(narrowsWorthOffering([mem(9, 'just words', at: now)]),
          [Narrow.all]);
    });

    test('a filter with no words at all lists everything that qualifies', () {
      final hits = findMemories('', rows, now, narrow: Narrow.money);
      expect(ids(hits), [1, 3], reason: 'newest first when nothing was asked');
    });

    test('a filter narrows a search rather than replacing it', () {
      expect(ids(findMemories('from', rows, now, narrow: Narrow.money)),
          containsAll([1, 3]));
      expect(findMemories('tamarind', rows, now, narrow: Narrow.money),
          isEmpty);
    });

    test('photos are a filter, because that is how people look for one', () {
      expect(ids(findMemories('', rows, now, narrow: Narrow.photos)), [4]);
    });
  });

  group('completing as you type', () {
    test('three letters offer the tag spelt the way the memory spells it', () {
      expect(completionsFor('vij', rows), contains('Vijay Sales'));
    });

    test('it completes from a word inside the value, not just the start', () {
      expect(completionsFor('sales', rows), contains('Vijay Sales'));
    });

    test('one letter offers nothing, because everything would match', () {
      expect(completionsFor('v', rows), isEmpty);
    });

    test('what is already typed in full is not offered back', () {
      expect(completionsFor('amma', rows), isNot(contains('Amma')));
    });
  });

  test('an empty search with no filter returns everything, newest first', () {
    expect(ids(findMemories('', rows, now)), [1, 3, 4, 2]);
  });
}
