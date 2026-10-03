// Notes, measured against what Google Keep actually does.
//
// The owner's note was "Notes also not exactly like Google Keep — analyse and
// implement it", so the gaps had to be found rather than described. Four of
// them were on this side.
//
//   * NO MULTI-SELECT. Every action was one note at a time through three small
//     icons on each card, so archiving a dozen finished lists meant twelve taps
//     on twelve cards, each of which re-sorted the grid under the thumb.
//   * NO UNDO. A note archived by a mis-tap vanished with nothing to say what
//     had happened to it; getting it back meant knowing the Archive bucket
//     existed and which note to look for in it.
//   * TICKED ITEMS STAYED PUT. A twelve-line shopping list with nine crossed
//     out showed eight struck-through lines and hid the three that mattered.
//   * AND A NOTE COULD NOT REMIND YOU, though the column had been on the model
//     since the first release with a comment calling it stage 2.
//
// The server half is verified against a live server by
// backend/verify_notes_keep.py — 28 checks.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/memory/reminders.dart';
import 'package:safenest/screens/notes_screen.dart';
import 'package:safenest/theme.dart';

Map<String, dynamic> _note(
  int id,
  String title, {
  String kind = 'note',
  String body = '',
  List<Map<String, dynamic>> items = const [],
  List<String> labels = const [],
  DateTime? remindAt,
  bool pinned = false,
}) =>
    {
      'id': id,
      'title': title,
      'body': body,
      'kind': kind,
      'color': 'default',
      'labels': labels,
      'items': items,
      'pinned': pinned,
      'archived': false,
      'reminder_at': remindAt?.toIso8601String(),
    };

/// Scoped to the selection bar. Every card carries its own Pin and Archive
/// buttons, so a bare tooltip finder matches two widgets and the test fails
/// for a reason that has nothing to do with what it is checking.
Finder _bar(String tooltip) => find.descendant(
    of: find.byType(AppBar), matching: find.byTooltip(tooltip));

Widget _app({
  required List<Map<String, dynamic>> notes,
  void Function(String, List<int>)? onBulk,
}) =>
    MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: NotesScreen(debugNotes: notes, onBulk: onBulk),
    );

