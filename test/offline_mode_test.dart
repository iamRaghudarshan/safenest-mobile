// The offline switch and the list of what works without the computer.
//
// The list is the part worth pinning. A screen that promises a module works
// offline when its screen never touches the store would be the exact defect
// CLAUDE.md §10 is about — a control that looks like it does something and does
// nothing — so these tests tie the promise to the code that keeps it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/api.dart';
import 'package:safenest/modules.dart';
import 'package:safenest/offline/mode.dart';
import 'package:safenest/offline/records.dart';
import 'package:safenest/offline/store.dart';
import 'package:safenest/offline/sync.dart';
import 'package:safenest/screens/offline_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

import 'offline_store_test.dart' show memSecure;

Widget _wrap(Widget child, {OfflineMode? mode, SyncService? sync}) {
  final store = OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<Session>(create: (_) => Session()),
      ChangeNotifierProvider<OfflineMode>.value(value: mode ?? OfflineMode()),
      ChangeNotifierProvider<SyncService>.value(
        value: sync ??
            SyncService(store: store, api: () => Api(baseUrl: '')),
      ),
    ],
    child: MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: child,
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 667);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // OfflineMode reads and writes SharedPreferences. Without a mock the
    // platform channel has nobody on the other end and the call never returns,
    // which shows up as a test that hangs rather than one that fails.
    SharedPreferences.setMockInitialValues({});
    // flutter_test answers every HTTP request with a fake 400. That is right
    // for most tests and wrong for the two below, whose whole subject is what
    // happens when the computer cannot be REACHED — a 400 is the computer
    // answering, which is the opposite case.
    HttpOverrides.global = null;
  });

  group('the list says what is true, and only what is true', () {
    test('everything that needs the computer says WHY', () {
      final blocked = {for (final m in needsComputer) m.key: m.reason};
      // Vault, Photos and Documents will never be offline. Notes and Habits
      // are here only because their screens are not wired yet — the reason
      // text says which is which, and this test does not care, because what
      // matters is that neither kind is left unexplained.
      expect(blocked.keys, containsAll(<String>['gallery', 'documents']));
      for (final entry in blocked.entries) {
        expect(entry.value, isNotNull);
        expect(entry.value!.length, greaterThan(20),
            reason: '"${entry.key} unavailable" invites a bug report; the '
                'reason is what stops one');
      }
    });

    // The vault WAS excluded, and is now included at the owner's explicit
    // request. What is pinned is no longer "it must be absent" but the two
    // things that make its presence defensible.
    test('vault is offline now — the owner asked for it', () {
      expect(worksOffline.map((m) => m.key), contains('vault'));
    });

    test('the vault is only cached when Working offline is ON', () async {
      final store = OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);
      await store.clearEverything();
      final off = OfflineRecords(store: store, mode: OfflineMode());

      // Mode off and the computer unreachable: it must not have written a
      // vault to disk on the way past. A phone that never leaves the house
      // should never be holding the passwords.
      try {
        await off.list(Api(baseUrl: 'http://127.0.0.1:1'), 'vault');
      } catch (_) {/* unreachable is fine; the point is what was stored */}
      final held = await store.read('vault');
      expect(held, isEmpty,
          reason: 'the vault must not be cached until the owner turns Working '
              'offline on');
      await store.close();
    });

    // THE TEST THAT WOULD HAVE CAUGHT IT. The first version of this listed the
    // module keys by hand, and 'todo' was written in both the source and the
    // test — so the test agreed with the typo instead of with the app, and
    // To-dos silently stopped being an offline module while the screen went on
    // promising it was one. Compare against the REAL specs.
    // Screens that were wired to the offline store BY HAND, rather than
    // inheriting it from ModuleListScreen. Every addition here is a real piece
    // of work on a real screen — the list exists so that promising a module
    // offline requires having done it, not merely having meant to.
    const wiredByHand = {'vault', 'notes', 'habits'};

    test('every module promised offline is genuinely wired to the store', () {
      final generic = {for (final m in kModules) m.key};
      for (final m in worksOffline) {
        expect(generic.contains(m.key) || wiredByHand.contains(m.key), isTrue,
            reason: '"${m.key}" is promised offline but nothing about it '
                'touches the offline store — it is neither a module of '
                'ModuleListScreen nor a screen wired by hand');
      }
    });

    test('everything except photos and documents works offline', () {
      // What the owner asked for, stated as the invariant. If a module is ever
      // added, it belongs in one of the two halves deliberately — and the test
      // above will refuse it in the working half until its screen is wired.
      expect(needsComputer.map((m) => m.key).toSet(), {'gallery', 'documents'});
    });

    test('every module promised offline is one the server will sync', () {
      // Mirrors SYNCABLE in backend/app/routers/sync.py. A module promised here
      // and refused there would queue work that can never be delivered.
      const serverSyncable = {
        'expenses', 'loans', 'cards', 'insurance', 'investments',
        'reminders', 'todos', 'notes', 'habits', 'vault',
      };
      for (final m in worksOffline) {
        expect(serverSyncable, contains(m.key),
            reason: '${m.key} is promised offline but the server will not '
                'accept it — see SYNCABLE in sync.py');
      }
    });

    test('no module is listed twice, or in both halves', () {
      final keys = offlineModules.map((m) => m.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  group('the switch', () {
    test('defaults to off — the app already copes without being told', () {
      expect(OfflineMode().on, isFalse);
    });

    test('changing it notifies, so screens follow', () async {
      final mode = OfflineMode();
      var told = 0;
      mode.addListener(() => told++);
      await mode.set(true);
      expect(mode.on, isTrue);
      expect(told, 1);
      await mode.set(true);
      expect(told, 1, reason: 'setting it to what it already is is not a change');
    });
  });

  group('the screen', () {
    testWidgets('shows both halves, and fits an iPhone SE', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const OfflineScreen()));
      await tester.pump();

      expect(find.text('Work from this phone'), findsOneWidget);
      expect(find.text('Works without your computer'), findsOneWidget);
      // Below the fold on an SE, and a ListView does not build what it has not
      // reached — so scroll to it rather than asserting on an unbuilt widget.
      await tester.scrollUntilVisible(find.text('Needs your computer'), 220,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Needs your computer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists Vault as working, and Photos as not', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const OfflineScreen()));
      await tester.pump();

      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Vault'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Photos'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.textContaining('too large to hold twice'), findsOneWidget);
    });

    testWidgets('the switch reflects the setting', (tester) async {
      _phone(tester);
      final mode = OfflineMode();
      await mode.set(true);
      await tester.pumpWidget(_wrap(const OfflineScreen(), mode: mode));
      await tester.pump();

      final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.value, isTrue);
      expect(find.textContaining('Nothing is sent until you press Sync'),
          findsOneWidget);
    });
  });

  group('records go to the right place', () {
    test('a module that is not offline-capable is never queued', () async {
      // gallery, not vault — the vault syncs now.
      final store = OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);
      await store.clearEverything();
      final records = OfflineRecords(store: store, mode: OfflineMode());

      // No server here at all, so an offline-capable module would queue. A
      // non-capable one must throw instead of quietly filing work that the
      // sync endpoint would refuse for ever.
      await expectLater(
        records.save(Api(baseUrl: 'http://127.0.0.1:1'), 'gallery',
            body: {'title': 'x'}),
        throwsA(anything),
      );
      expect(await store.pendingCount(), 0);
      await store.close();
    });

    test('an unreachable computer queues the save instead of losing it',
        () async {
      final store = OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);
      await store.clearEverything();
      final records = OfflineRecords(store: store, mode: OfflineMode());

      // Port 1 refuses immediately: "cannot reach it", not "it said no".
      final where = await records.save(
          Api(baseUrl: 'http://127.0.0.1:1'), 'expenses',
          body: {'note': 'queued please', 'amount': 5});

      expect(where, Saved.queued);
      expect(await store.pendingCount(), 1);
      final op = (await store.allPending()).single;
      expect(op.op, Op.create);
      expect(op.payload['note'], 'queued please');
      await store.close();
    });

    test('in offline mode it does not even try the network', () async {
      final store = OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);
      await store.clearEverything();
      final mode = OfflineMode();
      await mode.set(true);
      final records = OfflineRecords(store: store, mode: mode);

      final started = DateTime.now();
      final where = await records.save(
          // An address that would take a while to fail if it were tried.
          Api(baseUrl: 'http://10.255.255.1:8080'), 'expenses',
          body: {'note': 'straight to the queue', 'amount': 1});
      final took = DateTime.now().difference(started);

      expect(where, Saved.queued);
      expect(took.inSeconds, lessThan(2),
          reason: 'the owner asked to work from the phone; stalling on a '
              'timeout first has not honoured that');
      await store.close();
    });
  });

  group('a save made offline actually shows up', () {
    // THE DEFECT THIS PINS. The record sheet answers `true` when the computer
    // took the record and `'queued'` when the phone is holding it. The sheet was
    // opened as showModalBottomSheet<bool>, so the second answer could not
    // travel — it arrived as null, `saved == true` was false, the list never
    // reloaded, and a record saved offline simply never appeared. It had been
    // queued correctly the whole time; nothing on screen said so. Reported from
    // a real phone as "saving offline does not work".
    test('an offline save is readable straight back out of the store', () async {
      final store = OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);
      await store.clearEverything();
      final records = OfflineRecords(store: store, mode: OfflineMode());

      await records.save(Api(baseUrl: 'http://127.0.0.1:1'), 'expenses',
          body: {'note': 'bought chai', 'amount': 20, 'category': 'Food'});

      // What the list would show. If this is empty the record is invisible even
      // though it is safely queued, which is the shape of the bug above.
      final shown = await records.list(Api(baseUrl: 'http://127.0.0.1:1'), 'expenses');
      expect(shown.rows, hasLength(1));
      expect(shown.rows.single['note'], 'bought chai');
      expect(shown.rows.single['_pending'], isTrue,
          reason: 'the row has to be marked so the screen can show it is '
              'not on the computer yet');
      expect(shown.fromCache, isTrue);
      await store.close();
    });

    test('to-dos queue too — the key must be the real one', () async {
      final store = OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);
      await store.clearEverything();
      final records = OfflineRecords(store: store, mode: OfflineMode());

      // 'todos', as kModules has it. With 'todo' in the offline list this fell
      // through to the online path and threw instead of queueing.
      final where = await records.save(
          Api(baseUrl: 'http://127.0.0.1:1'), 'todos',
          body: {'title': 'call the bank'});

      expect(where, Saved.queued);
      expect(await store.pendingCount(), 1);
      await store.close();
    });
  });
}
