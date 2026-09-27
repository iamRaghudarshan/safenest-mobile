// The Colourful home, rendered and pinned.
//
// The phone cannot be run here — no Android SDK, no Xcode — so a screen that
// is only reasoned about ships unseen. `debugData` exists so this one can be
// drawn without a server, and the PNG beside it is how the design is judged
// rather than imagined.
//
// What is ASSERTED is the ordering, because the ordering is the whole
// argument: photos and files lead, and nothing competes with them. A later
// change that quietly puts money back at the top would pass every other test
// in this repository.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/screens/vivid_home.dart';
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

const _data = VividHomeData(
  name: 'Raghudarshan',
  photos: 1573,
  videos: 200,
  documents: 214,
  recent: [
    {'title': 'Car insurance 2026.pdf'},
    {'title': 'Rental agreement.docx'},
    {'title': 'Home budget.xlsx'},
  ],
  memories: [
    {'caption': 'Goa'},
    {'caption': 'Diwali'},
    {'caption': 'Anita'},
  ],
);

void main() {
  testWidgets('it renders, and photos and files lead', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
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

    // THE ORDERING IS THE ARGUMENT. Both hero tiles are above every other
    // section; a change that puts anything before them has changed what the
    // app says it is for.
    final photosY = tester.getTopLeft(find.text('Photos & videos')).dy;
    final filesY = tester.getTopLeft(find.text('Documents')).dy;
    final backupY = tester.getTopLeft(find.text('Your copy')).dy;
    expect(photosY, lessThan(backupY));
    expect(filesY, lessThan(backupY));
    for (final later in ['Looking back', 'Recent files']) {
      expect(tester.getTopLeft(find.text(later)).dy, greaterThan(photosY),
          reason: '"$later" must come after the two the app is for');
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

  testWidgets('a figure that has not arrived shows a dash, never a zero',
      (tester) async {
    // A zero drawn while the request is in flight is a lie that corrects
    // itself, and on this screen the lie is "you have no photographs".
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
      home: const VividHome(brand: Brand(), debugData: VividHomeData(name: 'R')),
    ));
    await tester.pump();
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  group('the pieces', () {
    test('counts are grouped', () {
      expect(vividCount(1573), '1,573');
      expect(vividCount(214), '214');
      expect(vividCount(20431), '20,431');
      expect(vividCount(null), '—');
    });

    test('the greeting turns on the same hours as the rest of the app', () {
      expect(vividGreeting(DateTime(2026, 9, 27, 8)), 'Good morning');
      expect(vividGreeting(DateTime(2026, 9, 27, 11, 59)), 'Good morning');
      expect(vividGreeting(DateTime(2026, 9, 27, 12)), 'Good afternoon');
      expect(vividGreeting(DateTime(2026, 9, 27, 16, 59)), 'Good afternoon');
      expect(vividGreeting(DateTime(2026, 9, 27, 17)), 'Good evening');
      expect(vividGreeting(DateTime(2026, 9, 27, 23)), 'Good evening');
    });

    test('a file is badged by what it IS, not by where it sits', () {
      // People ask for "the insurance PDF", so the kind is the fastest thing
      // to scan for and it gets the colour.
      final t = SkinTokens.vivid;
      expect(fileBadge('Car insurance.pdf', t).label, 'PDF');
      expect(fileBadge('Rental.docx', t).label, 'DOC');
      expect(fileBadge('Budget.xlsx', t).label, 'XLS');
      expect(fileBadge('Aadhaar.jpeg', t).label, 'IMG');
      // Unknown, and NAMELESS, are the two that crash a naive implementation.
      expect(fileBadge('archive.7z', t).label, '7Z');
      expect(fileBadge('noextension', t).label, 'FILE');
      expect(fileBadge('', t).label, 'FILE');
    });

    test('a very long extension does not overflow the badge', () {
      // substring on a length it does not have is the classic way this throws.
      expect(fileBadge('x.superlongextension', SkinTokens.vivid).label.length,
          lessThanOrEqualTo(4));
    });
  });
}
