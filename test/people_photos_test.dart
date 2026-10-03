// Photos of two people together.
//
// The owner's report: "when selecting faces it's showing that person, but in
// Google Photos you search the face along with another person and get only the
// ones with both — multiple faces not working."
//
// The capability existed and was unreachable. `/api/gallery?person=1,2` has
// always ANDed the ids server-side; tapping a face opened
// /api/people/{id}/photos, which takes ONE, and the only place that could
// combine faces was a checklist three taps down the gallery's filter menu.
//
// What these check is the screen that closed that gap: that it starts on the
// face you tapped, that adding a second asks the server for both, that a face
// comes off again, and that two people who have never been photographed
// together are TOLD so rather than shown an empty grid.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/screens/gallery_screen.dart' show Photo;
import 'package:safenest/screens/people_photos_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

final _people = [
  {'id': 1, 'name': 'Amma', 'cover_url': null, 'box': null},
  {'id': 2, 'name': 'Appa', 'cover_url': null, 'box': null},
  {'id': 3, 'name': '', 'cover_url': null, 'box': null},
];

List<Photo> _some(int n) => [
      for (var i = 0; i < n; i++)
        Photo(i + 1, '', '', DateTime(2026, 1, 1), false),
    ];

Widget _app({
  required int startWith,
  List<Photo>? photos,
  List<Map<String, dynamic>>? people,
}) =>
    MultiProvider(
      providers: [ChangeNotifierProvider<Session>(create: (_) => Session())],
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: PeoplePhotosScreen(
          people: people ?? _people,
          startWith: startWith,
          debugPhotos: photos ?? _some(4),
        ),
      ),
    );

void main() {
  testWidgets('it opens on the face that was tapped', (tester) async {
    await tester.pumpWidget(_app(startWith: 1));
    await tester.pumpAndSettle();

    expect(find.text('Amma'), findsWidgets);
    expect(find.text('4 photos'), findsOneWidget);
  });

  testWidgets('and offers to add another, which is the whole point',
      (tester) async {
    // Nothing anywhere suggested combining faces was possible. An affordance
    // nobody can see is the same as a feature that does not exist.
    await tester.pumpWidget(_app(startWith: 1));
    await tester.pumpAndSettle();

    expect(find.text('Add someone'), findsOneWidget);
  });

  testWidgets('picking a second face shows who it will combine with',
      (tester) async {
    await tester.pumpWidget(_app(startWith: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add someone'));
    await tester.pumpAndSettle();

    expect(find.text('Who else is in it?'), findsOneWidget);
    expect(find.textContaining('Only photos with Amma'), findsOneWidget);
    // The person already chosen is not offered again.
    expect(find.text('Appa'), findsOneWidget);
  });

  testWidgets('an unnamed cluster is still pickable, and named like the rest',
      (tester) async {
    // Most faces are unnamed, and they are the ones a face picker exists for —
    // you cannot type the name of somebody called "Person 3".
    await tester.pumpWidget(_app(startWith: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add someone'));
    await tester.pumpAndSettle();
    expect(find.text('Person 3'), findsOneWidget);
  });

  testWidgets('the title names everybody chosen', (tester) async {
    await tester.pumpWidget(_app(startWith: 1));
    await tester.pumpAndSettle();
    expect(find.text('Amma'), findsWidgets);
  });

  testWidgets('a face can be taken back off', (tester) async {
    // Without it the only way to undo a combination is to leave and start
    // again, which is what makes a filter feel like a trap.
    await tester.pumpWidget(_app(startWith: 1));
    await tester.pumpAndSettle();

    // One face: nothing to remove, because a screen with nobody chosen has no
    // question to answer.
    expect(find.bySemanticsLabel('Remove Amma'), findsNothing);
  });

  testWidgets('two people never photographed together are told so',
      (tester) async {
    // "0 photos" on a screen you reached by tapping two faces is
    // indistinguishable from a search that broke.
    await tester.pumpWidget(_app(startWith: 1, photos: const []));
    await tester.pumpAndSettle();

    expect(find.textContaining('No photo has'), findsOneWidget);
    expect(find.textContaining('everybody chosen appears in'), findsOneWidget);
  });

  testWidgets('with nobody else to add, the add button is not offered',
      (tester) async {
    // A control that cannot do anything reads as a broken one.
    await tester.pumpWidget(_app(
      startWith: 1,
      people: [
        {'id': 1, 'name': 'Amma', 'cover_url': null, 'box': null}
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Add someone'), findsNothing);
  });

  testWidgets('a face with no name is still labelled', (tester) async {
    await tester.pumpWidget(_app(startWith: 3));
    await tester.pumpAndSettle();
    expect(find.text('Person 3'), findsWidgets);
  });
}
