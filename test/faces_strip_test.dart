// The strip of faces along the top of the gallery.
//
// Both of these came off one screenshot from a real phone: six grey silhouettes,
// three of them labelled "411", "249", "146".
//
//   * The covers never loaded. The server mints a RELATIVE, signed media path
//     and Image.network cannot resolve one, so every face fell straight to its
//     errorBuilder. It read as "face detection is broken" when every face had
//     been found and the pictures were simply never fetched.
//   * An unnamed face was labelled with a bare number, which under a blank
//     circle reads as a fault rather than as a count.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/screens/gallery_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/photo_tile.dart';

Widget _wrap(Widget child) {
  return ChangeNotifierProvider<Session>(
    create: (_) => Session(),
    child: MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 667);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _chip(Map<String, dynamic> person) =>
    FaceChip(person: person, selected: false, onTap: () {});

void main() {
  // The rule itself, as plain logic. This is the defect: a relative path handed
  // to Image.network fetches nothing at all.
  group('a media path is made absolute before it is fetched', () {
    const base = 'https://safenest.example.com';

    test('a relative path gets the server address in front of it', () {
      expect(
        absoluteMedia('/api/gallery/media/thumb/a.jpg?t=1786245088.4e94', base),
        '$base/api/gallery/media/thumb/a.jpg?t=1786245088.4e94',
      );
    });

    test('the signature survives, because without it the fetch is refused', () {
      final out = absoluteMedia('/api/gallery/media/thumb/a.jpg?t=99.abc', base);
      expect(out.endsWith('?t=99.abc'), isTrue);
    });

    test('an absolute URL is left exactly as it is', () {
      const already = 'https://elsewhere.example.com/thumb/x.jpg?t=1.a';
      expect(absoluteMedia(already, base), already);
    });

    test('no server address yet leaves the path alone rather than mangling it', () {
      expect(absoluteMedia('/api/x.jpg', ''), '/api/x.jpg');
    });
  });

  group('a face chip shows a picture when it has one', () {
    testWidgets('a cover produces an image, not the silhouette', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(_chip(const {
        'id': 3,
        'name': 'Baba',
        'count': 12,
        'cover_url': '/api/gallery/media/thumb/abc.jpg?t=1786245088.4e94',
      })));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('no cover shows the silhouette, not a broken image', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(_chip(const {'id': 5, 'name': 'Asha', 'count': 1})),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });

  group('what a face is labelled', () {
    testWidgets('a named face shows its name', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(_chip(const {'id': 1, 'name': 'Baba', 'count': 411})),
      );
      await tester.pump();
      expect(find.text('Baba'), findsOneWidget);
    });

    testWidgets('an unnamed face counts in words, never a bare number', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(_chip(const {'id': 2, 'name': '', 'count': 411})),
      );
      await tester.pump();
      expect(find.text('411 photos'), findsOneWidget);
      expect(
        find.text('411'),
        findsNothing,
        reason: 'a bare number under a face reads as a fault, which is exactly '
            'how it was reported',
      );
    });

    testWidgets('one photo is singular', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(_chip(const {'id': 6, 'name': '', 'count': 1})),
      );
      await tester.pump();
      expect(find.text('1 photo'), findsOneWidget);
    });

    testWidgets('"Person 7" is the clustering talking, not a name', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(_chip(const {'id': 7, 'name': 'Person 7', 'count': 9})),
      );
      await tester.pump();
      expect(find.text('9 photos'), findsOneWidget);
      expect(find.text('Person 7'), findsNothing);
    });
  });
}
