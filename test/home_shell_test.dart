// The app SHELL — the thing every screen sits inside, and the thing nothing
// tested.
//
// Every test in this repository renders one screen on its own. That misses an
// entire class of defect, and one of them shipped: Home came up blank with the
// bottom bar floating in the middle of the screen. No screen rendered in
// isolation shows that, because the fault is in how the shell assembles them.
//
// What this pins is deliberately crude and hard to break: the bar is at the
// BOTTOM, the tabs are the right ones for the skin, and the body actually
// occupies the space above the bar.
import 'package:flutter/material.dart';
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

/// EVERY provider main.dart supplies, not just the one a screen happened to
/// need. A shell test that mounts real screens has to stand them up the way
/// the app does — with Session alone, PhotosHome threw ProviderNotFound, the
/// IndexedStack collapsed to nothing, and the harness produced the very
/// symptom it was written to catch. A test that fails for its own reasons is
/// worse than no test: it sends you looking for a bug that is not there.
/// The real app does not hand `HomeScreen` straight to `MaterialApp.home`. It
/// puts a backdrop behind everything through `MaterialApp.builder` — a Stack
/// with the wallpaper filling it and the app laid over the top — because every
/// Scaffold in the Classic skin is transparent and something has to be behind
/// them. A shell test that skips that layer is testing a tree the phone never
/// builds, and the constraints a Stack hands its children are exactly the kind
/// of thing that turned out to matter here.
Widget _withBackdrop(BuildContext context, Widget? child) => Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: Theme.of(context).colorScheme.surface),
        ),
        if (child != null) Positioned.fill(child: child),
      ],
    );

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
      builder: _withBackdrop,
      home: const HomeScreen(brand: Brand()),
    ),
  );
}

/// The Profile tab asks `package_info_plus` for the version the moment it is
/// built, and an IndexedStack builds every tab at once — so a shell test always
/// hits it. There is no plugin off-device, and the exception it throws lands in
/// the middle of the test rather than in Profile, which reads like a fault in
/// whatever was being measured.
void _mockPackageInfo() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async {
    if (call.method != 'getAll') return null;
    return <String, dynamic>{
      'appName': 'SafeNest',
      'packageName': 'in.safenesthub.app',
      'version': '1.75.0',
      'buildNumber': '176',
    };
  });
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockPackageInfo();
    // The offline store opens a real database the moment it is constructed,
    // and `sqflite` has no implementation off-device. Without this the store
    // throws, the screen above it never builds, and the shell collapses —
    // which looks exactly like the defect this file exists to catch.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Customize.ensureLoaded();
  });

  for (final skin in AppSkin.values) {
    testWidgets('${skin.name}: the bar sits at the bottom, not adrift',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell(skin));
      await tester.pump(const Duration(milliseconds: 400));

      final scaffold = find.byType(Scaffold).first;
      final screenBottom = tester.getBottomLeft(scaffold).dy;

      // The bar is whatever holds the tab labels. Home is in every bar, in
      // both skins, and it is the one tab that cannot be customised away.
      final home = find.text('Home');
      expect(home, findsWidgets, reason: 'the bar did not render at all');
      final barY = tester.getTopLeft(home.first).dy;

      // THE BUG THAT SHIPPED: the bar floated near the middle. It must live in
      // the bottom quarter of the screen — a generous bound, so this fails
      // only when something is genuinely adrift.
      expect(barY, greaterThan(screenBottom * 0.72),
          reason: 'the bottom bar is at ${barY.toStringAsFixed(0)} on an '
              '${screenBottom.toStringAsFixed(0)}pt screen — it is floating, '
              'not sitting at the bottom');
    });

    testWidgets('${skin.name}: the body fills the space above the bar',
        (tester) async {
      // A blank page under a bar is the other half of what shipped. Something
      // of the screen has to be painted in the top half.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell(skin));
      await tester.pump(const Duration(milliseconds: 400));

      final indexed = find.byType(IndexedStack);
      expect(indexed, findsWidgets,
          reason: 'the tab host is missing, so no screen can be shown');
      final size = tester.getSize(indexed.first);
      expect(size.height, greaterThan(300),
          reason: 'the body is ${size.height.toStringAsFixed(0)}pt tall — the '
              'screens have nowhere to draw');
    });
  }

  for (final skin in AppSkin.values) {
    testWidgets('${skin.name}: every tab draws something, not just the first',
        (tester) async {
      // Home was the tab that was reported blank, so Home is the tab that got
      // checked. That is not the same as the shell being right: an IndexedStack
      // builds all of them, they each sit in the same body, and a fault in how
      // one of them fills that body is invisible until it is the selected one.
      // Tap through the whole bar.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell(skin));
      await tester.pump(const Duration(milliseconds: 400));

      final stack = find.byType(IndexedStack).first;
      final count = tester.widget<IndexedStack>(stack).children.length;
      expect(count, greaterThanOrEqualTo(5), reason: 'the bar lost its tabs');

      for (var i = 0; i < count; i++) {
        // Tap the tab by its position in the bar rather than by label, so this
        // does not have to know which tabs a skin ships.
        await tester.tap(navItemAt(tester, i));
        await tester.pump(const Duration(milliseconds: 400));

        // PROVE THE TAP LANDED. Without this the loop can miss the bar
        // entirely, keep showing tab 0, and pass every assertion below it —
        // which is a test that reports five tabs checked and has checked one.
        expect(tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
            i,
            reason: 'tapping bar item $i did not select tab $i');

        // The body still has to be the body: full height, under the bar.
        final size = tester.getSize(find.byType(IndexedStack).first);
        expect(size.height, greaterThan(300),
            reason: 'tab $i collapsed the body to '
                '${size.height.toStringAsFixed(0)}pt');

        // And something has to be PAINTED in it — a tab that builds but draws
        // nothing is the same blank page to whoever is holding the phone.
        final drawn = find
            .descendant(of: stack, matching: find.byType(Text))
            .evaluate()
            .length;
        expect(drawn, greaterThan(0),
            reason: 'tab $i rendered no text at all — a blank page');
      }
    });
  }

  testWidgets('the bar survives somebody who has asked for larger text',
      (tester) async {
    // The floating bar is a FIXED height, which is what keeps it from resizing
    // as the selected glyph animates. The cost of a fixed height is that the
    // label can outgrow it, and an overflow on a phone is a yellow-and-black
    // stripe across the one element on every screen.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: _shell(AppSkin.vivid),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull,
        reason: 'the bar overflowed at a large text scale');
  });

  testWidgets('each skin ships its own default bar', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_shell(AppSkin.vivid));
    await tester.pump(const Duration(milliseconds: 300));
    // Five in Colourful: Home, Photos, Search, Files, Profile.
    expect(find.text('Search'), findsWidgets,
        reason: 'Colourful puts Search in the bar');
    expect(find.text('Expenses'), findsNothing,
        reason: 'Colourful does not; money is one tap away on Modules');
  });
}
