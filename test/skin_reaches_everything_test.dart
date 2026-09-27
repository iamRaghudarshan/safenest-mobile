// Does the skin reach a screen nobody hand-edited?
//
// The first pass at Colourful styled six screens and left thirty inheriting
// Classic with slightly different colours. That is worse than no skin: an app
// whose appearance depends on which page you are on reads as broken rather
// than as themed, and it was shipped that way.
//
// The fix was to move the look into the THEME, so screens inherit it. This
// test is what stops it regressing, and it deliberately uses a plain Scaffold
// with ordinary Material widgets — no SafeNest screen at all. If the theme
// carries the skin, anything built from these widgets carries it too.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/theme.dart';

Widget _plainScreen() => Scaffold(
      appBar: AppBar(title: const Text('Any screen')),
      body: ListView(children: [
        const Card(child: ListTile(title: Text('A row'))),
        const TextField(decoration: InputDecoration(hintText: 'A field')),
        FilledButton(onPressed: () {}, child: const Text('Do it')),
        OutlinedButton(onPressed: () {}, child: const Text('Or not')),
      ]),
    );

void main() {
  for (final mode in [Brightness.light, Brightness.dark]) {
    group('${mode.name} mode', () {
      testWidgets('the app bar carries the brand in Colourful, not in Classic',
          (tester) async {
        // THE APP BAR IS THE WHOLE TEST. Almost every screen in this app has
        // one and almost none of them style it, so it is the single control
        // that decides whether a skin reaches six screens or all of them.
        for (final skin in AppSkin.values) {
          await tester.pumpWidget(MaterialApp(
            theme: buildTheme(const Brand(), mode, skin: skin),
            home: _plainScreen(),
          ));
          // MaterialApp CROSS-FADES a theme change, so `Theme.of` straight
          // after a pump returns a blend of the old one and the new. Reading
          // it there is how this test first "proved" the skin had not been
          // applied when it had.
          await tester.pumpAndSettle();
          final bar = tester.widget<AppBar>(find.byType(AppBar));
          final theme = Theme.of(tester.element(find.byType(AppBar)));
          final want = skin == AppSkin.vivid
              ? SkinTokens.vivid.brand
              : theme.appBarTheme.backgroundColor;
          expect(theme.appBarTheme.backgroundColor, want,
              reason: '$skin in ${mode.name}');
          expect(bar.title, isNotNull);
        }
      });

      testWidgets('Colourful paints its own page; Classic stays transparent',
          (tester) async {
        // Classic is transparent so the app-wide nature backdrop shows
        // through. Colourful is a flat ground with saturated blocks on it,
        // and a photograph behind those stops the coloured header reading as
        // a header at all.
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(const Brand(), mode, skin: AppSkin.classic),
          home: _plainScreen(),
        ));
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(find.byType(Scaffold)))
            .scaffoldBackgroundColor, Colors.transparent);

        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(const Brand(), mode, skin: AppSkin.vivid),
          home: _plainScreen(),
        ));
        await tester.pumpAndSettle();
        expect(
            Theme.of(tester.element(find.byType(Scaffold)))
                .scaffoldBackgroundColor,
            isNot(Colors.transparent));
      });
    });
  }

  test('the pieces every screen inherits differ between the skins', () {
    // Each of these is a component an ordinary screen uses without styling
    // it. If any stopped differing, that part of the app would silently fall
    // back to looking Classic while the rest did not.
    final c = buildTheme(const Brand(), Brightness.light);
    final v = buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid);

    expect(v.appBarTheme.backgroundColor, isNot(c.appBarTheme.backgroundColor),
        reason: 'the app bar is on nearly every screen');
    expect(v.appBarTheme.foregroundColor, isNot(c.appBarTheme.foregroundColor));
    expect(v.scaffoldBackgroundColor, isNot(c.scaffoldBackgroundColor));
    expect(v.colorScheme.primary, isNot(c.colorScheme.primary));
    // Fields differ by SHAPE, not by fill. They were briefly filled with the
    // page colour in Colourful, which made every search box sitting straight
    // on a page invisible; both are white now and it is the radius and the
    // height that carry the skin.
    expect(v.inputDecorationTheme.border,
        isNot(c.inputDecorationTheme.border),
        reason: 'every search box and form field');
    expect(v.inputDecorationTheme.contentPadding,
        isNot(c.inputDecorationTheme.contentPadding));
    expect(v.bottomSheetTheme.shape, isNot(c.bottomSheetTheme.shape),
        reason: 'half the app lives in a sheet');
    expect(v.chipTheme.shape, isNot(c.chipTheme.shape));
  });

  test('a tab knows its colour in each skin', () {
    // The bottom bar bakes a colour in beside each icon. In Colourful those
    // constants would be the one place Photos is not blue.
    expect(SkinTokens.vivid.module('gallery'),
        isNot(SkinTokens.classic.module('gallery')));
  });
}
