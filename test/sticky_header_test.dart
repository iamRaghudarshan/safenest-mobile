// The sticky date header, and the two points that hid every photograph.
//
// `GalleryStickyHeader` declares a maxExtent of 46. Its content measured 44 —
// titleMedium's 24 plus _DayHeader's 11 above and 9 below — and that
// disagreement stopped the viewport laying out EVERY SLIVER AFTER IT. The photo
// grid came back with a null geometry, maxScrollExtent collapsed to zero, and
// no exception was thrown anywhere, so the Gallery drew its header and not one
// photograph while looking, from the outside, like a rendering fault.
//
// THE ASSERTION THAT MATTERS is the second group: that a grid placed after this
// header actually lays out. A test that only measured the header would have
// passed throughout the entire defect, because the header was always fine — it
// was everything downstream that vanished.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/screens/gallery_screen.dart';
import 'package:safenest/theme.dart';

GalleryStickyHeader _header({bool monthOnly = true, bool allSelected = false}) =>
    GalleryStickyHeader(
      day: DateTime(2026, 10),
      monthOnly: monthOnly,
      allSelected: allSelected,
      onToggle: () {},
    );

Widget _scroller({required int tiles, double viewport = 600}) => MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: viewport,
          child: CustomScrollView(slivers: [
            // Something ahead of it, as on the real screen.
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
            SliverPersistentHeader(pinned: true, delegate: _header()),
            SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5, mainAxisSpacing: 2, crossAxisSpacing: 2),
              delegate: SliverChildBuilderDelegate(
                (_, i) => ColoredBox(
                    color: Colors.primaries[i % Colors.primaries.length],
                    child: Text('$i')),
                childCount: tiles,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        ),
      ),
    );

/// The grid's geometry, read from the live render tree. Nothing else proves
/// the point: the tiles can be built and correctly sized while the sliver is
/// given no paint extent at all, which is exactly what happened.
SliverGeometry? _gridGeometry(WidgetTester tester) {
  SliverGeometry? found;
  void walk(RenderObject o) {
    if (o is RenderSliverGrid) found ??= o.geometry;
    o.visitChildren(walk);
  }

  walk(tester.renderObject(find.byType(CustomScrollView)));
  return found;
}

void main() {
  group('the header itself', () {
    testWidgets('its content fills the extent it declares', (tester) async {
      // The rule the fix encodes. 44 against a declared 46 is what broke it,
      // and the arithmetic that produced 44 is three separate numbers in two
      // files — so it is pinned here rather than left to agree by accident.
      await tester.pumpWidget(_scroller(tiles: 25));
      await tester.pumpAndSettle();

      final d = _header();
      expect(d.maxExtent, d.minExtent,
          reason: 'this header does not shrink; both must agree');

      // Measured from the Material the header draws, which is the thing whose
      // height was 44. `find.byType(Material)` also matches the MaterialApp's
      // own, so this takes the one inside the header.
      final inside = find.descendant(
          of: find.byType(SliverPersistentHeader),
          matching: find.byType(Material));
      expect(inside, findsWidgets);
      expect(tester.getSize(inside.last).height, d.maxExtent,
          reason: 'the built content must be exactly the declared extent, '
              'not the 44 its text and padding happen to add up to');
    });

    testWidgets('it still draws its label and its select circle',
        (tester) async {
      await tester.pumpWidget(_scroller(tiles: 5));
      await tester.pumpAndSettle();
      expect(find.text('October'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    });

    testWidgets('and shows it is fully selected when it is', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: Scaffold(
          body: CustomScrollView(slivers: [
            SliverPersistentHeader(
                pinned: true, delegate: _header(allSelected: true)),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  group('what the header must not do to the slivers after it', () {
    testWidgets('a grid below it is laid out and painted', (tester) async {
      // THE REGRESSION. With the two-point mismatch this grid came back with a
      // null geometry and nothing on screen.
      await tester.pumpWidget(_scroller(tiles: 25));
      await tester.pumpAndSettle();

      final g = _gridGeometry(tester);
      expect(g, isNotNull,
          reason: 'a null geometry means the viewport never laid the grid out');
      expect(g!.scrollExtent, greaterThan(0));
      expect(g.paintExtent, greaterThan(0),
          reason: 'laid out but never painted is the exact defect');
      expect(find.text('0'), findsOneWidget, reason: 'the first tile is drawn');
    });

    testWidgets('and the view can still be scrolled to reach it',
        (tester) async {
      // maxScrollExtent collapsed to zero while the defect was live, so the
      // grid could not even be reached. A short viewport forces real scrolling.
      await tester.pumpWidget(_scroller(tiles: 60, viewport: 300));
      await tester.pumpAndSettle();

      final position =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(position.maxScrollExtent, greaterThan(0),
          reason: 'zero here means everything below the header vanished');
    });

    testWidgets('the sliver after the grid is laid out too', (tester) async {
      // It was not: the trailing spacer came back null as well, which is how
      // "the header stops the viewport" was distinguished from "the grid is
      // broken".
      await tester.pumpWidget(_scroller(tiles: 10));
      await tester.pumpAndSettle();

      var lastPainted = 0.0;
      void walk(RenderObject o) {
        if (o is RenderSliver) {
          final g = o.geometry;
          if (g != null) lastPainted = g.paintExtent;
        }
        o.visitChildren(walk);
      }

      walk(tester.renderObject(find.byType(CustomScrollView)));
      expect(lastPainted, greaterThan(0));
    });
  });
}
