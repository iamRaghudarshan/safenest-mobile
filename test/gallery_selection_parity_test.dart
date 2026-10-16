// The three things that made selection feel unlike Google Photos.
//
// Selection already worked — long-press, slide to extend, tap a date circle
// for the whole day. What it lacked was everything AROUND the picking: the bar
// never acknowledged it, back threw the screen away rather than the selection,
// and a drag stopped dead at the edge of the glass.
//
// Each test here fails with its change reverted; that is the point of them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/screens/gallery_screen.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/selection_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: child,
    );

void main() {
  group('the count reaches whoever draws the bar', () {
    test('a fresh selection is inactive and silent', () {
      final s = GallerySelection();
      addTearDown(s.dispose);
      expect(s.count, 0);
      expect(s.active, isFalse);
    });

    test('it notifies when the number moves, and not when it does not', () {
      // The grid reports from a post-frame callback on EVERY build, so this is
      // called constantly — scrolling, loading a page, a rebuild from anything
      // at all. Without the equality check the app bar would rebuild on each
      // one of those.
      final s = GallerySelection();
      addTearDown(s.dispose);
      var rebuilds = 0;
      s.addListener(() => rebuilds++);

      s.report(3);
      s.report(3);
      s.report(3);
      expect(rebuilds, 1, reason: 'the same count must not rebuild the bar');

      s.report(4);
      expect(rebuilds, 2);
      expect(s.active, isTrue);

      s.report(0);
      expect(rebuilds, 3);
      expect(s.active, isFalse,
          reason: 'back at zero the ordinary bar returns');
    });
  });

  group('the bar that appears once photos are picked', () {
    Widget bar({bool busy = false, void Function(String)? tapped}) =>
        _wrap(Scaffold(
          bottomNavigationBar: SelectionBar(
            count: 3,
            busy: busy,
            onClear: () => tapped?.call('clear'),
            onSelectAll: () => tapped?.call('all'),
            onDelete: () => tapped?.call('delete'),
            onAlbum: () => tapped?.call('album'),
            onFavourite: () => tapped?.call('star'),
            onArchive: () => tapped?.call('archive'),
            onShare: () => tapped?.call('share'),
          ),
        ));

    testWidgets('shows the three Google Photos keeps, and no count',
        (tester) async {
      await tester.pumpWidget(bar());
      await tester.pumpAndSettle();

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Add to album'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      // The count belongs to the app bar now. Two places stating it is how the
      // two drift apart.
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('Star and Archive are still reachable, one tap in',
        (tester) async {
      // The real cost of the parity layout, so it is pinned: moved, NOT
      // removed. Archive especially — without it the only way out of a
      // crowded timeline is deleting photographs somebody wanted to keep.
      final taps = <String>[];
      await tester.pumpWidget(bar(tapped: taps.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsOneWidget);

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(taps, ['archive'], reason: 'the overflow must really fire it');
    });

    testWidgets('and Select all moved there too', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(bar(tapped: taps.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(taps, ['all']);
    });

    testWidgets('it fits the narrowest phone', (tester) async {
      // Four labels across 320 points, "Add to album" the longest of them.
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(bar());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
