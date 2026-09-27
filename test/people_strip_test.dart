// The faces along the top of the photo grid.
//
// Most of what is asserted is WHO GETS IN, because a strip of strangers
// labelled "Person 12" is worse than no strip at all: it asks somebody to
// identify a face before it will help them find anything. That rule is one
// regex and one count check, and it is exactly the kind of thing that breaks
// silently when the server starts returning a slightly different shape.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/theme.dart';
import 'package:safenest/widgets/people_strip.dart';

Map<String, dynamic> person(String name, {int count = 5, int id = 1}) =>
    {'id': id, 'name': name, 'photo_count': count};

void main() {
  group('who gets into the strip', () {
    test('named people with photographs do', () {
      final out = stripPeople([person('Anita'), person('Dad', id: 2)]);
      expect(out.length, 2);
    });

    test('the clustering\'s own placeholders do not', () {
      // "Person 12" is what the face grouping calls somebody nobody has named
      // yet. Offering it as a way to find photographs is offering a stranger.
      final out = stripPeople([
        person('Person 12'),
        person('person 3'),
        person('PERSON 41'),
        person('Person  7'),
        person('Anita'),
      ]);
      expect(out.length, 1);
      expect(out.single['name'], 'Anita');
    });

    test('a real name that merely contains a number still gets in', () {
      // The rule is anchored for a reason: it must reject the placeholder
      // without rejecting somebody actually called this.
      final out = stripPeople([person('Person of the Year'), person('R2')]);
      expect(out.length, 2);
    });

    test('nameless, blank and whitespace-only are all out', () {
      final out = stripPeople([
        {'id': 1, 'photo_count': 9},
        person(''),
        person('   '),
      ]);
      expect(out, isEmpty);
    });

    test('a face with no photographs is out', () {
      // It cannot narrow anything, so tapping it would empty the grid.
      expect(stripPeople([person('Anita', count: 0)]), isEmpty);
    });

    test('a missing count is treated as none rather than crashing', () {
      expect(stripPeople([
        {'id': 1, 'name': 'Anita'}
      ]), isEmpty);
    });
  });

  group('what it says', () {
    Future<void> pump(WidgetTester tester, Set<int> selected) =>
        tester.pumpWidget(MaterialApp(
          theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
          home: Scaffold(
            body: PeopleStrip(
              people: [
                person('Anita', id: 1),
                person('Dad', id: 2),
                person('Meera', id: 3),
              ],
              selected: selected,
              onToggle: (_) {},
            ),
          ),
        ));

    testWidgets('nothing picked is just "People"', (tester) async {
      await pump(tester, <int>{});
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Anita'), findsOneWidget);
    });

    testWidgets('two picked says it narrows, not widens', (tester) async {
      // The one thing that surprises people: a second face shows FEWER
      // photographs. The heading has to say so, or the grid emptying looks
      // like a bug.
      await pump(tester, {1, 2});
      expect(find.text('Only photos with all 2 of them'), findsOneWidget);
    });

    testWidgets('one picked reads naturally, not "all 1 of them"',
        (tester) async {
      await pump(tester, {1});
      expect(find.text('Photos of 1 person'), findsOneWidget);
    });

    testWidgets('an empty list draws nothing at all', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
        home: Scaffold(
          body: PeopleStrip(
            people: const [],
            selected: const <int>{},
            onToggle: (_) {},
          ),
        ),
      ));
      // Not an empty box with a heading over it — nothing.
      expect(find.text('People'), findsNothing);
    });

    testWidgets('tapping a face reports that person', (tester) async {
      Map<String, dynamic>? tapped;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
        home: Scaffold(
          body: PeopleStrip(
            people: [person('Anita', id: 7)],
            selected: const <int>{},
            onToggle: (p) => tapped = p,
          ),
        ),
      ));
      await tester.tap(find.text('Anita'));
      expect(tapped?['id'], 7);
    });
  });
}
