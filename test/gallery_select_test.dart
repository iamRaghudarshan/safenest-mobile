// Selecting photos, and the trash that makes deleting them safe.
//
// The backend supported all of this from the beginning — /albums/{id}/photos
// and /albums/{id}/remove take a LIST of photo_ids, album creation takes one
// too, and delete is SOFT with restore and permanent-delete beside it. The
// phone reached none of it, because there was no way to select anything.
//
// The endpoints themselves are verified against the running server by
// scratchpad/verify_gallery_actions.py (27 checks). These are the parts that
// live only in the app: the selection state machine and the two bars.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/screens/gallery_screen.dart';
import 'package:safenest/screens/cleanup_screen.dart';
import 'package:safenest/screens/trash_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/photo_tile.dart';
import 'package:safenest/widgets/selection_bar.dart';

List<Photo> _photos(int n) => [
      for (var i = 1; i <= n; i++)
        Photo(
          i,
          '/api/gallery/media/original/p$i.jpg?t=1.abc',
          '/api/gallery/media/thumb/p$i.jpg?t=1.abc',
          DateTime(2026, 8, 1 + (i % 3)),
          i == 1,
        )
    ];

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return ChangeNotifierProvider<Session>(
    create: (_) => Session(),
    child: MaterialApp(
      theme: buildTheme(const Brand(), brightness),
      home: child,
    ),
  );
}

