// The veil, before and after — because "not visible properly" is something to
// be looked at, not reasoned about.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/theme.dart';

const _out =
    r'C:\Users\Pro-TEAM\AppData\Local\Temp\claude\d--AI-TUBE\4dda9227-6269-4d42-aac1-051ae3b25e79\scratchpad';

Future<void> _useRealFont() async {
  for (final path in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\arial.ttf']) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    for (final family in ['Roboto', 'packages/safenest/Roboto', '.SF UI Text']) {
      await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
    }
    return;
  }
}

/// Stands in for a photograph: a dark one, which is the case that broke.
Widget _photo() => const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2A1E), Color(0xFF3E5140), Color(0xFF12202B)],
        ),
      ),
    );

Widget _panel(String title, Color veil, double alpha, ThemeData t) => SizedBox(
      width: 300,
      height: 210,
      child: Stack(fit: StackFit.expand, children: [
        _photo(),
        ColoredBox(color: veil.withValues(alpha: alpha)),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('Good morning',
                style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
            Text('Welcome',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: t.colorScheme.onSurface)),
            const SizedBox(height: 10),
            Text('Nothing due right now — bills paid, tasks done.',
                style: TextStyle(fontSize: 12, height: 1.4, color: t.colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text('Snapshot',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: t.colorScheme.onSurface)),
          ]),
        ),
      ]),
    );

void main() {
  testWidgets('the veil, wrong way and right way', (tester) async {
    tester.view.physicalSize = const Size(640 * 2, 230 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await _useRealFont();

    final t = buildTheme(const Brand(), Brightness.light);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: t,
      home: RepaintBoundary(
        key: key,
        child: Row(children: [
          // What shipped: darkened toward black at the old default.
          _panel('DARKENED 45% — WHAT SHIPPED', Colors.black, 0.45, t),
          const SizedBox(width: 20),
          // What it is now: faded toward the page colour, at the new default.
          _panel('FADED TO THE PAGE 70% — NOW',
              t.colorScheme.surface, 0.70, t),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png != null && Directory(_out).existsSync()) {
        File('$_out/veil_compare.png').writeAsBytesSync(png.buffer.asUint8List());
      }
    });
  });
}
