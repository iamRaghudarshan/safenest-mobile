// Render the backup animation to a PNG so it can actually be LOOKED at.
//
// There is no Android SDK or Xcode on this machine, so nothing here can be run
// on a device — and this widget is pure drawing, where "it compiles" says
// almost nothing. Every visual problem in this project so far was found by the
// owner rather than by CI, and the reason is that nobody ever looked.
//
// A widget test can paint into an image and write it out. It costs nothing and
// turns "I reasoned about the geometry" into "here is what it draws".
//
// It writes into the scratchpad rather than asserting against a golden: the
// point is to see it while designing, not to fail a build when a pixel moves.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/theme.dart';
import 'package:safenest/widgets/backup_flight.dart';

/// Where the PNGs land. Absent or unwritable, the test still passes — it is a
/// design aid, not a gate.
const _out =
    r'C:\Users\Pro-TEAM\AppData\Local\Temp\claude\d--AI-TUBE\4dda9227-6269-4d42-aac1-051ae3b25e79\scratchpad';

Future<void> _shoot(WidgetTester tester, Brightness mode, String name) async {
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(const Brand(), mode),
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 360,
            child: BackupFlight(running: true),
          ),
        ),
      ),
    ),
  ));
  // Part-way through the loop, so the parcels are mid-flight rather than
  // stacked at one end.
  await tester.pump(const Duration(milliseconds: 900));

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 3);
    final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) return;
    try {
      final dir = Directory(_out);
      if (dir.existsSync()) {
        File('$_out\\$name').writeAsBytesSync(png.buffer.asUint8List());
      }
    } catch (_) {
      // A design aid that cannot write is not a reason to fail a test run.
    }
  });
}

void main() {
  testWidgets('draws in light mode', (tester) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _shoot(tester, Brightness.light, 'flight_light.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('draws in dark mode', (tester) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _shoot(tester, Brightness.dark, 'flight_dark.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stopped backup still draws the two devices', (tester) async {
    // It must not vanish when the run ends: the devices are the explanation of
    // where photos go, which is worth seeing on an idle screen too.
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: const Scaffold(body: BackupFlight(running: false)),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(BackupFlight), findsOneWidget);
  });
}
