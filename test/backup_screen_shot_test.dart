// Photograph the backup screen so it can be judged rather than imagined.
//
// The screen cannot be run on a device from here — no Android SDK, no Xcode —
// and it is the screen the owner looks at longest. `debugProgress` exists
// precisely so a state can be rendered without a photo library or a server, so
// there is no excuse for designing it blind.
//
// Writes PNGs beside the code rather than asserting against goldens: the point
// is to LOOK at it while designing, not to fail a build when a pixel moves.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safenest/backup.dart';
import 'package:safenest/screens/backup_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

/// Load a REAL font before rendering.
///
/// `flutter test` ships no font, so every string draws as a filled black
/// rectangle — which makes a screenshot useless for judging a design, and is
/// exactly what happened the first time these were shown to somebody. Loading
/// a system face under the family the theme asks for makes the render show
/// what the phone will show.
Future<void> _useRealFont() async {
  for (final path in [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    for (final family in ['Roboto', 'packages/safenest/Roboto', '.SF UI Text']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    return;
  }
}

const _out =
    r'C:\Users\Pro-TEAM\AppData\Local\Temp\claude\d--AI-TUBE\4dda9227-6269-4d42-aac1-051ae3b25e79\scratchpad';

Future<void> _shoot(WidgetTester tester, BackupProgress p, String name,
    {Brightness mode = Brightness.light}) async {
  // A real phone, not a desktop: this screen lives on a 390pt viewport and
  // judging it at 800 would flatter it.
  // A REAL phone. 1000pt is taller than any of them and flatters the layout;
  // an iPhone 14 is 844 and that is what "fits without scrolling" has to mean.
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // The auto-backup card reads preferences, and a test has no plugin behind
  // them — which threw before anything was painted and left two of these
  // three states unrendered. Unrendered is unseen, and unseen is how a layout
  // ships broken.
  SharedPreferences.setMockInitialValues({});
  await _useRealFont();
  final key = GlobalKey();
  await tester.pumpWidget(ChangeNotifierProvider<Session>(
    create: (_) => Session(),
    child: MaterialApp(
      theme: buildTheme(const Brand(), mode),
      home: RepaintBoundary(key: key, child: BackupScreen(debugProgress: p)),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 600));

  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await b.toImage(pixelRatio: 2);
    final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) return;
    try {
      if (Directory(_out).existsSync()) {
        File('$_out\\$name').writeAsBytesSync(png.buffer.asUint8List());
      }
    } catch (_) {}
  });
}

/// How far the page could be scrolled. Zero means it fits.
double _scrollExtent(WidgetTester tester) {
  final sc = tester.widgetList<Scrollable>(find.byType(Scrollable)).first;
  final pos = sc.controller?.position;
  if (pos != null) return pos.maxScrollExtent;
  final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
  return state.position.maxScrollExtent;
}

void main() {
  testWidgets('idle — before anything has been backed up', (tester) async {
    await _shoot(tester, const BackupProgress(), 'backup_idle.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('running — the state people watch', (tester) async {
    await _shoot(
        tester,
        const BackupProgress(
          state: BackupState.running,
          total: 1048,
          done: 68,
          skipped: 900,
          message: 'Backing up…',
          currentLabel: 'IMG_4102.MOV',
          currentSent: 41943040,
          currentTotal: 96468992,
          inFlight: [
            BackupItem(
                id: 'a1',
                label: 'IMG_4102.MOV',
                isVideo: true,
                sent: 41943040,
                total: 96468992),
            BackupItem(
                id: 'a2',
                label: 'IMG_4103.HEIC',
                isVideo: false,
                sent: 900000,
                total: 2400000),
            BackupItem(
                id: 'a3', label: 'IMG_4104.HEIC', isVideo: false)
          ],
        ),
        'backup_running.png');
    expect(tester.takeException(), isNull);
    // THE WHOLE POINT: one page, nothing to scroll. Asserted rather than
    // eyeballed, because a screenshot taken at a generous height will always
    // look like it fits.
    expect(_scrollExtent(tester), 0.0,
        reason: 'the running screen must fit a 390x844 phone without scrolling');
  });

  testWidgets('scanning — the sentence that was being set as a number',
      (tester) async {
    // "Looking for your computer…" sits in the slot designed for "132
    // uploaded", and was inheriting its 34pt single line — so it rendered as
    // "Looking for your com…". Rendered here because it is the first thing
    // anybody sees after pressing the button.
    await _shoot(
        tester,
        const BackupProgress(
          state: BackupState.scanning,
          message: 'Looking for your computer…',
        ),
        'backup_scanning.png');
    expect(tester.takeException(), isNull);
    expect(find.text('Looking for your computer…'), findsOneWidget);
    expect(_scrollExtent(tester), 0.0);
  });

  testWidgets('done — everything went', (tester) async {
    // The state the hero was BLANK in until this change: the figures lived
    // inside `if (running)`, so a finished run left a big coloured block with
    // a drawing in it and no result anywhere near the top of the screen.
    await _shoot(
        tester,
        const BackupProgress(
          state: BackupState.done,
          total: 1048,
          done: 148,
          skipped: 900,
          message: 'Finished',
        ),
        'backup_done_clean.png');
    expect(tester.takeException(), isNull);
    expect(find.text('Backed up'), findsOneWidget);
    expect(find.text('148 uploaded'), findsOneWidget);
    expect(find.text('1,048 checked · 900 already there'), findsOneWidget);
    expect(_scrollExtent(tester), 0.0);
  });

  testWidgets('failed — the reason is the headline', (tester) async {
    // A failure has no figure worth enlarging, so the sentence takes the
    // hero's place and the message becomes the sub-line. Rendered because
    // that is a different layout from the other four, and an untested branch
    // of a layout is an untested layout.
    await _shoot(
        tester,
        const BackupProgress(
          state: BackupState.failed,
          total: 1048,
          message: 'Your session has expired. Sign in again and try once more.',
          reasons: {'the computer refused the upload': 12},
          retryable: 12,
        ),
        'backup_failed.png');
    expect(tester.takeException(), isNull);
    expect(find.text('That did not work'), findsOneWidget);
    expect(find.text('Nothing was sent'), findsOneWidget);
    // The reason, not the arithmetic — this is the one line that says what to
    // go and do.
    expect(
        find.text(
            'Your session has expired. Sign in again and try once more.'),
        findsOneWidget);
    expect(_scrollExtent(tester), 0.0);
  });

  testWidgets('done — with some that did not go', (tester) async {
    await _shoot(
        tester,
        const BackupProgress(
          state: BackupState.done,
          total: 1048,
          done: 132,
          skipped: 900,
          failed: 16,
          message: 'Finished',
          reasons: {'could not be downloaded from iCloud': 16},
          retryable: 16,
        ),
        'backup_done.png');
    expect(tester.takeException(), isNull);
    // The fullest state there is: counts, the reasons panel and two buttons.
    // If anything fits badly it is this one.
    expect(_scrollExtent(tester), 0.0,
        reason: 'the finished screen must fit a 390x844 phone without scrolling');
  });
}
