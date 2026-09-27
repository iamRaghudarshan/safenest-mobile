// Photographs of the Colourful skin's own pieces.
//
// The phone cannot be run here, so anything not rendered ships unseen — and
// every visual bug in this project so far was found by the owner rather than
// by CI. These write PNGs beside the code so the redesign can be LOOKED at.
//
// Widgets rather than whole screens: the screens need a server and a photo
// library, and a fake of either would be a picture of the fake.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/theme.dart';
import 'package:safenest/widgets/file_kinds.dart';
import 'package:safenest/widgets/people_strip.dart';
import 'package:safenest/widgets/skin_picker.dart';

const _out =
    r'C:\Users\Pro-TEAM\AppData\Local\Temp\claude\d--AI-TUBE\4dda9227-6269-4d42-aac1-051ae3b25e79\scratchpad';

Future<void> _font() async {
  for (final p in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\arial.ttf']) {
    final f = File(p);
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    for (final fam in ['Roboto', 'packages/safenest/Roboto', '.SF UI Text']) {
      await (FontLoader(fam)..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }
    return;
  }
}

Future<void> _shoot(WidgetTester tester, String name, Widget child,
    {AppSkin skin = AppSkin.vivid, double width = 390}) async {
  tester.view.physicalSize = Size(width * 3, 400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await _font();
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(const Brand(), Brightness.light, skin: skin),
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 3);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (png != null && Directory(_out).existsSync()) {
      File('$_out\\$name').writeAsBytesSync(png.buffer.asUint8List());
    }
  });
}

void main() {
  testWidgets('the theme picker', (tester) async {
    await _shoot(
      tester,
      'skin_picker.png',
      const Padding(
        padding: EdgeInsets.all(14),
        child: SkinPicker(brand: Brand()),
      ),
      // Drawn under CLASSIC, which is where somebody actually meets it: they
      // are being offered the other look, from the one they have.
      skin: AppSkin.classic,
    );
  });

  testWidgets('the kind row on Files', (tester) async {
    await _shoot(
      tester,
      'file_kinds.png',
      const Padding(
        padding: EdgeInsets.all(14),
        child: FileKindBar(
          counts: {'pdf': 86, 'image': 54, 'sheet': 31, 'other': 43},
          selected: 'pdf',
          onPick: _ignore,
        ),
      ),
    );
  });

  for (final skin in AppSkin.values) {
    testWidgets('an ordinary page in ${skin.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 620 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _font();
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light, skin: skin),
        home: RepaintBoundary(key: key, child: _ordinaryPage()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final b =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        if (png != null && Directory(_out).existsSync()) {
          File('$_out\\page_${skin.name}.png')
              .writeAsBytesSync(png.buffer.asUint8List());
        }
      });
    });
  }

  testWidgets('the faces on Photos', (tester) async {
    await _shoot(
      tester,
      'people_strip.png',
      Padding(
        padding: const EdgeInsets.all(14),
        child: PeopleStrip(
          people: const [
            {'id': 1, 'name': 'Anita', 'photo_count': 312},
            {'id': 2, 'name': 'Dad', 'photo_count': 108},
            {'id': 3, 'name': 'Meera', 'photo_count': 64},
            {'id': 4, 'name': 'Arjun', 'photo_count': 41},
          ],
          selected: const {1},
          onToggle: (_) {},
          onSeeAll: () {},
        ),
      ),
    );
  });
}

void _ignore(String _) {}

/// A page nobody hand-edited, in both skins, side by side.
///
/// Ordinary Material widgets only — no SafeNest screen. What it shows is
/// whether the LOOK is inherited, which is the difference between a skin that
/// reaches six screens and one that reaches all of them.
Widget _ordinaryPage() => Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: const [Icon(Icons.more_vert), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const TextField(
              decoration: InputDecoration(hintText: 'Search reminders')),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              title: Text('Car insurance renewal'),
              subtitle: Text('Due today'),
            ),
          ),
          const SizedBox(height: 10),
          const Card(
            child: ListTile(
              title: Text("Anita's birthday"),
              subtitle: Text('Tomorrow'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () {}, child: const Text('Add a reminder')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () {}, child: const Text('Show past ones')),
        ],
      ),
    );
