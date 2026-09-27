// Home, in the Colourful skin — rendered and pinned.
//
// The phone cannot be run here, so a screen that is only reasoned about ships
// unseen. `debugData` exists so this one can be drawn without a server, and
// the PNG beside it is how the design is judged rather than imagined.
//
// WHAT IS ASSERTED is the ordering, because the ordering is the argument.
// Three earlier versions of this screen led with money, then with counts, then
// with a progress ring — all three dashboards for a library rather than the
// library. The photograph comes first now, and a change that quietly puts a
// number back on top would pass every other test in this repository.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/screens/vivid_home.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/library_growth.dart';

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

const _data = VividHomeData(
  name: 'Raghudarshan',
  photos: 1573,
  videos: 200,
  documents: 214,
  memory: VividCard(title: 'Goa', sub: '142 photos', count: 142),
  people: [
    VividCard(title: 'Anita', count: 312),
    VividCard(title: 'Dad', count: 108),
    VividCard(title: 'Meera', count: 64),
    VividCard(title: 'Arjun', count: 41),
  ],
  albums: [
    VividCard(title: 'Goa', sub: '142 photos', count: 142),
    VividCard(title: 'Diwali', sub: '88 photos', count: 88),
    VividCard(title: 'Coorg', sub: '64 photos', count: 64),
  ],
  kinds: {'pdf': 86, 'image': 54, 'sheet': 31, 'other': 43},
  months: [88, 142, 96, 174, 151, 118, 203, 165, 229, 141, 186, 312],
);

void main() {
  testWidgets('the photograph leads, and the counts follow it', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _useRealFont();

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
      home: RepaintBoundary(
        key: key,
        child: const VividHome(brand: Brand(), debugData: _data),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // THE ORDERING IS THE ARGUMENT. The memory sits above every figure on the
    // screen; a change that puts a count back on top has changed what the app
    // says it is.
    final memoryY = tester.getTopLeft(find.text('142 photos').first).dy;
    for (final later in ['Photos', 'People', 'Places & days', 'Documents']) {
      expect(tester.getTopLeft(find.text(later).first).dy,
          greaterThan(memoryY),
          reason: '"$later" must come after the photograph');
    }

    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png != null && Directory(_out).existsSync()) {
        File('$_out\\vivid_home.png').writeAsBytesSync(png.buffer.asUint8List());
      }
    });
  });

  testWidgets('and the same page in the dark', (tester) async {
    // Night was drawn as its own artboard, and the app gets there through
    // dark mode rather than a third skin — so it has to be LOOKED at, not
    // assumed to follow.
    tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _useRealFont();

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.dark, skin: AppSkin.vivid),
      home: RepaintBoundary(
        key: key,
        child: const VividHome(brand: Brand(), debugData: _data),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png != null && Directory(_out).existsSync()) {
        File('$_out\\vivid_home_dark.png')
            .writeAsBytesSync(png.buffer.asUint8List());
      }
    });
  });

  testWidgets('with nothing to show it still draws, without zeroes',
      (tester) async {
    // A fresh install, or a server that answered nothing. A count of zero
    // drawn mid-flight reads as "you have no photographs"; the dash says "not
    // known yet", which is the truth.
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
      home: const VividHome(brand: Brand(), debugData: VividHomeData(name: 'R')),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsWidgets);
    // No memory, no people, no albums — and no empty headings announcing it.
    expect(find.text('People'), findsNothing);
    expect(find.text('Places & days'), findsNothing);
  });

  group('the pieces', () {
    test('counts are grouped', () {
      expect(vividCount(1573), '1,573');
      expect(vividCount(20431), '20,431');
      expect(vividCount(214), '214');
      expect(vividCount(null), '—');
    });

    test('the greeting turns on the same hours as the rest of the app', () {
      expect(vividGreeting(DateTime(2026, 9, 27, 8)), 'Good morning');
      expect(vividGreeting(DateTime(2026, 9, 27, 12)), 'Good afternoon');
      expect(vividGreeting(DateTime(2026, 9, 27, 17)), 'Good evening');
    });

    test('the date is written out, not punched in', () {
      // 27/09 is a format; a date on a screen is read.
      expect(vividDate(DateTime(2026, 9, 27)), 'Sunday, 27 September');
      expect(vividDate(DateTime(2026, 1, 1)), 'Thursday, 1 January');
    });

    group('how recent the last backup was', () {
      final now = DateTime(2026, 9, 27, 12, 0);

      test('it reads the way somebody would say it', () {
        expect(vividAgo(now.subtract(const Duration(seconds: 20)), now),
            'just now');
        expect(vividAgo(now.subtract(const Duration(minutes: 14)), now),
            '14 min ago');
        expect(vividAgo(now.subtract(const Duration(hours: 3)), now),
            '3 hours ago');
        expect(vividAgo(now.subtract(const Duration(days: 1)), now),
            'yesterday');
        expect(vividAgo(now.subtract(const Duration(days: 4)), now),
            '4 days ago');
        expect(vividAgo(now.subtract(const Duration(days: 20)), now),
            '3 weeks ago');
      });

      test('one hour is not "1 hours"', () {
        expect(vividAgo(now.subtract(const Duration(hours: 1)), now),
            '1 hour ago');
      });
    });

    group('how the library is growing', () {
      test('a trend needs something to compare against', () {
        // A first month has no trend, and "+100%" against zero is arithmetic
        // rather than information.
        expect(monthTrend(const []), isNull);
        expect(monthTrend(const [312]), isNull);
        expect(monthTrend(const [0, 312]), isNull);
      });

      test('it rounds to a whole percent, up or down', () {
        expect(monthTrend(const [100, 124]), 24);
        expect(monthTrend(const [200, 150]), -25);
        expect(monthTrend(const [100, 100]), 0);
      });
    });

    group('how long ago a memory was', () {
      final now = DateTime(2026, 9, 27);

      test('today and yesterday say nothing at all', () {
        // "0 days ago" on a photograph from this morning is noise, and the
        // badge is hidden rather than filled with it.
        expect(vividWhen(DateTime(2026, 9, 27), now), isNull);
        expect(vividWhen(DateTime(2026, 9, 26), now), isNull);
      });

      test('it rounds the way somebody would say it', () {
        expect(vividWhen(DateTime(2026, 9, 20), now), 'Last week');
        expect(vividWhen(DateTime(2026, 8, 20), now), '5 weeks ago');
        expect(vividWhen(DateTime(2026, 3, 27), now), '6 months ago');
        expect(vividWhen(DateTime(2025, 9, 27), now), 'A year ago');
        expect(vividWhen(DateTime(2024, 9, 27), now), '2 years ago');
      });

      test('a year is "a year", not "1 years"', () {
        // The tell that nobody read the output.
        expect(vividWhen(DateTime(2025, 10, 1), now), isNot(contains('1 year')));
        expect(vividWhen(DateTime(2025, 9, 27), now), 'A year ago');
      });

      test('no date is no badge', () {
        expect(vividWhen(null, now), isNull);
      });
    });
  });
}
