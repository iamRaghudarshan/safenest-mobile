// The search screen.
//
// The ranking is pinned in memory_find_test.dart. What is left is what somebody
// sees, and the specific failures the old sheet had: a query per keystroke, no
// sign of WHY a result is in the list, no way to say "the one with the photo",
// and near misses either absent or silently mixed in with real matches.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/screens/memory_search_screen.dart';
import 'package:safenest/theme.dart';

final _now = DateTime(2026, 10, 3, 11);

Map<String, dynamic> mem(
  int id,
  String body, {
  DateTime? at,
  List<Map<String, dynamic>> facts = const [],
  String? photo,
}) =>
    {
      'id': id,
      'body': body,
      'said_at': (at ?? _now.subtract(const Duration(days: 2)))
          .toIso8601String(),
      'spoken': 0,
      'server_id': null,
      'photo_path': photo,
      'facts': facts,
    };

final _rows = [
  mem(1, 'Bought the washing machine from Vijay Sales for Rs 32,400.',
      facts: [
        {'kind': 'amount', 'value': '₹32,400', 'at': null},
        {'kind': 'shop', 'value': 'Vijay Sales', 'at': null},
      ]),
  mem(2, 'Amma says tamarind goes in first.',
      at: _now.subtract(const Duration(days: 300)),
      facts: [
        {'kind': 'person', 'value': 'Amma', 'at': null}
      ]),
  mem(3, 'Took this at Lalbagh with Appa.',
      at: _now.subtract(const Duration(days: 100)),
      photo: '/x/m_1.jpg',
      facts: [
        {'kind': 'place', 'value': 'Lalbagh', 'at': null}
      ]),
];

/// Counts how many times the store was asked, which is the whole point of the
/// debounce.
class _Calls {
  int n = 0;
  final terms = <List<String>>[];
}

