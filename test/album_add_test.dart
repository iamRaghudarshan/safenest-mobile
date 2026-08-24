// Putting photos INTO an album, both ways the sheet offers.
//
// The server half is verified against a running server by
// scratchpad/verify_album_upload.py (15 checks): upload?album_id=N stores and
// attaches, a duplicate still lands in the album, and somebody else's album is
// a 404 that stores nothing. What lives only in the app — and is therefore
// pinned here — is the picker's selection state and the album screen offering
// the feature at all. §10's recurring defect is "complete on the server,
// unreachable from the client"; these tests are what keep the reaching.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/screens/gallery_screen.dart';
import 'package:safenest/screens/library_tabs.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/photo_tile.dart';

List<Photo> _photos(int n) => [
  for (var i = 1; i <= n; i++)
    Photo(
      i,
      '/api/gallery/media/original/p$i.jpg?t=1.abc',
      '/api/gallery/media/thumb/p$i.jpg?t=1.abc',
      DateTime(2026, 8, 1 + (i % 3)),
      i == 1,
    ),
];

Widget _wrap(Widget child) {
  return ChangeNotifierProvider<Session>(
    create: (_) => Session(),
    child: MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: child,
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 667);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('the add-to-album picker', () {
    testWidgets('nothing selected means nothing to submit', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(AlbumAddPicker(initialPhotos: _photos(6))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Add photos'), findsOneWidget);
      expect(find.text('Tap the photos to add'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('tapping selects, counts in words, and pops the ids', (
      tester,
    ) async {
      _phone(tester);
      List<int>? popped;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  child: const Text('open'),
                  onPressed: () async {
                    popped = await Navigator.of(ctx).push<List<int>>(
                      MaterialPageRoute(
                        builder: (_) =>
                            AlbumAddPicker(initialPhotos: _photos(6)),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PhotoTile).at(0));
      await tester.pump();
      // Singular first — "1 photos" is the plural bug this wording exists to avoid.
      expect(find.text('Add 1 photo'), findsOneWidget);

      await tester.tap(find.byType(PhotoTile).at(2));
      await tester.pump();
      expect(find.text('Add 2 photos'), findsOneWidget);
      expect(find.text('2 selected'), findsOneWidget);

      // Deselecting works the same way as selecting.
      await tester.tap(find.byType(PhotoTile).at(2));
      await tester.pump();
      expect(find.text('Add 1 photo'), findsOneWidget);

      await tester.tap(find.text('Add 1 photo'));
      await tester.pumpAndSettle();
      expect(popped, [
        1,
      ], reason: 'the caller receives exactly the chosen photo ids');
    });
  });

  group('the album screen offers adding', () {
    testWidgets('an album gets the add button and the two-way sheet', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          CollectionScreen(
            title: 'Trip',
            path: '/api/gallery?album=3',
            albumId: 3,
            initialPhotos: _photos(3),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Choose from your gallery'), findsOneWidget);
      expect(find.text('Upload from this phone'), findsOneWidget);
    });

    testWidgets('a computed collection offers no adding', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          CollectionScreen(
            title: 'Ravi',
            path: '/api/people/2/photos',
            initialPhotos: _photos(3),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byIcon(Icons.add_photo_alternate_outlined),
        findsNothing,
        reason: 'you cannot put a photo into a person',
      );
    });

    testWidgets('an empty album says how to fill it', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          const CollectionScreen(
            title: 'New album',
            path: '/api/gallery?album=9',
            albumId: 9,
            initialPhotos: [],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Use ＋ to put photos in this album.'), findsOneWidget);
    });
  });
}
