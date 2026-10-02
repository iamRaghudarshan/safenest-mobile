// Telling Life Memory something, all the way through.
//
// This is the flow the module exists for and it cannot be checked by hand on
// this machine: it needs a microphone, and no computer here has one. The fake
// dictation in lib/memory/dictation.dart is there so this test can speak.
//
// NO DATABASE HERE, deliberately, and it cost an hour to learn why. A widget
// test runs in a zone with a fake clock where real file IO callbacks are never
// delivered, so a screen that opens a database in initState never gets past
// its spinner and the file HANGS rather than failing — which reads as a hang
// in the screen, and the screen has nothing to do with it. The store is
// covered against real SQLite in memory_store_test.dart. What is left to check
// is the FLOW, and `debugRows` and `onKept` let that be checked without a disk.
//
// What is pinned is the promise the design makes: your words are kept exactly
// as you said them, and nothing is tagged unless you tap it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/memory/attach.dart';
import 'package:safenest/memory/dictation.dart';
import 'package:safenest/memory/facts.dart';
import 'package:safenest/screens/life_memory_screen.dart';
import 'package:safenest/theme.dart';

/// What the screen would have saved.
class Kept {
  String? words;
  bool? spoken;
  List<Fact> facts = const [];
  String? photo;
}

Widget _app(
  Dictation mic, {
  List<Map<String, dynamic>> rows = const [],
  Kept? kept,
  PhotoSource? photos,
}) =>
    MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: LifeMemoryScreen(
        dictation: mic,
        photos: photos ?? FakePhotos(),
        debugRows: rows,
        onKept: kept == null
            ? null
            : (w, s, f, p) {
                kept.words = w;
                kept.spoken = s;
                kept.facts = f;
                kept.photo = p;
              },
      ),
    );

