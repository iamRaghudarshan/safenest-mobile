// A suggestion card, at the width of a real phone.
//
// It shipped in 1.81.0 reading one character per line — "122 photos that day"
// set vertically down the middle of the card, with half the card empty beside
// it. Nothing in the source says why: the text is already inside an Expanded
// and the photo stack is a fixed-width SizedBox. Reading it was not going to
// settle it, so this draws it.
//
// The data is handed in rather than fetched. The panel loads itself, and a
// widget test runs in a zone where a real socket's callbacks are never
// delivered — which is exactly why this card had never been drawn at a phone's
// width by anything here. The shapes below are the ones that were on screen,
// including a suggestion with NO title, which is the case that was.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/api.dart';
import 'package:safenest/screens/suggestions_strip.dart';
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

/// The suggestions the phone actually had on screen: no title, a long detail,
/// three covers, and one of them a kind with a second button.
final _items = <Map<String, dynamic>>[
  {
    'kind': 'collage',
    'key': 'a',
    'detail': '122 photos that day',
    'covers': ['/media/1.jpg', '/media/2.jpg', '/media/3.jpg'],
  },
  {
    'kind': 'reel',
    'key': 'b',
    'title': 'A moving highlight',
    'detail': '227 photos that day',
    'covers': ['/media/4.jpg', '/media/5.jpg'],
  },
  {
    'kind': 'folder',
    'key': 'c',
    'detail': 'Photographs from a trip that has no name yet, '
        'which is the longest a detail line has ever been',
    'covers': ['/media/6.jpg'],
  },
];

void main() {
  testWidgets('the detail reads across the card, not down it', (tester) async {
    // 390pt is the phone. This is the whole point: the card was fine in every
    // render that had a desktop's width to spend.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _useRealFont();

    final key = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<Session>(
      create: (_) => Session(),
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SingleChildScrollView(
              child: SuggestionsStrip(
                // Port 1 is never listening, and nothing asks it anything:
                // `debugItems` is the data. The api is required only because
                // the dismiss and make buttons need somewhere to send to.
                api: Api(baseUrl: 'http://127.0.0.1:1', token: 'x'),
                debugItems: _items,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('SUGGESTIONS'), findsOneWidget);

    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png != null && Directory(_out).existsSync()) {
        File('$_out/suggestion_card.png')
            .writeAsBytesSync(png.buffer.asUint8List());
      }
    });

    // THE ASSERTION THAT WOULD HAVE CAUGHT IT. A line of text set one
    // character at a time is not a wrapping bug to be judged by eye — it is a
    // box far taller than it is wide, which is a number.
    for (final detail in ['122 photos that day', '227 photos that day']) {
      final size = tester.getSize(find.text(detail));
      expect(size.width, greaterThan(size.height),
          reason: '"$detail" is ${size.width.toStringAsFixed(0)}x'
              '${size.height.toStringAsFixed(0)} — it is being set down the '
              'card one character per line, not across it');
      expect(size.width, greaterThan(100),
          reason: '"$detail" has only ${size.width.toStringAsFixed(0)}pt to '
              'read in');
    }
  });
}