void main() {
  group('alarm ids stay out of each other way', () {
    test("a note's reminder cannot cancel the reminders module's", () {
      // Alarms.schedule clears an id before setting it, by design, so a
      // collision has no error and no symptom until something does not go off.
      for (final serverId in [1, 2, 50, 999, 100000]) {
        expect(noteAlarmId(1), isNot(serverId));
        expect(noteAlarmId(999999), isNot(serverId));
      }
    });

    test("nor Life Memory's warranty warnings", () {
      for (final factId in [1, 7, 99, 100000]) {
        for (final warning in [0, 1]) {
          expect(noteAlarmId(factId), isNot(memoryAlarmId(factId, warning)));
        }
      }
    });

    test('and it stays inside the band the repeat rings live below', () {
      // Alarms puts each reminder's repeats at (1 << 28) + id * 5.
      expect(noteAlarmId(999999999), lessThan(1 << 28));
      expect(noteAlarmId(999999999), greaterThan(0));
    });

    test('the same note always gets the same id, so editing moves it', () {
      // An id that changed between saves would leave the old alarm in place AND
      // add a new one, so the note would remind you twice and keep doing it.
      expect(noteAlarmId(42), noteAlarmId(42));
    });
  });

  group('what a checklist card shows', () {
    testWidgets('what is left comes first; what is done is counted',
        (tester) async {
      // THE SINGLE MOST RECOGNISABLE THING ABOUT A KEEP CARD. A twelve-line
      // shopping list with nine crossed out showed eight struck-through lines
      // and hid the three that mattered — the card was spent on the part of the
      // list already finished.
      await tester.pumpWidget(_app(notes: [
        _note(1, 'Weekly shop', kind: 'checklist', items: [
          for (var i = 0; i < 9; i++) {'text': 'bought \$i', 'checked': true},
          {'text': 'Rice', 'checked': false},
          {'text': 'Dal', 'checked': false},
          {'text': 'Oil', 'checked': false},
        ]),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Dal'), findsOneWidget);
      expect(find.text('Oil'), findsOneWidget);
      expect(find.text('9 ticked items'), findsOneWidget);
    });

    testWidgets('a finished list says so rather than showing nothing',
        (tester) async {
      await tester.pumpWidget(_app(notes: [
        _note(1, 'Packing', kind: 'checklist', items: [
          {'text': 'Passport', 'checked': true},
          {'text': 'Charger', 'checked': true},
        ]),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('All done'), findsOneWidget);
      expect(find.text('2 ticked items'), findsOneWidget);
    });

    testWidgets('a reminder is on the card, not only inside the editor',
        (tester) async {
      // A note that is going to interrupt you at nine tomorrow should say so
      // where you can see it.
      final when = DateTime.now().add(const Duration(days: 1));
      await tester.pumpWidget(_app(notes: [
        _note(1, 'Call the plumber', remindAt: when),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Tomorrow'), findsOneWidget);
    });
  });

  group('selecting several', () {
    testWidgets('a long press starts a selection', (tester) async {
      await tester.pumpWidget(_app(notes: [_note(1, 'One'), _note(2, 'Two')]));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('One'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('a plain tap then adds to it instead of opening the editor',
        (tester) async {
      // Opening the editor mid-selection is the commonest way a multi-select is
      // lost, and losing it means starting the whole selection again.
      await tester.pumpWidget(_app(notes: [_note(1, 'One'), _note(2, 'Two')]));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('One'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('tapping a chosen one again takes it out', (tester) async {
      await tester.pumpWidget(_app(notes: [_note(1, 'One'), _note(2, 'Two')]));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('One'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsNothing);
      // Scoped: "Notes" is the app bar title AND a bucket chip below it.
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Notes')),
          findsOneWidget);
    });

    testWidgets('the whole selection is acted on in ONE request',
        (tester) async {
      // Not a loop: eleven round trips from a phone each fail on their own, so
      // a flaky connection leaves some archived and some not with no way to
      // tell which.
      final sent = <List<Object>>[];
      await tester.pumpWidget(_app(
        notes: [_note(1, 'One'), _note(2, 'Two'), _note(3, 'Three')],
        onBulk: (a, ids) => sent.add([a, ids]),
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('One'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Three'));
      await tester.pumpAndSettle();
      await tester.tap(_bar('Archive'));
      await tester.pumpAndSettle();

      expect(sent, hasLength(1));
      expect(sent.single[0], 'archive');
      expect(sent.single[1], [1, 3]);
    });

    testWidgets('and it can be taken back', (tester) async {
      // A mis-tap that archives eleven notes cannot be unpicked by hand
      // afterwards — you no longer know which eleven.
      await tester.pumpWidget(_app(
        notes: [_note(1, 'One'), _note(2, 'Two')],
        onBulk: (_, _) {},
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('One'));
      await tester.pumpAndSettle();
      await tester.tap(_bar('Archive'));
      await tester.pumpAndSettle();

      expect(find.text('1 note archived'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('leaving the selection puts the title back', (tester) async {
      await tester.pumpWidget(_app(notes: [_note(1, 'One')]));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('One'));
      await tester.pumpAndSettle();
      await tester.tap(_bar('Stop selecting'));
      await tester.pumpAndSettle();

      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Notes')),
          findsOneWidget);
      expect(find.text('1 selected'), findsNothing);
    });

    testWidgets('pin, colour, label, archive and bin are all offered',
        (tester) async {
      await tester.pumpWidget(_app(notes: [_note(1, 'One')]));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('One'));
      await tester.pumpAndSettle();

      for (final tip in ['Pin', 'Colour', 'Label', 'Archive', 'Bin']) {
        expect(_bar(tip), findsOneWidget, reason: '$tip is missing');
      }
    });
  });

  testWidgets('a card lays out on the narrowest phone', (tester) async {
    // Half the width of a 320pt phone is not much, and this screen's cards hold
    // a title, text, chips, a reminder and a row of controls. The layout sweep
    // never drew one — it stands this screen up without a server, so it only
    // ever rendered the spinner — which is how a four-icon action row that
    // overflowed by 42 pixels got written.
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(notes: [
      _note(1, 'Call the plumber about the kitchen tap',
          body: 'He said any morning before ten, and to ring twice.',
          labels: ['Home', 'Urgent'],
          remindAt: DateTime.now().add(const Duration(days: 1))),
    ]));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}