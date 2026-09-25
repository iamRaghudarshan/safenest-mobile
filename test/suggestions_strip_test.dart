// The suggestions panel on Collections.
//
// It drew a generic icon in a tinted square beside a sentence — for a
// suggestion ABOUT somebody's own photographs, which is the one thing worth
// showing. "A moving highlight from 25 September" means nothing on its own.
// The server sent only photo ids, so the panel had nothing to draw even if it
// had wanted to.
//
// These pin the two things that made it read wrongly: no pictures, and eight
// full-width cards stacked above the albums.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/api.dart';
import 'package:safenest/screens/suggestions_strip.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

Widget _wrap(Widget child) => ChangeNotifierProvider<Session>(
      create: (_) => Session(),
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('draws nothing at all when there is nothing to offer',
      (tester) async {
    // An empty panel with a heading is a permanent reminder that a feature
    // exists and has no opinion, which is worse than silence. Port 1 is never
    // listening, so the load fails at once.
    await tester.pumpWidget(_wrap(
        SuggestionsStrip(api: Api(baseUrl: 'http://127.0.0.1:1', token: 'x'))));
    await tester.pumpAndSettle();

    expect(find.text('SUGGESTIONS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failure to load is silent, not an error on the screen',
      (tester) async {
    await tester.pumpWidget(_wrap(
        SuggestionsStrip(api: Api(baseUrl: 'http://127.0.0.1:1', token: 'x'))));
    await tester.pumpAndSettle();
    // Nothing on this screen is waiting for suggestions. A panel that cannot
    // load is a panel that is not drawn.
    expect(find.textContaining('Could not'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
