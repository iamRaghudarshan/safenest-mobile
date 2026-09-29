// The bottom bar, at every width it actually ships into.
//
// Colourful defaults to five tabs, and the reason is written down in
// home_screen.dart: "Six is over the guidance on both platforms and it shows:
// at 390pt the labels have no room and the icons crowd."
//
// But a bar somebody customised is kept across skins — deliberately, so that
// choosing a theme never silently rearranges a bar they arranged. Which means
// SIX tabs in the floating bar is not a hypothetical, it is what an existing
// install gets, and it had never been drawn.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/customize.dart';
import 'package:safenest/offline/mode.dart';
import 'package:safenest/offline/records.dart';
import 'package:safenest/offline/store.dart';
import 'package:safenest/offline/sync.dart';
import 'package:safenest/screens/home_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

import 'nav_finder.dart';

const _out =
    r'C:\Users\Pro-TEAM\AppData\Local\Temp\claude\d--AI-TUBE\4dda9227-6269-4d42-aac1-051ae3b25e79\scratchpad';

/// The six a long-standing install carries, which is the classic default.
const _six = ['home', 'modules', 'expenses', 'gallery', 'reminders', 'profile'];

Future<void> _useRealFont() async {
  for (final path in [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    for (final family in ['Roboto', 'packages/safenest/Roboto', '.SF UI Text']) {
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }
    return;
  }
}

void _mockPackageInfo() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => call.method == 'getAll'
              ? <String, dynamic>{
                  'appName': 'SafeNest',
                  'packageName': 'in.safenesthub.app',
                  'version': '1.81.0',
                  'buildNumber': '179',
                }
              : null);
}

