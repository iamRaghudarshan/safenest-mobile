// The Track Me screen.
//
// The day-reading and the sentences are pinned in track_day_test.dart and
// track_story_test.dart. What is left is what somebody sees, and two promises
// the screen makes that nothing else can check:
//
//   * NOTHING IS RECORDED UNTIL YOU SAY SO, and the way to stop and the way to
//     delete are both on the same screen as the switch. A location recorder
//     that starts because somebody opened a screen is the thing nobody should
//     ship.
//   * ASKING "WHERE WAS I AT THREE" GETS A SENTENCE, not a map to search. The
//     map is there to confirm the answer, not to be the answer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/screens/track_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/track/day.dart';
import 'package:safenest/track/story.dart';

const home = (12.9279, 77.6271);
const office = (12.9716, 77.5946);

final day = DateTime(2026, 10, 3);
final evening = DateTime(2026, 10, 3, 20, 0);

/// Home 06:00–08:30, a drive, the office from 09:20.
List<Fix> aDay() => [
      for (var m = 0; m <= 150; m += 10)
        Fix(
            at: DateTime(2026, 10, 3, 6).add(Duration(minutes: m)),
            lat: home.$1,
            lon: home.$2,
            accuracy: 10),
      for (var i = 0; i <= 8; i++)
        Fix(
            at: DateTime(2026, 10, 3, 8, 30).add(Duration(minutes: i * 5)),
            lat: home.$1 + (office.$1 - home.$1) * (i / 8),
            lon: home.$2 + (office.$2 - home.$2) * (i / 8),
            accuracy: 12),
      for (var m = 0; m <= 420; m += 15)
        Fix(
            at: DateTime(2026, 10, 3, 9, 20).add(Duration(minutes: m)),
            lat: office.$1,
            lon: office.$2,
            accuracy: 10),
    ];

Widget _app({List<Fix>? fixes, List<Named>? places}) => MultiProvider(
      providers: [ChangeNotifierProvider<Session>(create: (_) => Session())],
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: TrackScreen(
          debugFixes: fixes ?? aDay(),
          debugPlaces: places,
          debugNow: evening,
        ),
      ),
    );

void main() {
  testWidgets('a day reads as sentences, not as coordinates', (tester) async {
    await tester.pumpWidget(_app(places: [
      Named(name: 'Home', lat: home.$1, lon: home.$2),
      Named(name: 'Office', lat: office.$1, lon: office.$2),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('Left Home'), findsOneWidget);
    expect(find.textContaining('reached Office'), findsOneWidget);
    // The thing a map is bad at and this is the point of.
    expect(find.textContaining('08:30'), findsWidgets);
  });

  testWidgets('a place with no name offers to be named, where it is',
      (tester) async {
    // The moment somebody is most willing to type "Home" is while looking at a
    // row that says they have not.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.textContaining('have not named'), findsWidgets);
    expect(find.text('Name this place'), findsWidgets);
  });

  testWidgets('a named place is named everywhere it appears', (tester) async {
    await tester.pumpWidget(_app(places: [
      Named(name: 'Home', lat: home.$1, lon: home.$2),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('Home,'), findsWidgets);
    // And the place that is still unnamed still offers it.
    expect(find.text('Name this place'), findsWidgets);
  });

  testWidgets('an empty day says so rather than showing a blank', (tester) async {
    await tester.pumpWidget(_app(fixes: const []));
    await tester.pumpAndSettle();

    expect(find.text('Not recording'), findsWidgets);
    expect(find.textContaining('kept on this phone'), findsOneWidget);
  });

  testWidgets('where the map comes from is said out loud', (tester) async {
    // Both because OpenStreetMap asks, and because the interesting half is the
    // other one: this phone did not fetch it.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.textContaining('this phone never asks anyone else'),
        findsOneWidget);
  });

  testWidgets('forgetting is offered on the same screen as the switch',
      (tester) async {
    // The person who wants to stop should not have to go looking.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Forget'), findsOneWidget);
    expect(find.byTooltip('Where was I at…'), findsOneWidget);
  });

  testWidgets('the day can be stepped back and forth', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.byTooltip('The day before'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
  });

  testWidgets('and never forward past today', (tester) async {
    // There is nothing recorded in the future, and a chevron that does nothing
    // reads as a broken one.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final later = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('The day after'),
        matching: find.byType(IconButton)));
    expect(later.onPressed, isNull);
  });
}