void main() {
  testWidgets('an empty thread invites you to say something', (tester) async {
    await tester.pumpWidget(_app(FakeDictation()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing yet'), findsOneWidget);
    expect(find.textContaining('microphone'), findsOneWidget);
  });

  testWidgets('a phone with no microphone says so, and still takes typing',
      (tester) async {
    // Offering a microphone that cannot work is worse than not offering one:
    // the failure arrives after somebody has spoken a paragraph.
    await tester.pumpWidget(_app(FakeDictation(canListen: false)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Type anything worth keeping'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });

  testWidgets('speaking it, confirming it, keeping it', (tester) async {
    final kept = Kept();
    final mic = FakeDictation();
    await tester.pumpWidget(_app(mic, kept: kept));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    expect(mic.listening, isTrue);

    mic.say('Bought the washing machine from Vijay Sales. Two year warranty.');
    await tester.pumpAndSettle();
    // What is being heard is on screen while it is being said — a microphone
    // that shows nothing is one people talk into twice.
    expect(find.textContaining('washing machine'), findsWidgets);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    // The confirm step, with what it heard offered rather than applied.
    expect(find.text('Before it saves'), findsOneWidget);
    expect(find.text('tap to keep'), findsOneWidget);
    expect(find.textContaining('Warranty ends'), findsOneWidget);

    await tester.tap(find.text('Keep this'));
    await tester.pumpAndSettle();

    expect(kept.words,
        'Bought the washing machine from Vijay Sales. Two year warranty.');
    expect(kept.spoken, isTrue);
  });

  testWidgets('only the expiry is kept unasked; the rest wait for a tap',
      (tester) async {
    // THE RULE THE MODULE TURNS ON. A warranty is the one fact that becomes a
    // reminder, so it is pre-ticked and everything else is not — a store that
    // files what it merely guessed is one you stop trusting the first time it
    // is wrong.
    final kept = Kept();
    final mic = FakeDictation();
    await tester.pumpWidget(_app(mic, kept: kept));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    mic.say('Bought it from Croma in Indiranagar. Three year warranty.');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    // Croma and Indiranagar were both found and are both offered…
    expect(find.text('Croma'), findsOneWidget);
    expect(find.text('Indiranagar'), findsOneWidget);

    await tester.tap(find.text('Keep this'));
    await tester.pumpAndSettle();

    // …and neither was kept, because neither was tapped.
    expect(kept.facts, hasLength(1), reason: 'only the pre-ticked expiry');
    expect(kept.facts.single.kind, FactKind.expiry);
  });

  testWidgets('tapping a suggestion keeps it too', (tester) async {
    final kept = Kept();
    final mic = FakeDictation();
    await tester.pumpWidget(_app(mic, kept: kept));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    mic.say('Took this at Lalbagh with Appa.');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lalbagh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep this'));
    await tester.pumpAndSettle();

    expect([for (final f in kept.facts) f.value], contains('Lalbagh'));
  });

  testWidgets('tapping twice puts it back, so a mis-tap costs nothing',
      (tester) async {
    final kept = Kept();
    final mic = FakeDictation();
    await tester.pumpWidget(_app(mic, kept: kept));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    mic.say('Two year warranty on it.');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    // Pre-ticked; untick it.
    await tester.tap(find.textContaining('Warranty ends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep this'));
    await tester.pumpAndSettle();

    expect(kept.facts, isEmpty,
        reason: 'it was unticked, so it must not have been filed');
  });

  testWidgets('a memory with nothing to tag says so rather than guessing',
      (tester) async {
    final kept = Kept();
    final mic = FakeDictation();
    await tester.pumpWidget(_app(mic, kept: kept));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    mic.say('it rained all afternoon and we stayed in');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing to tag'), findsOneWidget);
    await tester.tap(find.text('Keep this'));
    await tester.pumpAndSettle();

    expect(kept.words, 'it rained all afternoon and we stayed in');
    expect(kept.facts, isEmpty);
  });

  testWidgets('typing works as well as speaking', (tester) async {
    final kept = Kept();
    await tester.pumpWidget(_app(FakeDictation(), kept: kept));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField), 'The spare key is with Ravi');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep this'));
    await tester.pumpAndSettle();

    expect(kept.words, 'The spare key is with Ravi');
    expect(kept.spoken, isFalse, reason: 'typed, not spoken');
  });

  testWidgets('a refused microphone is explained, not swallowed',
      (tester) async {
    await tester.pumpWidget(
        _app(FakeDictation(problem: DictationProblem.notAllowed)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();

    expect(find.textContaining('not been allowed'), findsOneWidget);
    // And the keyboard still works, which is the point of saying it at all.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a kept memory is drawn with its facts and where it lives',
      (tester) async {
    await tester.pumpWidget(_app(FakeDictation(), rows: [
      {
        'id': 1,
        'body': 'Amma says tamarind first',
        'said_at': DateTime.now().toIso8601String(),
        'spoken': 1,
        'server_id': null,
        'facts': [
          {'kind': 'person', 'value': 'Amma', 'at': null},
        ],
      }
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Amma says tamarind first'), findsOneWidget);
    expect(find.text('Amma'), findsOneWidget);
    expect(find.text('Nothing yet'), findsNothing);
    // On the phone and saying so — the only thing syncing will change.
    expect(find.text('on this phone'), findsOneWidget);
  });

  testWidgets('one that has reached the computer says that instead',
      (tester) async {
    await tester.pumpWidget(_app(FakeDictation(), rows: [
      {
        'id': 1,
        'body': 'already synced',
        'said_at': DateTime.now().toIso8601String(),
        'spoken': 0,
        'server_id': 42,
        'facts': const [],
      }
    ]));
    await tester.pumpAndSettle();

    expect(find.text('on your computer'), findsOneWidget);
    expect(find.text('on this phone'), findsNothing);
  });

  group('attaching a photograph', () {
    testWidgets('picked before the words, and it says it is waiting for them',
        (tester) async {
      // The order people do it in: find the picture, then say why it matters.
      final kept = Kept();
      await tester.pumpWidget(_app(FakeDictation(), kept: kept));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Recent photographs'), findsOneWidget);

      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Going on this one'), findsOneWidget);
    });

    testWidgets('it is kept with the words it was waiting for', (tester) async {
      final kept = Kept();
      await tester.pumpWidget(_app(FakeDictation(), kept: kept));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Lalbagh, flower show');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep this'));
      await tester.pumpAndSettle();

      expect(kept.words, 'Lalbagh, flower show');
      expect(kept.photo, isNotNull,
          reason: 'the picture has to reach the memory, not just the screen');
    });

    testWidgets('changing your mind about it costs one tap', (tester) async {
      final kept = Kept();
      await tester.pumpWidget(_app(FakeDictation(), kept: kept));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Not this one'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Going on this one'), findsNothing);

      await tester.enterText(find.byType(TextField), 'no picture on this one');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep this'));
      await tester.pumpAndSettle();

      expect(kept.photo, isNull);
    });

    testWidgets('a refused camera roll is explained, and typing still works',
        (tester) async {
      await tester.pumpWidget(
          _app(FakeDictation(), photos: FakePhotos(canSee: false)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('not been allowed to see your photographs'),
          findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a picture the phone cannot produce says so rather than '
        'saving a dead path', (tester) async {
      // A photo still in iCloud. Attaching a path that resolves to nothing
      // would show a grey box on the memory for ever, with nothing to explain
      // it.
      await tester.pumpWidget(
          _app(FakeDictation(), photos: FakePhotos(copies: false)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be read'), findsOneWidget);
      expect(find.textContaining('Going on this one'), findsNothing);
    });

    testWidgets('an empty camera roll says so instead of an empty sheet',
        (tester) async {
      await tester.pumpWidget(
          _app(FakeDictation(), photos: FakePhotos(count: 0)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('No photographs found'), findsOneWidget);
    });
  });

  testWidgets('asking is offered once there is something to ask about',
      (tester) async {
    // Disabled on an empty thread on purpose: a question screen with nothing
    // behind it can only ever answer "you have not told me anything".
    await tester.pumpWidget(_app(FakeDictation()));
    await tester.pumpAndSettle();
    expect(
        tester
            // The tooltip is built BY the IconButton, so it is a descendant of
            // it and not the other way round.
            .widget<IconButton>(find.ancestor(
                of: find.byTooltip('Ask a question'),
                matching: find.byType(IconButton)))
            .onPressed,
        isNull);
  });
}
