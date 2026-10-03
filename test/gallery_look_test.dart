// The look the owner asked for, from a reference they sent.
//
// Three things carry it, and each is easy to undo by accident later:
//
//   * The icon tile's shadow is in the TILE'S OWN HUE. A grey shadow under a
//     blue square reads as a sticker on paper; a coloured one reads as a lit
//     object, and that is most of the difference between the grid as it was and
//     the reference.
//   * The storage panel never shows a figure it has not got. An empty bar at
//     zero reads as "nothing is backed up", which is the most alarming possible
//     wrong answer on that screen.
//   * And it gets out of the way the moment anything is filtered: a storage
//     figure above a set of search results answers a question nobody asked.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/theme.dart';
import 'package:safenest/widgets/backed_up_grid.dart';
import 'package:safenest/widgets/module_tile.dart';
import 'package:safenest/widgets/storage_hero.dart';

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildTheme(const Brand(), brightness),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('the icon tile', () {
    test('the gradient is two steps of the module own colour', () {
      // Derived, never a second table. kModuleColours already holds one colour
      // per module and a parallel list is one more place for a new module to be
      // forgotten — which this codebase has a documented history of.
      final (light, deep) = gradientFor(const Color(0xFF3B82F6));
      expect(HSLColor.fromColor(light).lightness,
          greaterThan(HSLColor.fromColor(deep).lightness));
      expect(HSLColor.fromColor(light).hue,
          closeTo(HSLColor.fromColor(deep).hue, 1.0),
          reason: 'the two ends must be the same colour, not two colours');
    });

    test('a very light module colour still yields a readable tile', () {
      // Unclamped, a pale module would give a near-white tile and a white glyph
      // nobody can read.
      // The tolerance is not slack: a colour makes the round trip through
      // eight bits per channel, so a lightness clamped to exactly 0.78 reads
      // back as 0.7804. Asserting the bound to the last decimal would be
      // asserting the rounding, not the clamp.
      final (light, deep) = gradientFor(const Color(0xFFFFF4C2));
      expect(HSLColor.fromColor(light).lightness, lessThan(0.79));
      expect(HSLColor.fromColor(deep).lightness, lessThan(0.61));
    });

    test('a very dark one still has a gradient at all', () {
      final (light, deep) = gradientFor(const Color(0xFF07110A));
      expect(HSLColor.fromColor(light).lightness,
          greaterThan(HSLColor.fromColor(deep).lightness));
    });

    testWidgets('the shadow is the tile colour, never grey', (tester) async {
      await tester.pumpWidget(_app(const ModuleTile(
        icon: Icons.photo_library_outlined,
        colour: Color(0xFF1668DC),
        label: 'Gallery',
        count: '1,780',
      )));
      await tester.pumpAndSettle();

      final box = tester.widget<Container>(find.descendant(
          of: find.byType(ModuleTile),
          matching: find.byType(Container))).decoration as BoxDecoration;
      final shadow = box.boxShadow!.single.color;
      // A grey has no saturation. This one must.
      expect(HSLColor.fromColor(shadow).saturation, greaterThan(0.25),
          reason: 'a grey shadow is what made the old tiles look flat');
    });

    testWidgets('it shows its count, and reads it out', (tester) async {
      // Without the handle the semantics tree is never built and
      // bySemanticsLabel finds nothing — which looks exactly like a missing
      // label.
      // Disposed inline rather than through addTearDown, which runs after the
      // framework's own end-of-test check and so reports a leak either way.
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(const ModuleTile(
        icon: Icons.photo_library_outlined,
        colour: Color(0xFF1668DC),
        label: 'Gallery',
        count: '1,780',
      )));
      await tester.pumpAndSettle();

      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('1,780'), findsOneWidget);
      expect(find.bySemanticsLabel('Gallery, 1,780'), findsOneWidget);
      // And as ONE node: the name and count must not also be read separately.
      expect(find.bySemanticsLabel('Gallery'), findsNothing);
      semantics.dispose();
    });
  });

  group('what is backed up', () {
    List<BackedUp> six({int? count = 12}) => [
          for (final n in ['Photos', 'Videos', 'Documents', 'People', 'Places',
            'Albums'])
            BackedUp(
                key: n.toLowerCase(),
                label: n,
                icon: Icons.photo_library_outlined,
                colour: const Color(0xFF1668DC),
                count: count),
        ];

    testWidgets('all six tiles are drawn with their counts', (tester) async {
      await tester.pumpWidget(_app(BackedUpGrid(items: six())));
      await tester.pumpAndSettle();

      expect(find.text('What is backed up'), findsOneWidget);
      expect(find.byType(ModuleTile), findsNWidgets(6));
      expect(find.text('12'), findsNWidgets(6));
    });

    testWidgets('zero is shown as zero, not as a blank', (tester) async {
      // Zero photos is a fact about the backup; a blank is a fact about the
      // app, and the two must not look the same.
      await tester.pumpWidget(_app(BackedUpGrid(items: six(count: 0))));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsNWidgets(6));
    });

    testWidgets('a figure still loading is dimmed rather than silent',
        (tester) async {
      await tester.pumpWidget(_app(BackedUpGrid(items: six(count: null))));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsNothing);
      expect(tester.widgetList<Opacity>(find.byType(Opacity)).first.opacity,
          lessThan(1.0));
    });

    testWidgets('a lakh is grouped the Indian way', (tester) async {
      await tester.pumpWidget(_app(BackedUpGrid(items: [
        BackedUp(
            key: 'photos',
            label: 'Photos',
            icon: Icons.photo_library_outlined,
            colour: const Color(0xFF1668DC),
            count: 124500),
      ])));
      await tester.pumpAndSettle();
      expect(find.text('1,24,500'), findsOneWidget);
      expect(find.text('124,500'), findsNothing);
    });

    testWidgets('nothing to show draws nothing', (tester) async {
      await tester.pumpWidget(_app(const BackedUpGrid(items: [])));
      await tester.pumpAndSettle();
      expect(find.byType(ModuleTile), findsNothing);
    });
  });

  group('the storage panel', () {
    testWidgets('it leads with the number', (tester) async {
      await tester.pumpWidget(_app(const StorageHero(
        usedBytes: 158 * 1024 * 1024 * 1024,
        freeBytes: 342 * 1024 * 1024 * 1024,
        caption: '1,780 photos · 75 videos',
      )));
      await tester.pumpAndSettle();

      expect(find.text('158 GB'), findsOneWidget);
      expect(find.text('of 500 GB'), findsOneWidget);
      expect(find.textContaining('1,780 photos'), findsOneWidget);
      expect(find.text('Used 32%'), findsOneWidget);
      expect(find.text('Free 68%'), findsOneWidget);
    });

    testWidgets('with no free figure there is no bar and no invented total',
        (tester) async {
      // Only an admin is told what is left on the drive. Everybody else must
      // see the used figure alone rather than a bar against a number the app
      // made up.
      await tester.pumpWidget(_app(const StorageHero(
        usedBytes: 4 * 1024 * 1024 * 1024,
        freeBytes: 0,
        caption: '',
      )));
      await tester.pumpAndSettle();

      expect(find.text('4.0 GB'), findsOneWidget);
      expect(find.textContaining('of '), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a nearly full disk says so, and says it plainly',
        (tester) async {
      // The one time this number needs acting on. A bar that only ever
      // decorates is a bar nobody reads when it matters.
      await tester.pumpWidget(_app(const StorageHero(
        usedBytes: 96 * 1024 * 1024 * 1024,
        freeBytes: 2 * 1024 * 1024 * 1024,
        caption: '',
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('nearly full'), findsOneWidget);
      expect(find.textContaining('will start failing'), findsOneWidget);
    });

    testWidgets('a stale figure admits it rather than lying quietly',
        (tester) async {
      await tester.pumpWidget(_app(const StorageHero(
        usedBytes: 12 * 1024 * 1024 * 1024,
        freeBytes: 0,
        caption: '',
        unreachable: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('LAST SEEN ON YOUR COMPUTER'), findsOneWidget);
    });

    testWidgets('while loading it shows a spinner, not a zero', (tester) async {
      // "0 B on your computer" is the most alarming possible wrong answer on
      // this screen.
      await tester.pumpWidget(_app(const StorageHero(
        usedBytes: 0, freeBytes: 0, caption: '', loading: true,
      )));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('0 B'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a huge figure shrinks rather than overflowing', (tester) async {
      // The test font draws every glyph as a full-size square, so this is a
      // harsher row than any real one — which is the point. The headline must
      // give way rather than paint over its own edge.
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(const StorageHero(
        usedBytes: 1580 * 1024 * 1024 * 1024,
        freeBytes: 420 * 1024 * 1024 * 1024,
        caption: '1,24,500 photos · 1,075 videos · 2,171 documents',
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('and in the dark', (tester) async {
      await tester.pumpWidget(_app(
        const StorageHero(
            usedBytes: 158 * 1024 * 1024 * 1024,
            freeBytes: 342 * 1024 * 1024 * 1024,
            caption: 'some photos'),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('158 GB'), findsOneWidget);
    });
  });
}
