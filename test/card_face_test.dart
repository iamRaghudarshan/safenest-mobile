// The credit-card face, and the hash that decides its colour.
//
// A card in this product is not a list row — the web app draws an actual card,
// and the phone was rendering the same generic row it uses for an expense.
//
// THE GRADIENT IS DERIVED FROM THE BANK NAME, not stored, so the same card is
// the same colour on the laptop and the phone for ever without a column to hold
// it. That only holds if the two hashes agree exactly, and JavaScript's
//
//     h = (h * 31 + ch.charCodeAt(0)) >>> 0
//
// wraps at 32 bits while a Dart int is 64. Without the mask the value never
// wraps, the modulo lands elsewhere, and every card is a different colour on the
// two screens — a difference nobody would think to look for.
//
// The expected values below were computed by running the WEB app's algorithm,
// not by running this one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/theme.dart';
import 'package:safenest/widgets/card_face.dart';

void main() {
  group('gradientFor matches the web app byte for byte', () {
    // bank -> index into the seven gradients, per the JS implementation.
    const expected = <String, int>{
      'HDFC Bank': 1,
      'ICICI Bank': 4,
      'State Bank of India': 1,
      'Axis Bank': 5,
      'Kotak Mahindra': 1,
      'Punjab National Bank': 2,
      'Yes Bank': 0,
      'IDFC First': 3,
      'Other': 6,
      'card': 5,
    };

    // The seven, in the web app's order — the index is what the hash picks.
    const gradients = <List<Color>>[
      [Color(0xFF5B3DF5), Color(0xFF8B5CF6)],
      [Color(0xFF0EA5E9), Color(0xFF2563EB)],
      [Color(0xFFEC4899), Color(0xFFBE185D)],
      [Color(0xFF10B981), Color(0xFF0F766E)],
      [Color(0xFFF59E0B), Color(0xFFB45309)],
      [Color(0xFF334155), Color(0xFF0F172A)],
      [Color(0xFF7C3AED), Color(0xFF4338CA)],
    ];

    expected.forEach((bank, index) {
      test('$bank picks gradient $index', () {
        expect(gradientFor(bank), gradients[index],
            reason: 'a mismatch here means this card is one colour on the '
                'laptop and another on the phone');
      });
    });

    test('an empty name falls back to "card", not to a crash', () {
      expect(gradientFor(''), gradients[5]);
    });

    test('the same name always gives the same colour', () {
      for (final b in ['HDFC Bank', 'Some Credit Union', '']) {
        expect(gradientFor(b), gradientFor(b));
      }
    });
  });

  test('ordinal reads like a date', () {
    expect(ordinal(1), '1st');
    expect(ordinal(2), '2nd');
    expect(ordinal(3), '3rd');
    expect(ordinal(4), '4th');
    expect(ordinal(11), '11th', reason: '11th, not 11st');
    expect(ordinal(12), '12th');
    expect(ordinal(13), '13th');
    expect(ordinal(21), '21st');
    expect(ordinal(22), '22nd');
    expect(ordinal(31), '31st');
  });

  group('the card renders like a card', () {
    testWidgets('bank, masked number, due and limit — on an iPhone SE',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: Scaffold(
          body: CardFace(
            card: const {
              'bank': 'HDFC Bank',
              'last4': '4242',
              'credit_limit': 250000,
              'due_day': 5,
              'next_due_fmt': '05-09-2026',
              'days_until': 3,
              'paid_this_month': false,
            },
            onPay: () {},
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('HDFC Bank'), findsOneWidget);
      // Masked, like a real card — never the full number, which the server
      // does not store anyway.
      expect(find.text('•••• •••• •••• 4242'), findsOneWidget);
      expect(find.text('PAYMENT DUE'), findsOneWidget);
      expect(find.text('LIMIT'), findsOneWidget);
      expect(find.text('Mark paid'), findsOneWidget);
      expect(find.text('In 3 days'), findsOneWidget);
    });

    testWidgets('a paid card says so and offers Undo', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: Scaffold(
          body: CardFace(
            card: const {
              'bank': 'ICICI Bank',
              'last4': '1111',
              'paid_this_month': true,
              'paid_date': '02-08-2026',
              'due_day': 12,
            },
            onPay: () {},
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Paid'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      // A paid card looks forward, not back.
      expect(find.text('NEXT DUE'), findsOneWidget);
    });

    testWidgets('a card with almost nothing on it still lays out',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // A card just added, before a statement or a limit is known.
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: const Scaffold(body: CardFace(card: {})),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Card issuer'), findsOneWidget);
      expect(find.text('•••• •••• •••• ••••'), findsOneWidget);
      // No pay strip without a handler — a preview has nothing to press.
      expect(find.text('Mark paid'), findsNothing);
    });

    testWidgets('a very long bank name does not overflow', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: Scaffold(
          body: CardFace(
            card: const {
              'bank': 'Housing Development Finance Corporation Bank Limited',
              'last4': '9999',
              'credit_limit': 12500000,
              'due_day': 28,
              'paid_this_month': false,
              'days_until': -6,
            },
            onPay: () {},
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('6d overdue'), findsOneWidget);
    });
  });
}
