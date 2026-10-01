// Reading facts out of something somebody said.
//
// These rules decide what Life Memory offers you on the confirm screen, and
// one of them — the expiry — becomes a reminder that fires years later. A
// wrong date here is a notification nobody can explain in 2028, so every shape
// is pinned.
//
// The whole design rests on these being OFFERED rather than applied, which is
// why a crude reader is acceptable: the tests below are as interested in what
// it must NOT claim as in what it finds.
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/memory/facts.dart';

void main() {
  final now = DateTime(2026, 9, 14);

  List<Fact> of(String text) => readFacts(text, now);
  List<Fact> kind(String text, FactKind k) =>
      of(text).where((f) => f.kind == k).toList();

  group('a warranty, said as a length of time', () {
    test('in words, which is how people say it out loud', () {
      final f = kind('Bought the washing machine, two year warranty.',
          FactKind.expiry);
      expect(f, hasLength(1));
      expect(f.single.at, DateTime(2028, 9, 14));
      expect(f.single.value, 'Warranty ends 14 Sep 2028');
    });

    test('in digits', () {
      expect(kind('3 year warranty on the fridge', FactKind.expiry).single.at,
          DateTime(2029, 9, 14));
    });

    test('with the word first, which is just as natural', () {
      expect(kind('warranty is 2 years', FactKind.expiry).single.at,
          DateTime(2028, 9, 14));
    });

    test('in months', () {
      expect(kind('6 month warranty', FactKind.expiry).single.at,
          DateTime(2027, 3, 14));
    });

    test('and it says which words it came from', () {
      // The confirm screen shows this. A suggestion somebody cannot judge is
      // one they have to trust, and trusting it is what this design avoids.
      expect(kind('two year warranty', FactKind.expiry).single.because,
          contains('two year'));
    });
  });

  group('a warranty, said as a date', () {
    test('a full date', () {
      expect(
          kind('warranty expires 14 March 2029', FactKind.expiry).single.at,
          DateTime(2029, 3, 14));
    });

    test('a month and a year, which lands on the first', () {
      expect(kind('warranty till Sep 2028', FactKind.expiry).single.at,
          DateTime(2028, 9, 1));
    });
  });

  group('what it must NOT call a warranty', () {
    test('a year mentioned with nothing to do with one', () {
      expect(kind('We moved here in 2019 and it rained for a week',
          FactKind.expiry), isEmpty);
    });

    test('a span of time that is not about a guarantee', () {
      // "two years ago" is a memory, not an expiry, and filing it as one puts
      // a reminder in the past.
      expect(kind('We bought this two years ago', FactKind.expiry), isEmpty);
    });
  });

  group('money', () {
    test('a rupee sign, a prefix, or the word', () {
      expect(kind('It cost ₹45,000', FactKind.amount).single.value, '₹45,000');
      expect(kind('Rs 8999 for the mixer', FactKind.amount).single.value,
          '₹8,999');
      expect(kind('paid 12000 rupees', FactKind.amount).single.value,
          '₹12,000');
    });

    test('a lakh is grouped the way it is written here', () {
      // 12,50,000 — not 1,250,000. Western grouping is the tell that nobody
      // local read the output.
      expect(kind('₹1250000 for the car', FactKind.amount).single.value,
          '₹12,50,000');
    });

    test('a bare year is not money', () {
      expect(kind('since 2019', FactKind.amount), isEmpty);
    });
  });

  group('where', () {
    test('"from" is where a thing came from', () {
      final f = kind('Bought it from Vijay Sales', FactKind.shop);
      expect(f.single.value, 'Vijay Sales');
    });

    test('"in" and "at" are where you were', () {
      expect(kind('Took this in Jayanagar', FactKind.place).single.value,
          'Jayanagar');
      expect(kind('We met at Lalbagh', FactKind.place).single.value,
          'Lalbagh');
    });

    test('the two are not the same claim', () {
      // "bought it from Jayanagar" and "took this in Jayanagar" mean
      // different things and only one of them is a shop.
      final shop = of('Bought the fridge from Croma in Indiranagar');
      expect(shop.any((f) => f.kind == FactKind.shop && f.value == 'Croma'),
          isTrue);
      expect(
          shop.any((f) => f.kind == FactKind.place && f.value == 'Indiranagar'),
          isTrue);
    });
  });

  group('names', () {
    test('a capital inside a sentence is offered', () {
      expect(of('This is Amma\'s recipe').map((f) => f.value), contains('Amma'));
    });

    test('the first word of a sentence is not', () {
      // Its capital is grammar. Offering "Bought" as a person is the kind of
      // suggestion that makes somebody stop reading the suggestions.
      expect(of('Bought the machine today.').map((f) => f.value),
          isNot(contains('Bought')));
    });

    test('a month is not a person', () {
      expect(of('It arrived in March and worked.').map((f) => f.value),
          isNot(contains('March')));
    });
  });

  group('the whole sentence from the design', () {
    test('finds the warranty, the shop and the place', () {
      final f = of('Bought the washing machine from Vijay Sales in Jayanagar. '
          'Two year warranty, the bill is in the drawer.');
      final values = f.map((x) => x.value).toList();

      expect(values, contains('Warranty ends 14 Sep 2028'));
      expect(values, contains('Vijay Sales'));
      expect(values, contains('Jayanagar'));

      // The expiry leads, because it is the one that becomes a reminder and so
      // the one most worth a glance.
      expect(f.first.kind, FactKind.expiry);
    });

    test('nothing is offered twice', () {
      final f = of('Met Ravi at Lalbagh. Ravi said Lalbagh is best early.');
      final values = f.map((x) => '${x.kind}|${x.value}').toList();
      expect(values.length, values.toSet().length);
    });
  });

  test('ordinary talk offers nothing, rather than something', () {
    // A memory with no facts in it is completely normal and must not be
    // decorated with guesses to look busy.
    expect(of('it rained all afternoon and we stayed in'), isEmpty);
  });
}
