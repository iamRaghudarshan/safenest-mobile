// Can you SEE the back button on a full-screen photo?
//
// Reported as "in photos when open full photo back button not visible
// properly", and it was invisible rather than faint. The viewer's app bar said
//
//     AppBar(backgroundColor: Colors.black38, foregroundColor: Colors.white)
//
// which reads as though it colours the back arrow white. It does not.
// Flutter resolves an app bar's icon colour as
//
//     widget.iconTheme ?? appBarTheme.iconTheme ?? defaults(foregroundColor)
//
// so a NON-NULL AppBarTheme.iconTheme beats the widget's foregroundColor
// outright — and theme.dart sets iconTheme on both skins, unconditionally. On
// Classic that is `ink`, a near-black, drawn straight over somebody's
// photograph. The date beside it went the same way, because
// AppBarTheme.titleTextStyle wins over foregroundColor by the same rule.
//
// The bottom action row was legible the whole time, and that is the evidence
// for the diagnosis rather than a coincidence: it hardcodes Colors.white on
// every Icon and Text, so it never consulted the theme at all. The one control
// that leaned on foregroundColor is the one that disappeared.
//
// These tests pin the RULE and not the appearance, because the appearance is
// what a future tidy-up would quietly change back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/screens/gallery_screen.dart' show Photo;
import 'package:safenest/screens/photo_viewer.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

/// The scrim painted behind the chrome, as the viewer paints it. Kept here as
/// the arithmetic's input so the test fails if the viewer is weakened.
const _scrimTop = Color(0x8C000000);

Photo _photo(int i) => Photo(
      i,
      '/api/gallery/media/full/p$i.jpg',
      '/api/gallery/media/thumb/p$i.jpg',
      DateTime(2026, 10, 14),
      false,
    );

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return ChangeNotifierProvider<Session>(
    create: (_) => Session(),
    child: MaterialApp(
      theme: buildTheme(const Brand(), brightness),
      home: child,
    ),
  );
}

/// The colour the back arrow is actually drawn in, read off the rendered icon
/// rather than off the configuration that was meant to produce it.
///
/// Resolved from the ICON'S OWN element and not the app bar's. AppBar wraps its
/// leading in an IconTheme of its own, so asking at the app bar's context
/// answers with the ambient theme above it and misses the thing under test —
/// which is how the first version of this test passed while reading the wrong
/// value.
Color? _backArrowColour(WidgetTester tester) {
  final arrow = find.byIcon(Icons.arrow_back);
  final icon = tester.widget<Icon>(arrow);
  return icon.color ?? IconTheme.of(tester.element(arrow)).color;
}

/// Pump the viewer and discard the image service's complaints.
///
/// NetworkImage cannot fetch anything in a widget test — every request comes
/// back 400 — and the viewer loads full-size photographs. The chrome over the
/// top is what these tests are about, so the load failures are noise here, but
/// they are reported as test failures unless taken.
/// It is PUSHED, not used as `home`, and that is not incidental to this test:
/// the back arrow under examination is the one AppBar builds automatically for
/// a route that can be popped. As `home` there is nothing to pop, no leading is
/// built, and the test finds no arrow to measure — which is how the first
/// version of this failed with "No element" rather than a wrong colour.
Future<void> _pumpViewer(WidgetTester tester,
    {Brightness brightness = Brightness.light}) async {
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ChangeNotifierProvider<Session>(
    create: (_) => Session(),
    child: MaterialApp(
      navigatorKey: nav,
      theme: buildTheme(const Brand(), brightness),
      home: const Scaffold(body: SizedBox()),
    ),
  ));

  nav.currentState!.push(MaterialPageRoute(
    builder: (_) =>
        PhotoViewer(photos: [_photo(1), _photo(2)], initialIndex: 0),
  ));

  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  while (tester.takeException() != null) {
    // Each one is a NetworkImageLoadException for a photo that cannot exist.
  }
}