Widget _app({
  List<Map<String, dynamic>>? rows,
  _Calls? calls,
  List<String>? recent,
  void Function(String)? onAsk,
}) =>
    MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: MemorySearchScreen(
        debugNow: _now,
        debugRecent: recent ?? const [],
        onAsk: onAsk,
        look: (terms) async {
          calls?.n++;
          calls?.terms.add(terms);
          final all = rows ?? _rows;
          if (terms.isEmpty) return all;
          // Stands in for the store's OR query: anything containing ANY term,
          // on a five-character prefix.
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

Future<void> _type(WidgetTester tester, String s) async {
  await tester.enterText(find.byType(TextField), s);
  // Past the debounce.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it waits for you to stop typing before it asks the store',
      (tester) async {
    // A query per character is four thrown away for "croma", and on a long
    // thread the list flickers through four different answers while you type.
    final calls = _Calls();
    await tester.pumpWidget(_app(calls: calls));
    await tester.pumpAndSettle();
    final atStart = calls.n; // the empty pool, fetched on open

    await tester.enterText(find.byType(TextField), 'v');
    await tester.pump(const Duration(milliseconds: 40));
    await tester.enterText(find.byType(TextField), 'vi');
    await tester.pump(const Duration(milliseconds: 40));
    await tester.enterText(find.byType(TextField), 'vij');
    await tester.pump(const Duration(milliseconds: 40));
    expect(calls.n, atStart, reason: 'nothing yet — still typing');

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(calls.n, atStart + 1, reason: 'exactly one query for the lot');
  });

  testWidgets('all the words, in any order, across the sentence and the tags',
      (tester) async {
    // The case the old LIKE-the-whole-phrase search returned nothing for.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _type(tester, 'vijay washing');

    expect(find.textContaining('Bought the washing machine'), findsOneWidget);
    expect(find.text('1 memory'), findsOneWidget);
  });

  testWidgets('a word that matches nothing rules the memory out',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _type(tester, 'washing fridge');

    expect(find.textContaining('Nothing you have told it matches'),
        findsOneWidget);
  });

  testWidgets('a near miss is shown under its own heading, never mixed in',
      (tester) async {
    // Silently returning approximate results is how somebody decides the
    // search returns nonsense.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _type(tester, 'lalbgah');

    expect(find.text('NOTHING EXACT — DID YOU MEAN'), findsOneWidget);
    expect(find.textContaining('Lalbagh'), findsWidgets);
  });

  testWidgets('what you typed is offered spelt the way the memory spells it',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _type(tester, 'vij');

    // The completion, from the confirmed tags.
    expect(find.text('Vijay Sales'), findsWidgets);
  });

  testWidgets('tapping a completion searches for it', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _type(tester, 'vij');

    await tester.tap(find.byIcon(Icons.north_west).first);
    await tester.pumpAndSettle();

    expect(find.text('1 memory'), findsOneWidget);
  });

  group('narrowing', () {
    testWidgets('only the filters with something behind them are offered',
        (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('Everything'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('With a photo'), findsOneWidget);
      // Nothing here carries a date, so no Dates chip.
      expect(find.text('Dates'), findsNothing);
    });

    testWidgets('a filter on its own lists everything that qualifies',
        (tester) async {
      // "The one with the picture" is how people hunt, and no amount of typing
      // expresses it.
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('With a photo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Lalbagh'), findsWidgets);
      expect(find.textContaining('washing machine'), findsNothing);
    });

    testWidgets('a filter narrows a search rather than replacing it',
        (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _type(tester, 'tamarind');
      expect(find.text('1 memory'), findsOneWidget);

      await tester.tap(find.text('Money'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing in money matches'), findsOneWidget);
    });

    testWidgets('changing a filter does not go back to the store',
        (tester) async {
      // Filtering is done on what is already in hand, so a chip is instant.
      final calls = _Calls();
      await tester.pumpWidget(_app(calls: calls));
      await tester.pumpAndSettle();
      final before = calls.n;

      await tester.tap(find.text('With a photo'));
      await tester.pumpAndSettle();
      expect(calls.n, before);
    });
  });

  group('recent searches', () {
    testWidgets('they are offered before anything is typed', (tester) async {
      await tester.pumpWidget(_app(recent: ['croma', 'warranty']));
      await tester.pumpAndSettle();

      expect(find.text('RECENT'), findsOneWidget);
      expect(find.text('croma'), findsOneWidget);
    });

    testWidgets('tapping one runs it', (tester) async {
      await tester.pumpWidget(_app(recent: ['tamarind']));
      await tester.pumpAndSettle();

      await tester.tap(find.text('tamarind'));
      await tester.pumpAndSettle();
      expect(find.text('1 memory'), findsOneWidget);
    });

    testWidgets('a search that found something joins the list',
        (tester) async {
      await tester.pumpWidget(_app(recent: const []));
      await tester.pumpAndSettle();
      await _type(tester, 'tamarind');

      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('RECENT'), findsOneWidget);
      expect(find.text('tamarind'), findsWidgets);
    });
  });

  group('asking instead', () {
    testWidgets('a typed question offers the answer screen', (tester) async {
      var asked = '';
      await tester.pumpWidget(_app(onAsk: (q) => asked = q));
      await tester.pumpAndSettle();
      await _type(tester, 'where is the car insurance policy');

      expect(find.textContaining('Ask it instead'), findsOneWidget);
      await tester.tap(find.textContaining('Ask it instead'));
      await tester.pumpAndSettle();
      expect(asked, 'where is the car insurance policy');
    });

    testWidgets('a plain word search does not offer it', (tester) async {
      // An offer that appears under every search is an offer nobody reads.
      await tester.pumpWidget(_app(onAsk: (_) {}));
      await tester.pumpAndSettle();
      await _type(tester, 'tamarind');

      expect(find.textContaining('Ask it instead'), findsNothing);
    });
  });

  testWidgets('clearing goes back to the recent list', (tester) async {
    await tester.pumpWidget(_app(recent: ['croma']));
    await tester.pumpAndSettle();
    await _type(tester, 'tamarind');
    expect(find.text('RECENT'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('RECENT'), findsOneWidget);
  });
}
