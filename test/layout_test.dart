// Does it fit on a phone?
//
// WHY THIS EXISTS
// The Home screen ran off the bottom of a real iPhone, and nothing here caught
// it: `flutter analyze` reports zero issues for a layout that cannot possibly
// fit, because overflow is a RUNTIME measurement, not a type error. Seven
// versions were shipped on the strength of a clean analyse.
//
// The actual fault was that Home is the only screen with no AppBar, and nothing
// insets a Scaffold body without one — so its content began at y=0, under the
// clock and behind the notch.
//
// Worth recording how that was found, because the first answer was wrong. The
// initial diagnosis was Columns nested in Rows defaulting to MainAxisSize.max.
// That theory was tested by putting the "bug" back and running these tests: they
// still passed, which proved the theory wrong rather than the tests weak. A fix
// that cannot be made to fail on purpose has not been shown to fix anything.
//
// So the tests lay each screen out at real phone sizes, WITH a notch inset, and
// fail on overflow or on content drawn above the safe area. The smallest size is
// an iPhone SE, because a layout that only fits a large phone breaks for whoever
// has the cheap one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/screens/dashboard_screen.dart';
import 'package:safenest/screens/notifications_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/brand_button.dart';

/// Phones people actually hold, smallest first.
const _sizes = <String, Size>{
  'iPhone SE': Size(375, 667),
  'iPhone 15': Size(393, 852),
  'Pixel 7': Size(412, 915),
};

/// Realistic content, not a happy-path stub. Long names and big numbers are
/// what push a layout over the edge, so they belong in the test.
final _dashboardData = <String, dynamic>{
  'stats': {
    'investValue': 1234567,
    'investDelta': 12,
    'monthSpend': 98765,
    'monthIncome': 150000,
    'outstanding': 2500000,
    'duesCount': 3,
  },
  'upcoming': [
    {'title': 'HDFC Regalia credit card bill ••4242', 'module': 'cards', 'due': '03-08-2026', 'days': -4},
    {'title': 'Home loan instalment', 'module': 'loans', 'due': '10-08-2026', 'days': 3},
    {'title': 'Renew car insurance before it lapses', 'module': 'insurance', 'due': '12-08-2026', 'days': 5},
  ],
};

final _brief = <String, dynamic>{'date': 'Friday, 07 August'};

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return ChangeNotifierProvider<Session>(
    create: (_) => Session(),
    child: MaterialApp(
      theme: buildTheme(const Brand(), brightness),
      home: child,
    ),
  );
}

void main() {
  for (final entry in _sizes.entries) {
    testWidgets('Home fits a ${entry.key} without overflowing', (tester) async {
      tester.view.physicalSize = entry.value * tester.view.devicePixelRatio;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = entry.value;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(DashboardScreen(
        onOpen: (_) {},
        initialData: _dashboardData,
        initialBrief: _brief,
      )));
      await tester.pump();

      // takeException() returns any error Flutter recorded while laying out —
      // a RenderFlex overflow among them. Asserting it is null is the whole
      // point: it is the check that was missing.
      expect(tester.takeException(), isNull,
          reason: 'Home overflowed on ${entry.key}');
    });
  }

  testWidgets('Home lays out in dark as well as light', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(
      DashboardScreen(
          onOpen: (_) {}, initialData: _dashboardData, initialBrief: _brief),
      brightness: Brightness.dark,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home survives an empty account — no dues, no briefing',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The "all clear" branch is a different tree from the dues branch, so it
    // needs laying out too. A brand-new customer sees only this one.
    await tester.pumpWidget(_wrap(DashboardScreen(
      onOpen: (_) {},
      initialData: const {'stats': {}, 'upcoming': []},
      initialBrief: const {},
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home starts BELOW the status bar and the notch', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    // A Dynamic Island phone reserves 59 logical pixels at the top. Home is the
    // only screen with no AppBar, so nothing insets it automatically — and it
    // rendered the greeting under the clock until SafeArea was added.
    tester.view.padding = const FakeViewPadding(top: 59);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(DashboardScreen(
      onOpen: (_) {},
      initialData: _dashboardData,
      initialBrief: _brief,
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // The greeting is the first thing on the screen. If its top edge is above
    // the inset, it is behind the notch.
    final greeting = find.textContaining('Good', findRichText: true);
    expect(greeting, findsWidgets);
    final top = tester.getTopLeft(greeting.first).dy;
    expect(top, greaterThanOrEqualTo(59.0),
        reason: 'Home content is drawn under the status bar / notch');
  });

  testWidgets('The notification inbox fits, read and unread, on an iPhone SE',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Long bodies are the realistic case — a daily digest lists everything due,
    // and that is the message most likely to burst a row.
    await tester.pumpWidget(_wrap(NotificationsScreen(
      initialRows: [
        {
          'id': 1,
          'kind': 'reminder',
          'title': 'Take the tablets',
          'body': 'Due now — 6:30 pm',
          'is_read': 0,
          'created_at': DateTime.now()
              .subtract(const Duration(minutes: 20))
              .toIso8601String(),
        },
        {
          'id': 2,
          'kind': 'digest',
          'title': '3 overdue · 2 due today',
          'body': 'HDFC Regalia credit card bill ••4242, Home loan instalment, '
              'Renew car insurance before it lapses, Pay the electricity bill',
          'is_read': 1,
          'created_at': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        },
        {
          'id': 3,
          'kind': 'broadcast',
          'title': 'SafeNest 3.2 is available',
          'body': 'Reminders can now be set for a particular time of day.',
          'is_read': 0,
          'created_at': DateTime.now()
              .subtract(const Duration(hours: 5))
              .toIso8601String(),
        },
      ],
    )));
    await tester.pump();

    expect(tester.takeException(), isNull, reason: 'the inbox overflowed');
    // Unread by default: the two unread ones, said in words not only in weight.
    // The read digest is on its own tab now, not mixed in.
    expect(find.text('New'), findsNWidgets(2));
    expect(find.text('Reminder'), findsOneWidget);
    expect(find.text('20m ago'), findsOneWidget);
    expect(find.text('2d ago'), findsNothing);

    // Switch to Read: the digest, and it still fits the narrow screen.
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'the read tab overflowed');
    expect(find.text('2d ago'), findsOneWidget);
  });

  testWidgets('An empty inbox says so warmly rather than looking broken',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const NotificationsScreen(initialRows: [])));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('All caught up'), findsOneWidget);
  });

  testWidgets('The segmented control fits five labels on the narrowest phone',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Five is the case the web app has a rule for — `.seg4.five` tightens the
    // type rather than letting "Memories" wrap. Worth proving it holds here.
    await tester.pumpWidget(_wrap(Scaffold(
      body: Segmented(
        labels: const ['Photos', 'Albums', 'People', 'Memories', 'Favourites'],
        index: 0,
        onChanged: (_) {},
      ),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
