// Working offline, and catching up on its own.
//
// The owner put the requirement plainly: "if internet is available and the
// laptop is connected then sync, else it should work offline, then when the
// system is available it should auto sync". Two things were wrong.
//
// NOTHING SYNCED BY ITSELF. Anything typed with the computer away sat in the
// queue until somebody opened the Sync screen and pressed the button.
//
// AND A SAVE MADE OFFLINE TOOK TWO TIMEOUTS TO APPEAR. The POST waited for one,
// queued the record, and then the list reload waited for a second before
// falling back to what the phone holds — with the new row missing from the
// screen for the whole of both. Reported as "when I create it is not showing
// instantly".
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/api.dart';
import 'package:safenest/offline/autosync.dart';
import 'package:safenest/offline/mode.dart';
import 'package:safenest/offline/records.dart';
import 'package:safenest/offline/store.dart';
import 'package:safenest/offline/sync.dart';

import 'offline_store_test.dart' show memSecure;

/// An Api that is simply not there — the ordinary case for this product.
class _Away implements Api {
  int calls = 0;

  @override
  Future<dynamic> get(String path, [Map<String, String>? query]) async {
    calls++;
    throw ApiError(0, 'Could not reach your SafeNest');
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    calls++;
    throw ApiError(0, 'Could not reach your SafeNest');
  }

  @override
  Future<dynamic> put(String path, [Object? body]) async {
    calls++;
    throw ApiError(0, 'Could not reach your SafeNest');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A SyncService that records that it was asked, and says how it went.
class _FakeSync implements SyncService {
  _FakeSync({this.works = true});
  bool works;
  int runs = 0;

  @override
  Future<SyncResult> run() async {
    runs++;
    if (!works) return const SyncResult.blocked('Could not reach your SafeNest');
    return const SyncResult(
        sent: 1, saved: 1, already: 0, conflicts: 0, refused: 0, failed: 0,
        problems: []);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

var _seq = 0;
Future<OfflineStore> _store() async {
  final s = OfflineStore(
      secure: memSecure(), path: 'autosync${_seq++}.db');
  await s.clearEverything();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  group('knowing the computer is away', () {
    test('a failure is remembered, so the next call does not wait for it', () {
      final mode = OfflineMode();
      expect(mode.computerAway, isFalse);
      mode.markAway();
      expect(mode.computerAway, isTrue);
    });

    test('it is not the same thing as the owner choosing to work offline', () {
      // A network hiccup silently flipping a mode somebody chose is how a
      // setting stops meaning anything.
      final mode = OfflineMode();
      mode.markAway();
      expect(mode.on, isFalse);
    });

    test('reaching it forgets the failure at once', () {
      // Coming back into range should feel immediate, not wait the window out.
      final mode = OfflineMode();
      mode.markAway();
      mode.markReachable();
      expect(mode.computerAway, isFalse);
    });

    test('it says how long is left, so a screen can explain itself', () {
      final mode = OfflineMode();
      mode.markAway();
      expect(mode.retryIn.inSeconds, greaterThan(0));
    });
  });

  group('saving with the computer away', () {
    test('the second call does not pay for the timeout again', () async {
      // THE BUG. One timeout for the POST is unavoidable; a second for the
      // reload that follows it is what made the new row invisible.
      final store = await _store();
      final mode = OfflineMode();
      final records = OfflineRecords(store: store, mode: mode);
      final api = _Away();

      await records.save(api, 'reminders', body: {'title': 'Bin day'});
      expect(api.calls, 1);
      expect(mode.computerAway, isTrue);

      await records.list(api, 'reminders');
      expect(api.calls, 1,
          reason: 'the reload must come from the phone, not from a second wait');
    });

    test('and the new row is there straight away', () async {
      final store = await _store();
      final mode = OfflineMode();
      final records = OfflineRecords(store: store, mode: mode);
      final api = _Away();

      final where =
          await records.save(api, 'reminders', body: {'title': 'Bin day'});
      expect(where, Saved.queued);

      final loaded = await records.list(api, 'reminders');
      expect([for (final r in loaded.rows) r['title']], contains('Bin day'));
      expect(loaded.fromCache, isTrue);
    });

    test('it is still marked as not yet sent', () async {
      // "Saved" and "saved on this phone" are different promises and must not
      // read the same.
      final store = await _store();
      final mode = OfflineMode();
      final records = OfflineRecords(store: store, mode: mode);
      final api = _Away();

      await records.save(api, 'reminders', body: {'title': 'Bin day'});
      final loaded = await records.list(api, 'reminders');
      expect(loaded.rows.single['_pending'], isTrue);
    });
  });

  group('catching up on its own', () {
    test('nothing queued means nothing is sent', () async {
      final store = await _store();
      final sync = _FakeSync();
      final auto = AutoSync(sync: sync, store: store, mode: OfflineMode());
      addTearDown(auto.dispose);

      auto.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sync.runs, 0);
    });

    test('something queued is sent without anybody pressing anything',
        () async {
      final store = await _store();
      await store.enqueue(
          module: 'reminders', op: Op.create, localId: 1,
          payload: {'title': 'Bin day'});
      final sync = _FakeSync();
      final auto = AutoSync(sync: sync, store: store, mode: OfflineMode());
      addTearDown(auto.dispose);

      auto.start();
      // Past the two-second settle after a resume or a start.
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(sync.runs, 1);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('it does not overrule the owner asking to work from the phone',
        () async {
      // Pushing anyway would be the app overruling a setting somebody chose.
      final store = await _store();
      await store.enqueue(
          module: 'reminders', op: Op.create, localId: 1, payload: {'a': 1});
      final mode = OfflineMode();
      await mode.set(true);
      final sync = _FakeSync();
      final auto = AutoSync(sync: sync, store: store, mode: mode);
      addTearDown(auto.dispose);

      auto.start();
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(sync.runs, 0);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('it waits for a sign-in rather than failing for no reason', () async {
      final store = await _store();
      await store.enqueue(
          module: 'reminders', op: Op.create, localId: 1, payload: {'a': 1});
      final sync = _FakeSync();
      final auto = AutoSync(
          sync: sync, store: store, mode: OfflineMode(),
          signedIn: () => false);
      addTearDown(auto.dispose);

      auto.start();
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(sync.runs, 0);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('coming back to the app is a reason to try', () async {
      final store = await _store();
      await store.enqueue(
          module: 'reminders', op: Op.create, localId: 1, payload: {'a': 1});
      final sync = _FakeSync();
      final auto = AutoSync(sync: sync, store: store, mode: OfflineMode());
      addTearDown(auto.dispose);

      auto.start();
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      final after = sync.runs;

      auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(sync.runs, greaterThan(after),
          reason: 'you type on the bus, you get home, you open the app');
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('a memory waiting to go up counts as work, too', () async {
      // Life Memory pushes its own table rather than the journal, so a queue
      // check that only looked at `pending` would leave a spoken memory sitting
      // on the phone for ever with nothing to send it.
      final store = await _store();
      await store.addMemory(body: 'said offline', saidAt: DateTime(2026, 10, 3));
      final sync = _FakeSync();
      final auto = AutoSync(sync: sync, store: store, mode: OfflineMode());
      addTearDown(auto.dispose);

      auto.start();
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(sync.runs, 1);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
