// The sync engine, and the Sync screen.
//
// The engine is tested against a fake server rather than a real one, because
// what needs pinning is how it reacts to each ANSWER — and the answers worth
// testing (a dropped reply, a conflict, a refusal, a server too old to know
// what sync is) are the ones a real server will not produce on demand.
//
// The server side is verified separately, against a live server, by
// backend/verify_sync.py — 35 checks including "replaying a create leaves
// exactly one record".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/api.dart';
import 'package:safenest/offline/store.dart';
import 'package:safenest/offline/sync.dart';
import 'package:safenest/screens/sync_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

import 'offline_store_test.dart' show memSecure;

/// An Api that answers from a script instead of a network.
class _FakeApi implements Api {
  _FakeApi({this.onReplay, this.capabilitiesError});

  final ApiError? capabilitiesError;
  final List<dynamic> Function(List<dynamic> ops)? onReplay;

  final sent = <List<dynamic>>[];

  @override
  Future<dynamic> get(String path, [Map<String, String>? query]) async {
    if (path.startsWith('/api/sync/capabilities')) {
      if (capabilitiesError != null) throw capabilitiesError!;
      return {'protocol': 1};
    }
    throw ApiError(404, 'no such path');
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    if (path == '/api/sync/replay') {
      final ops = ((body as Map)['ops'] as List);
      sent.add(ops);
      return {'results': onReplay?.call(ops) ?? []};
    }
    throw ApiError(404, 'no such path');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Map<String, dynamic> _ok(dynamic op, {int? id, String status = 'ok'}) => {
      'client_uuid': (op as Map)['client_uuid'],
      'status': status,
      'server_id': ?id,
    };

Future<OfflineStore> _store() async {
  final s = OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);
  await s.clearEverything();
  return s;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('it refuses to sync into a server that cannot remember', () {
    test('a 404 on capabilities stops everything, and says so', () async {
      final store = await _store();
      await store.enqueue(
          module: 'expenses', op: Op.create, localId: 1, payload: {'note': 'x'});
      final api = _FakeApi(capabilitiesError: ApiError(404, 'Not Found'));
      final sync = SyncService(store: store, api: () => api);

      final r = await sync.run();

      expect(r.blocked, isTrue);
      expect(r.blockedReason, contains('too old'));
      expect(api.sent, isEmpty,
          reason: 'replaying into a server with no memory of what it accepted '
              'is what creates a second copy of every record');
      expect(await store.pendingCount(), 1, reason: 'and nothing was dropped');
      await store.close();
    });

    test('being unable to REACH it is not the same as it being old', () async {
      final store = await _store();
      await store.enqueue(module: 'expenses', op: Op.create, localId: 1);
      final api = _FakeApi(capabilitiesError: ApiError(0, 'Connection refused'));
      final sync = SyncService(store: store, api: () => api);

      final r = await sync.run();

      expect(r.blocked, isFalse,
          reason: 'an unreachable computer must not be reported as an '
              'out-of-date one — they need different actions');
      await store.close();
    });
  });

  group('what lands is forgotten, what does not is kept', () {
    test('a saved op is cleared from the queue', () async {
      final store = await _store();
      await store.enqueue(
          module: 'expenses', op: Op.create, localId: 1, payload: {'note': 'a'});
      final api = _FakeApi(onReplay: (ops) => [_ok(ops.first, id: 5)]);
      final sync = SyncService(store: store, api: () => api);

      final r = await sync.run();

      expect(r.saved, 1);
      expect(await store.pendingCount(), 0);
      await store.close();
    });

    test('a refusal is KEPT, with the reason', () async {
      final store = await _store();
      await store.enqueue(module: 'expenses', op: Op.create, localId: 1);
      final api = _FakeApi(onReplay: (ops) => [
            {
              'client_uuid': (ops.first as Map)['client_uuid'],
              'status': 'refused',
              'message': 'Enter an amount greater than zero',
            }
          ]);
      final sync = SyncService(store: store, api: () => api);

      final r = await sync.run();

      expect(r.refused, 1);
      expect(await store.pendingCount(), 1);
      final left = (await store.allPending()).single;
      expect(left.lastError, 'Enter an amount greater than zero');
      expect(r.problems, contains('Enter an amount greater than zero'));
      await store.close();
    });

    test('a conflict is kept, not applied and not thrown away', () async {
      final store = await _store();
      await store.enqueue(
          module: 'expenses', op: Op.update, serverId: 9,
          baseUpdatedAt: '2026-08-01T00:00:00', payload: {'note': 'mine'});
      final api = _FakeApi(onReplay: (ops) => [
            {
              'client_uuid': (ops.first as Map)['client_uuid'],
              'status': 'conflict',
              'server_id': 9,
              'message': 'Changed on the computer as well',
            }
          ]);
      final sync = SyncService(store: store, api: () => api);

      final r = await sync.run();

      expect(r.conflicts, 1);
      expect(await store.pendingCount(), 1,
          reason: 'the owner decides; nothing is discarded for them');
      await store.close();
    });

    test('an op the server never mentions is kept', () async {
      final store = await _store();
      await store.enqueue(module: 'expenses', op: Op.create, localId: 1);
      final api = _FakeApi(onReplay: (ops) => []); // answered, said nothing
      final sync = SyncService(store: store, api: () => api);

      final r = await sync.run();

      expect(r.failed, 1);
      expect(await store.pendingCount(), 1,
          reason: 'it may or may not have landed — the uuid stops a duplicate, '
              'but nothing can recover a record that was dropped');
      await store.close();
    });

    test('eight of ten landing leaves exactly the two behind', () async {
      final store = await _store();
      for (var i = 1; i <= 10; i++) {
        await store.enqueue(
            module: 'expenses', op: Op.create, localId: i, payload: {'n': i});
      }
      var n = 0;
      final api = _FakeApi(onReplay: (ops) => [
            for (final o in ops)
              (++n == 4 || n == 8)
                  ? {
                      'client_uuid': (o as Map)['client_uuid'],
                      'status': 'refused',
                      'message': 'no',
                    }
                  : _ok(o, id: n)
          ]);
      final sync = SyncService(store: store, api: () => api);

      final r = await sync.run();

      expect(r.saved, 8);
      expect(r.refused, 2);
      expect(await store.pendingCount(), 2);
      await store.close();
    });
  });

  group('order and identity', () {
    test('a create that lands re-points the edits that followed it', () async {
      final store = await _store();
      final local = await store.nextLocalId('todos');
      await store.enqueue(
          module: 'todos', op: Op.create, localId: local, payload: {'t': 'a'});
      await store.enqueue(
          module: 'todos', op: Op.update, localId: local, payload: {'t': 'b'});

      // Only the create is answered this round; the edit is left unanswered so
      // it stays queued and can be inspected.
      final api = _FakeApi(onReplay: (ops) => [_ok(ops.first, id: 42)]);
      final sync = SyncService(store: store, api: () => api);
      await sync.run();

      final left = (await store.allPending()).single;
      expect(left.op, Op.update);
      expect(left.serverId, 42,
          reason: 'an edit still pointing at a local id replays against nothing');
      await store.close();
    });

    test('operations are sent oldest first', () async {
      final store = await _store();
      await store.enqueue(module: 'todos', op: Op.create, localId: 1, payload: {'n': 1});
      await store.enqueue(module: 'todos', op: Op.update, localId: 1, payload: {'n': 2});
      final api = _FakeApi(onReplay: (ops) => [for (final o in ops) _ok(o, id: 1)]);
      final sync = SyncService(store: store, api: () => api);
      await sync.run();

      final order = [for (final o in api.sent.first) (o as Map)['op']];
      expect(order, ['create', 'update']);
      await store.close();
    });

    test('the same uuid is reused on a retry, so it cannot double-create', () async {
      final store = await _store();
      await store.enqueue(module: 'todos', op: Op.create, localId: 1);
      final first = _FakeApi(onReplay: (ops) => []); // no answer
      await SyncService(store: store, api: () => first).run();

      final second = _FakeApi(onReplay: (ops) => [_ok(ops.first, id: 3)]);
      await SyncService(store: store, api: () => second).run();

      expect((first.sent.first.first as Map)['client_uuid'],
          (second.sent.first.first as Map)['client_uuid'],
          reason: 'a fresh uuid per attempt is exactly how a retry makes a '
              'second record');
      await store.close();
    });
  });

  group('progress never lies', () {
    test('an empty queue reports nothing rather than a full bar', () async {
      final store = await _store();
      final sync = SyncService(store: store, api: () => _FakeApi());
      final r = await sync.run();
      expect(r.sent, 0);
      expect(sync.progress, 0.0);
      await store.close();
    });

    test('progress stays within 0..1', () async {
      final store = await _store();
      for (var i = 1; i <= 3; i++) {
        await store.enqueue(module: 'todos', op: Op.create, localId: i);
      }
      final api = _FakeApi(onReplay: (ops) => [for (final o in ops) _ok(o, id: 1)]);
      final sync = SyncService(store: store, api: () => api);
      await sync.run();
      expect(sync.progress, inInclusiveRange(0.0, 1.0));
      await store.close();
    });
  });

  group('the Sync screen', () {
    Widget wrap(Widget child, SyncService sync) => MultiProvider(
          providers: [
            ChangeNotifierProvider<Session>(create: (_) => Session()),
            ChangeNotifierProvider<SyncService>.value(value: sync),
          ],
          child: MaterialApp(
            theme: buildTheme(const Brand(), Brightness.light),
            home: child,
          ),
        );

    testWidgets('says plainly that unsent changes exist only here',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // NOT `await _store()`. testWidgets runs inside a FakeAsync zone, so a
      // real sqflite call never completes and the test hangs until it times
      // out. Constructing the store is synchronous and it opens the database
      // lazily — and with `initialPending` supplied the screen never reads it.
      final sync = SyncService(
          store: OfflineStore(secure: memSecure(), path: inMemoryDatabasePath),
          api: () => _FakeApi());
      final ops = [
        PendingOp(
          seq: 1, module: 'expenses', op: Op.create,
          clientUuid: 'u1', localId: 1, serverId: null,
          payload: const {}, baseUpdatedAt: null,
          state: OpState.pending, tries: 0, lastError: null,
          createdAt: DateTime(2026, 8, 25),
        ),
      ];

      await tester.pumpWidget(wrap(SyncScreen(initialPending: ops), sync));
      await tester.pump();

      expect(find.textContaining('only on this phone'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refused item does not look like one that is queued',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // NOT `await _store()`. testWidgets runs inside a FakeAsync zone, so a
      // real sqflite call never completes and the test hangs until it times
      // out. Constructing the store is synchronous and it opens the database
      // lazily — and with `initialPending` supplied the screen never reads it.
      final sync = SyncService(
          store: OfflineStore(secure: memSecure(), path: inMemoryDatabasePath),
          api: () => _FakeApi());
      final ops = [
        PendingOp(
          seq: 1, module: 'expenses', op: Op.update,
          clientUuid: 'u1', localId: null, serverId: 4,
          payload: const {}, baseUpdatedAt: null,
          state: OpState.failed, tries: 2,
          lastError: 'Enter an amount greater than zero',
          createdAt: DateTime(2026, 8, 25),
        ),
      ];

      await tester.pumpWidget(wrap(SyncScreen(initialPending: ops), sync));
      await tester.pump();

      expect(find.text('Enter an amount greater than zero'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsNothing);
    });

    testWidgets('with nothing waiting, the button is disabled', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final sync = SyncService(
          store: OfflineStore(secure: memSecure(), path: inMemoryDatabasePath),
          api: () => _FakeApi());
      await tester.pumpWidget(
          wrap(const SyncScreen(initialPending: []), sync));
      await tester.pump();

      expect(find.text('Everything is on your computer'), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });
  });
}