void main() {
  group('the tile knows how to be selected', () {
    testWidgets('a tick only appears while selecting', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final p = _photos(1).first;

      await tester.pumpWidget(_wrap(Scaffold(
          body: SizedBox(
              width: 120, height: 120, child: PhotoTile(photo: p)))));
      await tester.pump();
      expect(find.byIcon(Icons.check), findsNothing,
          reason: 'no ticks on a grid nobody is selecting in');

      await tester.pumpWidget(_wrap(Scaffold(
          body: SizedBox(
              width: 120,
              height: 120,
              child: PhotoTile(photo: p, selecting: true, selected: true)))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('long-press and tap are wired separately', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var opened = 0, longPressed = 0;
      await tester.pumpWidget(_wrap(Scaffold(
        body: SizedBox(
          width: 120,
          height: 120,
          child: PhotoTile(
            photo: _photos(1).first,
            onOpen: () => opened++,
            onLongPress: () => longPressed++,
          ),
        ),
      )));
      await tester.pump();

      await tester.tap(find.byType(PhotoTile));
      await tester.pump();
      expect(opened, 1);
      expect(longPressed, 0);

      await tester.longPress(find.byType(PhotoTile));
      await tester.pump();
      expect(longPressed, 1,
          reason: 'long-press starts selection — there is no button to find');
      expect(opened, 1, reason: 'a long press must not also open the photo');
    });
  });

  group('the selection bar', () {
    testWidgets('states the count in words and offers the three actions',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(Scaffold(
        bottomNavigationBar: SelectionBar(
          count: 12,
          busy: false,
          onClear: () {},
          onSelectAll: () {},
          onDelete: () {},
          onAlbum: () {},
          onFavourite: () {},
        ),
      )));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Counting ticks across a grid of thumbnails is not checkable at a
      // glance; a number is.
      expect(find.text('12 selected'), findsOneWidget);
      expect(find.text('Album'), findsOneWidget);
      expect(find.text('Star'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
    });

    testWidgets('every action is disabled while one is running', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var taps = 0;
      await tester.pumpWidget(_wrap(Scaffold(
        bottomNavigationBar: SelectionBar(
          count: 3,
          busy: true,
          onClear: () => taps++,
          onSelectAll: () => taps++,
          onDelete: () => taps++,
          onAlbum: () => taps++,
          onFavourite: () => taps++,
        ),
      )));
      await tester.pump();

      await tester.tap(find.text('Album'));
      await tester.tap(find.text('Delete'));
      await tester.pump();
      // Deleting the same twelve photos twice because the first tap looked
      // like it did nothing is exactly the mistake to design out.
      expect(taps, 0);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('a four-figure selection still fits an iPhone SE',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(Scaffold(
        bottomNavigationBar: SelectionBar(
          count: 20431,
          busy: false,
          onClear: () {},
          onSelectAll: () {},
          onDelete: () {},
          onAlbum: () {},
          onFavourite: () {},
        ),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('20431 selected'), findsOneWidget);
    });
  });

  group('the album picker', () {
    testWidgets('offers a new album first, then the existing ones',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(Scaffold(
        body: AlbumPicker(count: 5, albums: const [
          {'id': 1, 'name': 'Kerala 2026', 'count': 214},
          {'id': 2, 'name': 'Documents to scan', 'count': 3},
        ]),
      )));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Add 5 photos to…'), findsOneWidget);
      // New album first: the common case is photos that belong nowhere yet,
      // which is why the create endpoint takes photo_ids at all.
      expect(find.text('New album'), findsOneWidget);
      expect(find.text('Kerala 2026'), findsOneWidget);
      expect(find.text('214 photos'), findsOneWidget);
      expect(find.text('3 photos'), findsOneWidget);
    });

    testWidgets('one photo reads as a photo, not "1 photos"', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(Scaffold(
        body: AlbumPicker(count: 1, albums: const [
          {'id': 1, 'name': 'Solo', 'count': 1},
        ]),
      )));
      await tester.pump();
      expect(find.text('Add 1 photo to…'), findsOneWidget);
      expect(find.text('1 photo'), findsOneWidget);
    });

    testWidgets('with no albums at all it still offers to create one',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _wrap(Scaffold(body: AlbumPicker(count: 2, albums: const []))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('New album'), findsOneWidget);
    });
  });

  group('Recently deleted', () {
    testWidgets('lays out and everything is selectable immediately',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(TrashScreen(initialPhotos: _photos(6))));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('6 photos'), findsOneWidget);
      // No long-press ceremony here: there is nothing else to do with a
      // deleted photo but pick it.
      expect(find.byType(PhotoTile), findsWidgets);
    });

    testWidgets('empty says the deletion is still reversible', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const TrashScreen(initialPhotos: [])));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Nothing deleted'), findsOneWidget);
    });

    testWidgets('selecting reveals Put back and Delete', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(TrashScreen(initialPhotos: _photos(3))));
      await tester.pump();

      await tester.tap(find.byType(PhotoTile).first);
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      // Restore is the FILLED button and permanent delete is the outlined one:
      // the reversible action should be the easy one to hit.
      expect(find.text('Put back'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('Free up space', () {
    // Exact duplicates essentially cannot happen: the upload endpoint dedupes
    // on content_hash — three identical uploads return the SAME photo and the
    // library grows by one, which was verified against the server. So the
    // screen opens on "Look alike", where the space actually goes.
    testWidgets('opens on Look alike, not Exact copies', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const CleanupScreen(initialGroups: [])));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('NOT identical'), findsOneWidget);
    });

    testWidgets('a group keeps one and marks the rest', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(CleanupScreen(initialMode: 1, initialGroups: [
        {
          'hash': 'e88eaa0f173b86e8',
          'count': 3,
          'keep_id': 2,
          'items': [
            {'id': 1, 'thumb_url': '/t/1.jpg?t=1.a', 'url': '/o/1.jpg?t=1.a'},
            {'id': 2, 'thumb_url': '/t/2.jpg?t=1.a', 'url': '/o/2.jpg?t=1.a'},
            {'id': 3, 'thumb_url': '/t/3.jpg?t=1.a', 'url': '/o/3.jpg?t=1.a'},
          ],
        },
      ])));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The server's suggestion is honoured, and the maths is stated on the
      // button rather than left to be counted.
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Remove'), findsNWidgets(2));
      expect(find.text('Remove 2 and keep 1'), findsOneWidget);
      expect(find.text('3 copies'), findsOneWidget);
    });

    testWidgets('nothing to clean says so without alarming anybody',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _wrap(const CleanupScreen(initialMode: 1, initialGroups: [])));
      await tester.pump();
      expect(find.text('Nothing looks duplicated'), findsOneWidget);
      // No action bar when there is nothing to do.
      expect(find.textContaining('Remove '), findsNothing);
    });
  });
}
