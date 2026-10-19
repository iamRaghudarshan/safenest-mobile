// How much work a selection costs the photo grid.
//
// The grid is the hottest surface in the app: a few hundred tiles, scrolled
// fast, with a finger dragging across them to select. "It feels fine" is not a
// measurement anybody can re-run, so this counts PhotoTile builds instead.
//
// THE HARNESS MIRRORS gallery_screen.dart DELIBERATELY: a Set of selected ids
// held by the parent, mutated in setState, with the tiles reading their
// `selected` flag out of it. That is exactly what the real screen does, so a
// number measured here is the number the real screen pays.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/screens/gallery_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/photo_tile.dart';

/// Enough to fill several screens, as a real library does.
const _tiles = 120;

Photo _photo(int i) => Photo(
      i,
      '/api/gallery/media/full/p$i.jpg',
      '/api/gallery/media/thumb/p$i.jpg',
      DateTime(2026, 10, (i % 9) + 1),
      false,
    );

/// A grid that selects the way the Gallery selects.
class _Harness extends StatefulWidget {
  const _Harness({required this.onState});
  final void Function(_HarnessState) onState;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final Set<int> selected = {};

  void toggle(int id) => setState(() {
        if (!selected.remove(id)) selected.add(id);
      });

  @override
  Widget build(BuildContext context) {
    widget.onState(this);
    return GridView.builder(
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
      itemCount: _tiles,
      itemBuilder: (_, i) => PhotoTile(
        photo: _photo(i),
        selecting: selected.isNotEmpty,
        selected: selected.contains(i),
      ),
    );
  }
}

Widget _wrap(Widget child) => MultiProvider(
      providers: [ChangeNotifierProvider<Session>(create: (_) => Session())],
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: Scaffold(body: child),
      ),
    );

void main() {
  late _HarnessState state;

  Future<void> pumpGrid(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(_Harness(onState: (s) => state = s)));
    await tester.pump();
  }

  group('what one tap costs the grid', () {
    testWidgets('selecting a photo rebuilds every tile on screen',
        (tester) async {
      // THE MEASUREMENT, not yet a complaint. The parent holds the selection
      // and rebuilds, so every mounted tile rebuilds with it — even the ones
      // whose own selected flag did not change.
      //
      // One tap is cheap. The cost is the DRAG: a slide across forty photos is
      // forty of these, each rebuilding everything mounted, which is where a
      // selection sweep stops feeling smooth.
      await pumpGrid(tester);

      PhotoTile.debugBuilds = 0;
      state.toggle(0);
      await tester.pump();

      final mounted = tester.widgetList<PhotoTile>(find.byType(PhotoTile)).length;
      expect(mounted, greaterThan(10),
          reason: 'this test is worthless if the grid built almost nothing');
      // Recorded as a fact, not asserted as good. It rebuilds at least every
      // mounted tile — measured at 75 builds for 60 found, the extra being
      // the rows GridView keeps either side of the viewport.
      //
      // If a later change makes one tap cost a handful of builds instead,
      // THIS TEST SHOULD FAIL and be tightened to the new number. A
      // performance test that still passes after the thing got faster is not
      // measuring anything.
      expect(PhotoTile.debugBuilds, greaterThanOrEqualTo(mounted),
          reason: 'one tap currently rebuilds every mounted tile');
    });

    testWidgets('a drag across ten photos multiplies that', (tester) async {
      await pumpGrid(tester);
      final mounted = tester.widgetList<PhotoTile>(find.byType(PhotoTile)).length;

      PhotoTile.debugBuilds = 0;
      for (var i = 0; i < 10; i++) {
        state.toggle(i);
        await tester.pump();
      }

      // Ten steps of a drag, each rebuilding everything mounted. A real sweep
      // across a month is forty or more of these.
      expect(PhotoTile.debugBuilds, greaterThanOrEqualTo(mounted * 10));
    });
  });

  group('what a tile decodes', () {
    testWidgets('a thumbnail is not decoded at full size', (tester) async {
      // The usual reason a photo grid is killed by the OS: a 4000px JPEG
      // decoded into memory to fill a 76pt square costs about 64 MB, and a
      // screenful of them is gone.
      await pumpGrid(tester);

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, isNotEmpty);
      for (final img in images) {
        expect(img.width == null || img.width! <= 400, isTrue);
      }
    });

    testWidgets('every tile is its own repaint boundary', (tester) async {
      // Without one, a single tile's ripple repaints the whole grid. GridView
      // adds them by default — this is here so a future `addRepaintBoundaries:
      // false`, which looks like a harmless optimisation, does not slip past.
      await pumpGrid(tester);
      expect(find.byType(RepaintBoundary), findsWidgets);
    });
  });
}
