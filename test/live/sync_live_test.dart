// The phone's sync engine against a REAL server.
//
// WHY THIS EXISTS. Everything else about sync is tested against a fake Api on
// this side and hand-written JSON on that side, so the two halves are each
// proved correct against a description of the other. That is exactly the gap
// that produced the album_id defect: both ends were right, the contract between
// them was not, and nothing noticed until it reached a phone.
//
// So this drives the actual Dart client, over real HTTP, into the actual
// FastAPI server, and then asks the SERVER what it ended up holding.
//
// IT IS NOT PART OF `flutter test`. It needs a server running, so it lives
// under test/live/ and CI does not sweep it up. Run it by hand:
//
//   1. Start a throwaway server -- NEVER the live one on 8080:
//        cd finmate-react/backend
//        DB_ENGINE=sqlite DB_FILE=<scratch>/t.db JWT_SECRET=... MEDIA_SECRET=... \
//        VAULT_KEY_HEX=<64 hex> venv/Scripts/python -m uvicorn app.main:app \
//            --host 127.0.0.1 --port 8090
//   2. Seed an account on it (see backend/verify_sync.py for the pattern).
//   3. flutter test test/live/sync_live_test.dart \
//        --dart-define=SYNC_URL=http://127.0.0.1:8090 \
//        --dart-define=SYNC_EMAIL=live@test.local \
//        --dart-define=SYNC_PASSWORD=...
//
// With no SYNC_URL it skips rather than fails, so nobody has to remember it.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/api.dart';
import 'package:safenest/offline/store.dart';
import 'package:safenest/offline/sync.dart';

const _url = String.fromEnvironment('SYNC_URL');
const _email = String.fromEnvironment('SYNC_EMAIL');
const _password = String.fromEnvironment('SYNC_PASSWORD');

/// The Keychain does not exist in a test process.
class _MemSecure extends FlutterSecureStorage {
  final _mem = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _mem[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) _mem[key] = value;
  }
}

void main() {
  if (_url.isEmpty) {
    test('live sync (skipped — pass --dart-define=SYNC_URL to run)', () {},
        skip: 'No SYNC_URL given');
    return;
  }

  late String token;
  late Directory dir;
  late OfflineStore store;
  late SyncService sync;

  Api api() => Api(baseUrl: _url, token: token);

  setUpAll(() async {
    // flutter_test installs an HttpOverrides that answers every request with a
    // fake 400, which is right for unit tests and fatal here — the whole point
    // is to reach a real server.
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final r = await Api(baseUrl: _url)
        .post('/api/auth/login', {'email': _email, 'password': _password});
    token = '${(r as Map)['token']}';
    expect(token.length, greaterThan(20), reason: 'could not sign in');
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_live');
    store = OfflineStore(
        secure: _MemSecure(), path: p.join(dir.path, 'offline.db'));
    sync = SyncService(store: store, api: api);
  });

  tearDown(() async {
    await store.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<List<Map<String, dynamic>>> serverExpenses() async {
    final r = await api().get('/api/expenses');
    return [
      for (final e in ((r as Map)['items'] as List))
        Map<String, dynamic>.from(e as Map)
    ];
  }

  test('this server is one the phone will agree to sync with', () async {
    expect(await sync.whyNotSyncable(), isNull);
  });

  test('a record typed offline reaches the server, exactly once', () async {
    final before = (await serverExpenses()).length;

    final local = await store.nextLocalId('expenses');
    await store.enqueue(module: 'expenses', op: Op.create, localId: local,
        payload: {
          'note': 'Live end-to-end',
          'amount': 123,
          'category': 'Food',
          'txn_date': '2026-08-26',
        });

    final r = await sync.run();

    expect(r.blocked, isFalse, reason: r.blockedReason ?? '');
    expect(r.saved, 1, reason: 'problems: ${r.problems}');
    expect(await store.pendingCount(), 0, reason: 'it should be off the queue');

    final after = await serverExpenses();
    expect(after.length, before + 1);
    expect(after.where((e) => e['note'] == 'Live end-to-end').length, 1);
  });

  test('THE ONE THAT MATTERS: a replay does not make a second record',
      () async {
    final local = await store.nextLocalId('expenses');
    await store.enqueue(module: 'expenses', op: Op.create, localId: local,
        payload: {
          'note': 'Replay me',
          'amount': 55,
          'category': 'Travel',
          'txn_date': '2026-08-26',
        });

    // Send it, then put the very same operation back on the queue with the SAME
    // uuid — which is what a phone does when the reply never arrives.
    final ops = await store.allPending();
    final original = ops.single;
    await sync.run();

    await store.requeue(original);
    expect(await store.pendingCount(), 1);

    final second = await sync.run();

    expect(second.already, 1,
        reason: 'the server must recognise the uuid it already honoured');
    expect(
        (await serverExpenses()).where((e) => e['note'] == 'Replay me').length,
        1,
        reason: 'a retry after a dropped reply must not duplicate the record');
  });

  test('an edit and a delete made offline both land', () async {
    final local = await store.nextLocalId('expenses');
    await store.enqueue(module: 'expenses', op: Op.create, localId: local,
        payload: {
          'note': 'Edit me',
          'amount': 10,
          'category': 'Other',
          'txn_date': '2026-08-26',
        });
    await sync.run();

    final made = (await serverExpenses())
        .firstWhere((e) => e['note'] == 'Edit me')['id'] as int;

    await store.enqueue(module: 'expenses', op: Op.update, serverId: made,
        payload: {'note': 'Edited offline'});
    final r1 = await sync.run();
    expect(r1.saved, 1, reason: '${r1.problems}');
    expect(
        (await serverExpenses()).firstWhere((e) => e['id'] == made)['note'],
        'Edited offline');

    await store.enqueue(module: 'expenses', op: Op.delete, serverId: made);
    final r2 = await sync.run();
    expect(r2.saved, 1, reason: '${r2.problems}');
    expect((await serverExpenses()).where((e) => e['id'] == made), isEmpty);
  });

  test('an edit the computer has moved past is reported, not forced through',
      () async {
    final local = await store.nextLocalId('expenses');
    await store.enqueue(module: 'expenses', op: Op.create, localId: local,
        payload: {
          'note': 'Conflict me',
          'amount': 10,
          'category': 'Other',
          'txn_date': '2026-08-26',
        });
    await sync.run();
    final made = (await serverExpenses())
        .firstWhere((e) => e['note'] == 'Conflict me')['id'] as int;

    // Based on a copy from long before whatever the server now holds.
    await store.enqueue(module: 'expenses', op: Op.update, serverId: made,
        baseUpdatedAt: '2020-01-01T00:00:00',
        payload: {'note': 'SHOULD NOT WIN'});

    final r = await sync.run();

    expect(r.conflicts, 1);
    expect(await store.pendingCount(), 1,
        reason: 'the local version is kept for the owner to decide about');
    expect(
        (await serverExpenses()).firstWhere((e) => e['id'] == made)['note'],
        'Conflict me',
        reason: 'the server\'s value must stand until the owner says otherwise');
  });

  test('the vault is refused even if something asks for it', () async {
    await store.enqueue(
        module: 'vault', op: Op.create, localId: 1, payload: {'title': 'nope'});
    final r = await sync.run();
    expect(r.saved, 0);
    expect(r.refused, 1);
  });
}
