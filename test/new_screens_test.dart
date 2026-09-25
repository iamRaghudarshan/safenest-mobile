// The screens added to close the phone's gap with the web app.
//
// WHAT THESE CAN AND CANNOT PROVE. There is no Android SDK and no Xcode on the
// machine this is written on, so nothing here observes a real device. What a
// widget test does reach is the thing that has actually broken in this project
// repeatedly: a screen that throws while laying out, or one whose empty state
// says something wrong. Every visual bug so far was found by the owner rather
// than by CI, and the answer to that is not to claim more than a test proves —
// it is to pin the parts a test genuinely covers.
//
// Each screen is given an Api pointed at a closed port, so the failing branch
// runs immediately and deterministically. That is the state a phone is in when
// the computer at home is switched off, and it is the one people photograph
// and send in.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/api.dart';
import 'package:safenest/screens/doc_recent.dart';
import 'package:safenest/screens/doc_trash.dart';
import 'package:safenest/screens/person_faces.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/face_circle.dart';

/// Port 1 is never listening, so the call fails at once rather than after a
/// timeout the test would have to wait out.
Api _deadApi() => Api(baseUrl: 'http://127.0.0.1:1', token: 'x');

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: child,
    );

void main() {
  group('the recycle bin', () {
    testWidgets('an unreachable computer says so instead of looking empty',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(DocTrashScreen(api: _deadApi())));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // "The bin is empty" over a failed request is the worst outcome here:
      // it tells somebody their deleted documents are gone when they are
      // sitting on a computer that is merely switched off.
      expect(find.text('The bin is empty'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('Empty is absent while there is nothing to empty',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(DocTrashScreen(api: _deadApi())));
      await tester.pumpAndSettle();
      // A destructive control that does nothing is worse than no control.
      expect(find.text('Empty'), findsNothing);
    });
  });

  group('Recent', () {
    testWidgets('keeps added, changed and starred apart', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _wrap(DocRecentScreen(api: _deadApi(), onOpen: (_) {})));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Three tabs, not one merged feed: "what did I just put in here" and
      // "what did I just work on" are different questions, and a single list
      // sorted by whichever timestamp is larger answers neither.
      expect(find.text('Added'), findsOneWidget);
      expect(find.text('Changed'), findsOneWidget);
      expect(find.text('Starred'), findsOneWidget);
    });
  });

  group('correcting a grouping', () {
    testWidgets('lays out, and offers merge and hide from the bar',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(PersonFacesScreen(
        api: _deadApi(),
        personId: 3,
        name: 'Asha',
        baseUrl: 'http://127.0.0.1:1',
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.byIcon(Icons.merge_type), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets('a long name does not overflow the bar', (tester) async {
      // 320 is the narrowest phone still in use, and the title is a name
      // somebody typed — there is no length limit on it.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(PersonFacesScreen(
        api: _deadApi(),
        personId: 3,
        name: 'Lakshmi Venkataraman Subramanian Iyer',
        baseUrl: 'http://127.0.0.1:1',
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('a face circle', () {
    testWidgets('with no box it shows the picture rather than nothing',
        (tester) async {
      // The fallback the server relies on: a hand-tagged person has no face
      // row, so no box, and guessing a crop would be worse than the photo.
      await tester.pumpWidget(_wrap(const Scaffold(
        body: Center(
          child: FaceCircle(imageUrl: null, box: null, size: 64),
        ),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('a zero-sized box is treated as no box, not as a crop',
        (tester) async {
      // A detector rectangle of zero width would divide by zero in the scale.
      await tester.pumpWidget(_wrap(const Scaffold(
        body: Center(
          child: FaceCircle(
            imageUrl: 'http://127.0.0.1:1/x.jpg',
            box: {'x': 0.1, 'y': 0.1, 'w': 0.0, 'h': 0.3},
            size: 64,
          ),
        ),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
