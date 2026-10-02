// The Ask screen: what somebody actually sees when they ask a question.
//
// The engine is pinned in memory_ask_test.dart. What is left is the promise the
// screen makes, and it is a specific one: an answer NEVER appears without how
// sure it is and the words it came from. A confident-sounding sentence with no
// evidence is the one failure that would make this feature worse than not
// having it, so that is what most of these check.
//
// No database here, for the reason written up in life_memory_screen_test.dart —
// the lookup is injected.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/screens/memory_ask_screen.dart';
import 'package:safenest/theme.dart';

final _now = DateTime(2026, 10, 2, 11, 0);

Map<String, dynamic> mem(int id, String body,
        {DateTime? at, List<Map<String, dynamic>> facts = const []}) =>
    {
      'id': id,
      'body': body,
      'said_at': (at ?? _now.subtract(const Duration(days: 5)))
          .toIso8601String(),
      'spoken': 0,
      'server_id': null,
      'facts': facts,
    };

final _rows = [
  mem(1, 'Bought the washing machine from Vijay Sales for ₹32,400. '
      'Two year warranty.',
      facts: [
        {
          'kind': 'expiry',
          'value': 'Warranty ends 26 Sep 2028',
          'at': DateTime(2028, 9, 26).toIso8601String()
        },
        {'kind': 'amount', 'value': '₹32,400', 'at': null},
        {'kind': 'shop', 'value': 'Vijay Sales', 'at': null},
      ]),
  mem(2, 'Amma says tamarind goes in first.',
      at: DateTime(2025, 5, 2),
      facts: [
        {'kind': 'person', 'value': 'Amma', 'at': null}
      ]),
];

Widget _app({List<Map<String, dynamic>>? rows, List<String>? sawTerms}) =>
    MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: MemoryAskScreen(
        debugNow: _now,
        look: (terms) async {
          sawTerms?.addAll(terms);
          final all = rows ?? _rows;
          if (terms.isEmpty) return all;
          // Stands in for the store's OR-of-prefixes query, on the same stems.
          return [
            for (final r in all)
              if (terms.any((t) {
                final stem = t.length <= 5 ? t : t.substring(0, 5);
                final hay = '${r['body']} '
                    '${(r['facts'] as List).map((f) => f['value']).join(' ')}'
                    .toLowerCase();
                return hay.contains(stem);
              }))
                r
          ];
        },
      ),
    );

Future<void> _ask(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it opens with questions it can actually answer',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('TRY ONE OF THESE'), findsOneWidget);
    // And it says where the answering happens, because that is the whole reason
    // it answers this way rather than with a model.
    expect(find.textContaining('Answered on this phone'), findsOneWidget);
  });

  testWidgets('an empty life offers no hollow suggestions', (tester) async {
    await tester.pumpWidget(_app(rows: const []));
    await tester.pumpAndSettle();

    expect(find.text('TRY ONE OF THESE'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a question is answered with a sentence and its evidence',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _ask(tester, 'where did I buy the washing machine');

    expect(find.textContaining('Vijay Sales'), findsWidgets);
    // THE RULE. Never a sentence on its own.
    expect(find.text('WHAT THAT CAME FROM'), findsOneWidget);
    expect(find.text('FROM WHAT YOU SAID'), findsOneWidget);
    expect(find.textContaining('Nothing was sent anywhere'), findsOneWidget);
  });

  testWidgets('the evidence is the words, verbatim, with its date',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _ask(tester, 'when does the warranty end');

    expect(
        find.textContaining('Bought the washing machine from Vijay Sales'),
        findsWidgets);
    expect(find.textContaining('you said this on'), findsWidgets);
  });

  testWidgets('a question it cannot answer says so instead of inventing',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _ask(tester, 'where is the car insurance policy');

    expect(find.text('NOTHING RECORDED'), findsOneWidget);
    expect(find.textContaining('insurance'), findsWidgets);
    // Nothing to cite, so nothing is cited — an evidence heading over an empty
    // space reads as a failure to load.
    expect(find.text('WHAT THAT CAME FROM'), findsNothing);
  });

  testWidgets('a half-answer is labelled NOT SURE and still shows the words',
      (tester) async {
    // Lalbagh is mentioned nowhere, but "cost" matches nothing either, so what
    // comes back is at best adjacent. The badge has to say so.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _ask(tester, 'how much did Amma cost');

    expect(find.text('NOT SURE'), findsOneWidget);
    expect(find.text('WHAT THAT CAME FROM'), findsOneWidget);
  });

  testWidgets('tapping a suggestion asks it', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final suggestion = find.byIcon(Icons.north_east).first;
    await tester.tap(suggestion);
    await tester.pumpAndSettle();

    expect(find.text('WHAT THAT CAME FROM'), findsOneWidget);
  });

  testWidgets('only the question words are sent to the store', (tester) async {
    // The screen and the store have to agree about what counts as a word, or
    // the scorer is handed rows that do not contain what it is scoring for.
    final seen = <String>[];
    await tester.pumpWidget(_app(sawTerms: seen));
    await tester.pumpAndSettle();
    seen.clear();
    await _ask(tester, 'where did I buy the washing machine');

    expect(seen, ['buy', 'washing', 'machine']);
  });

  testWidgets('the memory the answer came from is marked out', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _ask(tester, 'who told me about tamarind');

    // Numbered, so the sentence and its source can be lined up.
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a lookup that fails says nothing was lost', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: MemoryAskScreen(
        debugNow: _now,
        look: (_) async => throw StateError('disk gone'),
      ),
    ));
    await tester.pumpAndSettle();
    await _ask(tester, 'anything at all');

    expect(find.textContaining('Nothing was lost'), findsOneWidget);
  });

  testWidgets('opening it already answered works, so the sweep draws an answer',
      (tester) async {
    // If this ever stops working the layout sweep goes on passing while drawing
    // nothing but the empty state, which is the gap it exists to close.
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: MemoryAskScreen(
        debugNow: _now,
        debugQuestion: 'where did I buy the washing machine',
        look: (_) async => _rows,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('WHAT THAT CAME FROM'), findsOneWidget);
    expect(find.textContaining('Vijay Sales'), findsWidgets);
  });
}