void main() {
  group('the back button on a full photo', () {
    testWidgets('is white, over a photograph of any colour', (tester) async {
      await _pumpViewer(tester);

      expect(_backArrowColour(tester), Colors.white,
          reason: 'a near-black arrow on a photograph is the reported bug');
    });

    testWidgets('and so is the date beside it', (tester) async {
      await _pumpViewer(tester);

      final title = tester.widget<AppBar>(find.byType(AppBar)).titleTextStyle;
      expect(title?.color, Colors.white,
          reason: 'titleTextStyle must be set here; the theme would win');
    });

    testWidgets('white in the DARK theme too, not just Classic',
        (tester) async {
      // The viewer is black whatever the app's theme is, so the answer must not
      // depend on the skin. Dark mode's ink is near-white and would have
      // ACCIDENTALLY looked fine, which is exactly how a bug like this survives
      // in one theme and ships broken in the other.
      await _pumpViewer(tester, brightness: Brightness.dark);

      expect(_backArrowColour(tester), Colors.white);
    });
  });

  group('why foregroundColor was not enough', () {
    testWidgets('the theme icon colour beats a widget foregroundColor',
        (tester) async {
      // THE BUG, WRITTEN DOWN — the old app bar, under the app's own theme.
      // If this ever starts returning white, Flutter changed its resolution
      // order or theme.dart stopped setting iconTheme, and the comment in
      // photo_viewer.dart explaining all this has gone stale.
      await tester.pumpWidget(_wrap(
        Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black38,
            foregroundColor: Colors.white, // the old code, verbatim
            // Supplied because this bar sits on the first route, so there is
            // nothing to pop and no automatic leading would be built. It is
            // the same widget the viewer gets for free when pushed.
            leading: const BackButton(),
            title: const Text('14 October 2026'),
          ),
          body: const SizedBox(),
        ),
      ));
      await tester.pump();

      final resolved = _backArrowColour(tester);
      expect(resolved, isNot(Colors.white),
          reason: 'if this is white, foregroundColor DID work and the fix '
              'addressed the wrong cause');

      final classic = buildTheme(const Brand(), Brightness.light);
      expect(resolved, classic.appBarTheme.iconTheme?.color,
          reason: 'it is the theme that is winning, specifically');
    });

    testWidgets('and the theme title style beats it in the same way',
        (tester) async {
      await tester.pumpWidget(_wrap(
        Scaffold(
          appBar: AppBar(
            foregroundColor: Colors.white,
            title: const Text('14 October 2026'),
          ),
          body: const SizedBox(),
        ),
      ));
      await tester.pump();

      final classic = buildTheme(const Brand(), Brightness.light);
      expect(tester.widget<AppBar>(find.byType(AppBar)).titleTextStyle, isNull,
          reason: 'nothing was set on the widget, so the theme supplies it');
      expect(classic.appBarTheme.titleTextStyle?.color, isNot(Colors.white),
          reason: 'which in Classic is dark ink');
    });
  });

  group('white chrome needs something behind it', () {
    test('the scrim carries white text over the brightest photograph', () {
      // White icons alone are not a fix: a scanned document or a snow shot
      // leaves a white arrow on near-white pixels. A photograph can be any
      // colour, so the floor has to hold for the worst one — the same
      // arithmetic the app backdrop uses, reused rather than reinvented.
      final c = backdropContrast(
        ink: Colors.white,
        surface: const Color(0xFF000000),
        alpha: (_scrimTop.a * 255.0).round() / 255.0,
      );
      expect(c, greaterThanOrEqualTo(4.5),
          reason: 'worst-case contrast under the scrim is '
              '${c.toStringAsFixed(2)}:1, below the readable threshold');
    });

    test('the old flat black38 bar would have failed that', () {
      // Why the fix is a gradient and not simply "make the icons white". At
      // 38% the bar was a tint, not a scrim: white-on-white stayed white.
      final c = backdropContrast(
        ink: Colors.white,
        surface: const Color(0xFF000000),
        alpha: (Colors.black38.a * 255.0).round() / 255.0,
      );
      expect(c, lessThan(4.5),
          reason: 'if this passes, black38 was strong enough and the scrim '
              'change was unnecessary');
    });

    testWidgets('the scrim does not swallow the tap that hides the chrome',
        (tester) async {
      // The scrim is paint, not a surface. Without IgnorePointer the top of
      // every photograph stops responding to the tap that clears the controls,
      // which would be a new bug introduced by the fix for this one.
      await _pumpViewer(tester);

      final scrims = find.descendant(
        of: find.byType(Stack),
        matching: find.byType(IgnorePointer),
      );
      expect(scrims, findsWidgets,
          reason: 'the gradient must be wrapped in IgnorePointer');
    });
  });
}
