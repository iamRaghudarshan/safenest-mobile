// The code screen, drawn.
//
// It is reached only by an account with two-step sign-in turned on, which is
// exactly the kind of screen that ships unlooked-at and stays wrong for
// months. Rendered here in both skins, and the recovery toggle exercised,
// because that half of it is behind a tap nobody makes by accident.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/screens/two_factor_screen.dart';
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

final _pending = TwoFactorRequired(
  url: 'http://127.0.0.1:5601',
  challenge: 'c',
  methods: const ['totp', 'recovery'],
);

Widget _screen(AppSkin skin) => ChangeNotifierProvider<Session>(
      create: (_) => Session(),
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light, skin: skin),
        home: TwoFactorScreen(brand: const Brand(), pending: _pending),
      ),
    );

void main() {
  for (final skin in AppSkin.values) {
    testWidgets('${skin.name}: it asks for the code, and offers the way out',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _useRealFont();

      final key = GlobalKey();
      await tester.pumpWidget(
          RepaintBoundary(key: key, child: _screen(skin)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Enter your code'), findsOneWidget);
      // Somebody who has lost their phone must be able to see the other route
      // without knowing it exists.
      expect(find.textContaining("can't get to my authenticator"), findsOneWidget);

      Future<void> shoot(String name) => tester.runAsync(() async {
            final b =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await b.toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            if (png != null && Directory(_out).existsSync()) {
              File('$_out/twofactor_$name.png')
                  .writeAsBytesSync(png.buffer.asUint8List());
            }
          });
      await shoot(skin.name);

      // The recovery half is a different keyboard and a different field, not
      // just different words, so it is worth drawing too.
      await tester.tap(find.textContaining("can't get to my authenticator"));
      await tester.pumpAndSettle();
      expect(find.text('Use a recovery code'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shoot('${skin.name}_recovery');
    });
  }

  testWidgets('an account with no recovery codes is not offered them',
      (tester) async {
    // The server names what it will accept. Offering a route it will refuse is
    // worse than not offering it: it sends somebody looking for codes that do
    // not exist at the moment they are already locked out.
    await tester.pumpWidget(ChangeNotifierProvider<Session>(
      create: (_) => Session(),
      child: MaterialApp(
        theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
        home: TwoFactorScreen(
          brand: const Brand(),
          pending: TwoFactorRequired(
              url: 'http://x', challenge: 'c', methods: const ['totp']),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't get to my authenticator"), findsNothing);
  });
}