Widget _shell(AppSkin skin) {
  final session = Session();
  final store = OfflineStore();
  final mode = OfflineMode();
  final records = OfflineRecords(store: store, mode: mode);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<Session>.value(value: session),
      Provider<OfflineStore>.value(value: store),
      ChangeNotifierProvider<OfflineMode>.value(value: mode),
      Provider<OfflineRecords>.value(value: records),
      ChangeNotifierProvider<SyncService>.value(
          value: SyncService(
              store: store, api: () => session.api, records: records)),
    ],
    child: MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light, skin: skin),
      home: const HomeScreen(brand: Brand()),
    ),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockPackageInfo();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // 320 is the narrowest phone still in use (an iPhone SE, 1st generation);
  // 390 is the common one; 360 is most Androids, including the one this is
  // reported from.
  for (final width in [320.0, 360.0, 390.0]) {
    testWidgets('six tabs fit at ${width.toInt()}pt', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Customize.ensureLoaded();
      await Customize.setNavBar(_six);
      await Customize.setSkin(Customize.skinVivid);

      tester.view.physicalSize = Size(width * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _useRealFont();

      await tester.pumpWidget(_shell(AppSkin.vivid));
      await tester.pump(const Duration(milliseconds: 400));

      // AN OVERFLOW IS THE FAILURE. A bar too narrow for its contents paints a
      // yellow-and-black stripe across the one element on every screen.
      expect(tester.takeException(), isNull,
          reason: 'the bar overflowed at ${width.toInt()}pt with six tabs');

      final keys = navItemKeys(tester);
      expect(keys.length, 6, reason: 'the customised bar was not kept');

      // And every label has to be READABLE, not merely present. A label
      // clipped to "Remind…" is what "the bottom menu is not proper" means.
      for (final k in keys) {
        final label = find.descendant(of: find.byKey(k), matching: find.byType(Text));
        expect(label, findsOneWidget);
        final w = tester.getSize(label).width;
        expect(w, greaterThan(24),
            reason: 'a tab label has only ${w.toStringAsFixed(0)}pt to show in '
                'at ${width.toInt()}pt');
      }
    });
  }

  group('the sizing rule itself', () {
    // The bar's inner width is the screen less a 16pt margin each side and
    // 4pt of padding each side, so a cell is (w - 40) / tabs.
    double cell(double width, int tabs) => (width - 40) / tabs;

    test('five tabs on a normal phone are exactly as they were', () {
      // The rule must not have quietly restyled the default bar while fixing
      // the crowded one. 46 is the number that shipped.
      expect(navGlyphFor(cell(390, 5), selected: true), 46.0);
      expect(navGlyphFor(cell(390, 5), selected: false), 40.0);
      expect(navLabelFor(cell(390, 5)), 10.0);
    });

    test('six tabs give up some size rather than some air', () {
      final c = cell(390, 6);
      expect(c, lessThan(60), reason: 'six at 390pt is a tight cell');
      final g = navGlyphFor(c, selected: true);
      expect(g, lessThan(46.0));
      // Whatever it shrinks to, there has to be real space between chips.
      expect(c - g, greaterThan(16),
          reason: 'only ${(c - g).toStringAsFixed(0)}pt between chips');
    });

    test('it never shrinks past legible', () {
      // A 320pt phone with six tabs is the worst case that exists. Small is
      // acceptable there; invisible is not.
      expect(navGlyphFor(cell(320, 6), selected: true), greaterThanOrEqualTo(32));
      expect(navGlyphFor(0, selected: true), greaterThanOrEqualTo(32));
    });

    test('and never grows past the design on a tablet', () {
      // A wide screen would otherwise hand each tab 200pt and draw six
      // enormous chips.
      expect(navGlyphFor(cell(1024, 5), selected: true), 46.0);
    });
  });

  group('how far off the bottom it floats', () {
    // A SafeArea plus a 12pt margin put 46pt of empty page under the bar on an
    // iPhone, which reads as stranded rather than resting near the edge. But
    // the bottom of that inset is where the home indicator and the gesture
    // strip live, so the bar cannot simply sit on the glass either.
    Future<double> gapAt(WidgetTester tester, double inset) async {
      SharedPreferences.setMockInitialValues({});
      await Customize.ensureLoaded();
      await Customize.setNavBar(_six);
      await Customize.setSkin(Customize.skinVivid);

      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          devicePixelRatio: 3,
          padding: EdgeInsets.only(bottom: inset),
          viewPadding: EdgeInsets.only(bottom: inset),
        ),
        child: _shell(AppSkin.vivid),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      // The bar is the box that holds the tabs.
      final bar = find.ancestor(
          of: navItemAt(tester, 0), matching: find.byType(Container)).last;
      return 844 - tester.getBottomLeft(bar).dy;
    }

    testWidgets('an iPhone: close to the edge, clear of the indicator',
        (tester) async {
      final gap = await gapAt(tester, 34);
      expect(gap, lessThan(30),
          reason: 'still ${gap.toStringAsFixed(0)}pt of empty page below it');
      expect(gap, greaterThanOrEqualTo(8),
          reason: 'the home indicator needs room');
    });

    testWidgets('an Android on gestures', (tester) async {
      final gap = await gapAt(tester, 24);
      expect(gap, lessThan(24));
      expect(gap, greaterThanOrEqualTo(8));
    });

    testWidgets('and a phone that reports no inset at all', (tester) async {
      // Zero here would weld the bar to the glass and lose the point of
      // floating it.
      final gap = await gapAt(tester, 0);
      expect(gap, greaterThanOrEqualTo(8));
    });
  });

  testWidgets('and it is drawn, so it can be judged', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Customize.ensureLoaded();
    await Customize.setNavBar(_six);
    await Customize.setSkin(Customize.skinVivid);

    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _useRealFont();

    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          devicePixelRatio: 3,
          padding: EdgeInsets.only(top: 47, bottom: 34),
          viewPadding: EdgeInsets.only(top: 47, bottom: 34),
        ),
        child: _shell(AppSkin.vivid),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png != null && Directory(_out).existsSync()) {
        File('$_out/navbar_six.png').writeAsBytesSync(png.buffer.asUint8List());
      }
    });
  });
}
