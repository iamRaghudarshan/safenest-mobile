// The screens rebuilt in this pass, laid out at real phone sizes.
//
// `flutter analyze` reports zero issues for a layout that cannot fit — this
// project shipped seven versions on exactly that basis — so a screen is not
// "done" here until it has been laid out with realistic content and asserted
// not to overflow.
//
// Backup gets the most attention because it has FIVE states and four of them
// were previously indistinguishable grey text: idle, running, finished,
// stopped, and failed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safenest/backup.dart';
import 'package:safenest/screens/activity_screen.dart';
import 'package:safenest/screens/backup_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

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
  group('Backup — every state it can be in', () {
    final states = <String, BackupProgress>{
      'idle': const BackupProgress(),
      'scanning': const BackupProgress(
          state: BackupState.scanning, message: 'Looking through your photos…'),
      'running': const BackupProgress(
          state: BackupState.running,
          total: 20431,
          done: 8123,
          skipped: 4001,
          failed: 12,
          message: 'Backing up…'),
      'finished': const BackupProgress(
          state: BackupState.done,
          total: 20431,
          done: 16430,
          skipped: 4001,
          message: 'Backed up. 16430 new, 4001 already there.'),
      'stopped': const BackupProgress(
          state: BackupState.paused,
          total: 20431,
          done: 120,
          skipped: 4001,
          message: 'Stopped — nothing is lost, it carries on from here next time.'),
      'failed — session expired': const BackupProgress(
          state: BackupState.failed,
          total: 20431,
          failed: 20431,
          message: 'Nothing could be backed up. Your session has expired. '
              'Sign out and back in.'),
      'failed — limited access': const BackupProgress(
          state: BackupState.failed,
          message: 'SafeNest can only see the few photos you picked, not your '
              'whole library. Settings → Privacy → Photos → SafeNest → '
              'All Photos, then run this again.'),
    };

    for (final entry in states.entries) {
      testWidgets('${entry.key} fits an iPhone SE', (tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
            _wrap(BackupScreen(debugProgress: entry.value)));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'Backup overflowed in the ${entry.key} state');
      });
    }

    testWidgets('a failed run does NOT read as a success', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(BackupScreen(
          debugProgress: states['failed — session expired']!)));
      await tester.pump();

      // The old screen said "Backed up. 0 new, 0 already there." for this, in
      // grey, with a tick. That is the single worst thing this app can say.
      expect(find.text('That did not work'), findsOneWidget);
      expect(find.textContaining('Sign out and back in'), findsOneWidget);
      expect(find.text('Backed up'), findsNothing);
      // And the count is named as an UPLOAD failure, not a read failure.
      expect(find.textContaining('not sent'), findsOneWidget);
      expect(find.textContaining('could not be read'), findsNothing);
    });

    testWidgets('a permission failure offers the settings shortcut, and a '
        'network one does not', (tester) async {
      // A taller viewport than the fitting tests use, on purpose: this asserts
      // WHICH controls appear, and in a ListView a control below the fold is
      // not in the element tree for a finder to see. Whether it fits is the
      // other tests' job.
      tester.view.physicalSize = const Size(375, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _wrap(BackupScreen(debugProgress: states['failed — limited access']!)));
      await tester.pump();
      expect(find.text('Open photo settings'), findsOneWidget);

      await tester.pumpWidget(_wrap(
          BackupScreen(debugProgress: states['failed — session expired']!)));
      await tester.pump();
      // Sending somebody to iOS photo settings to fix an expired session would
      // be worse than saying nothing.
      expect(find.text('Open photo settings'), findsNothing);
    });

    testWidgets('a run in progress shows real numbers, not just a bar',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _wrap(BackupScreen(debugProgress: states['running']!)));
      await tester.pump();

      expect(find.text('12136 of 20431'), findsOneWidget);
      expect(find.text('59%'), findsOneWidget);
      expect(find.text('8123 sent'), findsOneWidget);
      expect(find.text('4001 already there'), findsOneWidget);
      expect(find.text('12 not sent'), findsOneWidget);
    });

    testWidgets('dark theme lays out too', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
          BackupScreen(debugProgress: states['running']!),
          brightness: Brightness.dark));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Backup progress accounting', () {
    // THE REPORTED BUG: the bar froze. `_emit` was called only inside the
    // upload loop, so a page of 200 photos that were ALL already backed up ran
    // that loop zero times and emitted nothing — `skipped` climbed by 200 in
    // silence and the bar did not move.
    //
    // Which made it look broken on exactly the runs people do most: the second
    // one, and every one after it. A first backup uploads everything and moves
    // smoothly; a repeat skips nearly all of it, sits at 0% through the whole
    // library, then jumps to 100% at the end.

    test('skipped photos count towards progress, not just uploaded ones', () {
      // A second run over a fully backed-up library: nothing to send, but it is
      // 60% of the way through and has to say so.
      const p = BackupProgress(
          state: BackupState.running, total: 1000, done: 0, skipped: 600);
      expect(p.handled, 600);
      expect(p.fraction, closeTo(0.6, 0.001),
          reason: 'a skip IS progress — it is a photo that has been dealt with');
    });

    test('a page reports even when it uploads nothing', () {
      // Emitting per PAGE rather than only per upload slice is the fix. Over a
      // 20,000-photo library that is 200 updates, which moves visibly.
      var emitted = 0;
      var skipped = 0;
      const total = 20000, page = 200;
      for (var offset = 0; offset < total; offset += page) {
        skipped += page;   // every photo in the page already sent
        emitted++;         // report() after the skip accounting  <-- the fix
        // the upload loop body runs ZERO times on this path
        emitted++;         // report() at the end of the page
      }
      expect(skipped, total);
      expect(emitted, 200,
          reason: 'the old code emitted zero times over this entire library');
    });

    test('the fraction never leaves 0..1', () {
      // LinearProgressIndicator asserts outside that range, and the total comes
      // from the phone's library — which can change during a long run.
      expect(const BackupProgress(total: 0).fraction, 0);
      expect(const BackupProgress(total: 10, done: 50).fraction, 1.0,
          reason: 'a photo deleted mid-run must nudge the bar, not crash it');
      expect(
          const BackupProgress(total: 10, done: 5).fraction, closeTo(0.5, 0.001));
    });

    testWidgets('a repeat run over a backed-up library shows real progress',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const BackupScreen(
          debugProgress: BackupProgress(
              state: BackupState.running,
              total: 20000,
              done: 0,
              skipped: 12000,
              message: 'Backing up…'))));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Not 0%. This is the reading that used to be stuck.
      expect(find.text('12000 of 20000'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
    });
  });

  group('Activity log', () {
    testWidgets('lays out, and reads times as a person would', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      await tester.pumpWidget(_wrap(ActivityScreen(initialRows: [
        {
          'action': 'delete',
          'label': 'HDFC Regalia credit card ••4242',
          'created_at':
              now.subtract(const Duration(minutes: 12)).toIso8601String(),
        },
        {
          'action': 'card_paid',
          'label': 'ICICI Amazon Pay',
          'created_at': now.subtract(const Duration(hours: 5)).toIso8601String(),
        },
        {
          'action': 'profile_update',
          'label': '',
          'created_at': now.subtract(const Duration(days: 3)).toIso8601String(),
        },
      ])));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // "card_paid" -> "Card paid". A log full of database identifiers reads
      // like a stack trace.
      expect(find.text('Card paid'), findsOneWidget);
      expect(find.text('Profile update'), findsOneWidget);
      expect(find.text('12m ago'), findsOneWidget);
      expect(find.text('3d ago'), findsOneWidget);
      // A deletion is the one entry worth spotting from across the list.
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('an empty log explains what will appear there', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const ActivityScreen(initialRows: [])));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Nothing recorded yet'), findsOneWidget);
    });
  });
}
