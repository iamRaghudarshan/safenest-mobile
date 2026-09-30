// The two new screens, drawn at a phone's width.
//
// Everything about these is visual — a dim that has to keep text readable, a
// row of shortcut tiles that has to fit six across 390pt. Neither is something
// the source can be read for.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safenest/customize.dart';
import 'package:safenest/screens/background_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

const _out =
    r'C:\Users\Pro-TEAM\AppData\Local\Temp\claude\d--AI-TUBE\4dda9227-6269-4d42-aac1-051ae3b25e79\scratchpad';

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

void main() {
  testWidgets('the background page, at a phone width', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Customize.ensureLoaded();
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _useRealFont();

    final key = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<Session>(
      create: (_) => Session(),
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: RepaintBoundary(
          key: key,
          // No camera roll in a test, so the strip is handed an empty list
          // rather than being left to ask the platform and hang.
          child: const BackgroundScreen(debugRecent: []),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // The dim control and its floor have to be ON the page — the sentence is
    // what stops somebody hunting for a setting that deliberately is not
    // there.
    expect(find.text('Dim it'), findsOneWidget);
    expect(find.textContaining('will not go below'), findsOneWidget);
    expect(find.text('Nature'), findsOneWidget);
    expect(find.text('Your photo'), findsOneWidget);

    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png != null && Directory(_out).existsSync()) {
        File('$_out/bg_screen.png').writeAsBytesSync(png.buffer.asUint8List());
      }
    });
  });

  testWidgets('a picture cannot be chosen before there is one', (tester) async {
    // The "Your photo" tile with nothing behind it would put the app on a
    // blank screen, so it is not selectable until a picture exists.
    SharedPreferences.setMockInitialValues({});
    await Customize.reloadForTest();
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider<Session>(
      create: (_) => Session(),
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light),
        home: const BackgroundScreen(debugRecent: []),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(Customize.backgroundImagePath, isEmpty);
    await tester.tap(find.text('Your photo'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(Customize.photoBackground, isFalse,
        reason: 'selecting it with no picture would blank the app');
  });
}
