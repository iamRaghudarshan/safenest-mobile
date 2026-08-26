// The offline store: what survives, what is thrown away, and what must never
// be thrown away.
//
// These run against a real SQLite database on this machine (sqflite_common_ffi),
// not a mock, because every rule worth testing here is about what the database
// actually does — ordering, the unique constraint, and deleting exactly one row.
//
// The rule with teeth is `confirmed`: an operation is forgotten only when the
// server confirms THAT operation. Between typing and syncing, a pending row is
// the only copy of that record in the world.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/offline/store.dart';

/// The Keychain is not available in a test process, so stand in for it.
/// Behaviour that matters: it hands back the same key it was given.
class _MemSecure extends FlutterSecureStorage {
  _MemSecure() : super();
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

Future<OfflineStore> _store() async {
  final s = OfflineStore(secure: _MemSecure(), path: inMemoryDatabasePath);
  await s.clearEverything();
  return s;
}

Map<String, dynamic> _row(int id, String note, {String? updated}) => {
      'id': id,
      'note': note,
      'amount': id * 100,
      'updated_at': updated ?? '2026-08-20T10:00:00',
    };

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the cache holds what the server said', () {
    test('a fetched list reads back', () async {
      final s = await _store();
      await s.putList('expenses', [_row(1, 'chai'), _row(2, 'bus')]);
      final out = await s.read('expenses');
      expect(out.length, 2);
      expect(out.map((r) => r.data['note']).toSet(), {'chai', 'bus'});
      expect(out.every((r) => r.pending), isFalse);
      await s.close();
    });

    test('a later fetch replaces it, so a record deleted elsewhere goes', () async {
      final s = await _store();
      await s.putList('expenses', [_row(1, 'chai'), _row(2, 'bus')]);
      await s.putList('expenses', [_row(1, 'chai')]);
      final out = await s.read('expenses');
      expect(out.map((r) => r.id), [1]);
      await s.close();
    });

    test('modules do not bleed into each other', () async {
      final s = await _store();
      await s.putList('expenses', [_row(1, 'chai')]);
      await s.putList('todos', [_row(1, 'call bank')]);
      expect((await s.read('expenses')).single.data['note'], 'chai');
      expect((await s.read('todos')).single.data['note'], 'call bank');
      await s.close();
    });

    test('clearing the cache does NOT clear pending work', () async {
      final s = await _store();
      await s.putList('expenses', [_row(1, 'chai')]);
      await s.enqueue(
          module: 'expenses', op: Op.create, localId: 1, payload: {'note': 'auto'});
      await s.clearCache();
      expect(await s.pendingCount(), 1,
          reason: 'the cache is the server\'s and can be refetched; the queue '
              'is the only copy of what the owner typed');
      await s.close();
    });
  });

  group('what you did offline shows up straight away', () {
    test('a record created offline appears in the merged list', () async {
      final s = await _store();
      final local = await s.nextLocalId('expenses');
      await s.enqueue(
          module: 'expenses', op: Op.create, localId: local,
          payload: {'note': 'petrol', 'amount': 500});
      final out = await s.read('expenses');
      expect(out.single.data['note'], 'petrol');
      expect(out.single.isLocalOnly, isTrue);
      expect(out.single.pending, isTrue);
      await s.close();
    });

    test('its id is negative, so it cannot be mistaken for a server row', () async {
      final s = await _store();
      final local = await s.nextLocalId('expenses');
      await s.enqueue(
          module: 'expenses', op: Op.create, localId: local, payload: {'note': 'x'});
      expect((await s.read('expenses')).single.id, lessThan(0));
      await s.close();
    });

    test('an edit to a server record is applied on top of the cached copy', () async {
      final s = await _store();
      await s.putList('expenses', [_row(1, 'chai')]);
      await s.enqueue(
          module: 'expenses', op: Op.update, serverId: 1,
          payload: {'note': 'chai and samosa'},
          baseUpdatedAt: '2026-08-20T10:00:00');
      final r = (await s.read('expenses')).single;
      expect(r.data['note'], 'chai and samosa');
      expect(r.data['amount'], 100, reason: 'untouched fields must survive');
      expect(r.pending, isTrue);
      await s.close();
    });

    test('a delete marks the record rather than hiding it from the store', () async {
      final s = await _store();
      await s.putList('expenses', [_row(1, 'chai')]);
      await s.enqueue(module: 'expenses', op: Op.delete, serverId: 1);
      final r = (await s.read('expenses')).single;
      expect(r.deleted, isTrue,
          reason: 'a list hides it, but the sync screen has to count it');
      await s.close();
    });
  });

  group('replay order and identity', () {
    test('the queue comes back oldest first, whatever order it was written', () async {
      final s = await _store();
      await s.enqueue(module: 'todos', op: Op.create, localId: 1, payload: {'t': 'a'});
      await s.enqueue(module: 'todos', op: Op.update, localId: 1, payload: {'t': 'b'});
      await s.enqueue(module: 'todos', op: Op.delete, localId: 1);
      final ops = await s.allPending();
      expect(ops.map((o) => o.op), [Op.create, Op.update, Op.delete],
          reason: 'a create must never replay after the edit that followed it');
      expect(ops.map((o) => o.seq).toList(), isA<List<int>>());
      expect(ops[0].seq < ops[1].seq && ops[1].seq < ops[2].seq, isTrue);
      await s.close();
    });

    test('every operation gets its own uuid', () async {
      final s = await _store();
      final a = await s.enqueue(module: 'todos', op: Op.create, localId: 1);
      final b = await s.enqueue(module: 'todos', op: Op.create, localId: 2);
      expect(a, isNot(b));
      expect(a.length, greaterThan(30));
      await s.close();
    });

    test('once a create lands, later ops point at the real row', () async {
      final s = await _store();
      final local = await s.nextLocalId('todos');
      await s.enqueue(module: 'todos', op: Op.create, localId: local, payload: {'t': 'a'});
      await s.enqueue(module: 'todos', op: Op.update, localId: local, payload: {'t': 'b'});

      await s.resolveLocalId('todos', local, 77);

      final ops = await s.allPending();
      expect(ops.every((o) => o.serverId == 77), isTrue,
          reason: 'an edit still pointing at a local id replays against nothing');
      expect(ops.every((o) => o.localId == null), isTrue);
      await s.close();
    });
  });

  group('confirming and failing — the rule that stops data loss', () {
    test('confirming one operation removes exactly that one', () async {
      final s = await _store();
      await s.enqueue(module: 'todos', op: Op.create, localId: 1, payload: {'t': 'a'});
      await s.enqueue(module: 'todos', op: Op.create, localId: 2, payload: {'t': 'b'});
      final ops = await s.allPending();

      await s.confirmed(ops.first.seq);

      final left = await s.allPending();
      expect(left.length, 1);
      expect(left.single.payload['t'], 'b');
      await s.close();
    });

    test('a failure KEEPS the operation, and says why', () async {
      final s = await _store();
      await s.enqueue(module: 'todos', op: Op.create, localId: 1, payload: {'t': 'a'});
      final op = (await s.allPending()).single;

      await s.failed(op.seq, 'the computer did not answer');

      final after = (await s.allPending()).single;
      expect(after.state, OpState.failed);
      expect(after.tries, 1);
      expect(after.lastError, 'the computer did not answer');
      expect(await s.pendingCount(), 1,
          reason: 'a refused operation is the one thing that must never be '
              'dropped — it exists nowhere else');
      await s.close();
    });

    test('retrying increments the count rather than starting over', () async {
      final s = await _store();
      await s.enqueue(module: 'todos', op: Op.create, localId: 1);
      final seq = (await s.allPending()).single.seq;
      await s.failed(seq, 'one');
      await s.failed(seq, 'two');
      final after = (await s.allPending()).single;
      expect(after.tries, 2);
      expect(after.lastError, 'two');
      await s.close();
    });

    test('eight of ten landing leaves exactly the two behind', () async {
      final s = await _store();
      for (var i = 1; i <= 10; i++) {
        await s.enqueue(module: 'todos', op: Op.create, localId: i, payload: {'n': i});
      }
      final ops = await s.allPending();
      for (var i = 0; i < 10; i++) {
        if (i == 3 || i == 7) {
          await s.failed(ops[i].seq, 'refused');
        } else {
          await s.confirmed(ops[i].seq);
        }
      }
      final left = await s.allPending();
      expect(left.length, 2);
      expect(left.map((o) => o.payload['n']), [4, 8]);
      await s.close();
    });
  });

  group('payloads are not readable in the database file', () {
    // A real file, not :memory:, because the claim being tested is about what
    // is on disk — and a second connection cannot see another connection's
    // in-memory database, so the check would silently pass on nothing.
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('offline_store_test');
    });
    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('the plain text is NOT in the database file', () async {
      final file = p.join(dir.path, 'offline.db');
      final s = OfflineStore(secure: _MemSecure(), path: file);
      await s.enqueue(
          module: 'expenses', op: Op.create, localId: 1,
          payload: {'note': 'RECOGNISABLE-SECRET-STRING', 'amount': 4242});
      await s.close();

      final bytes = await File(file).readAsBytes();
      final asText = String.fromCharCodes(bytes);
      expect(asText.contains('RECOGNISABLE-SECRET-STRING'), isFalse,
          reason: 'anyone who gets the file would read the record straight out '
              'of it');
      expect(asText.contains('4242'), isFalse);
    });

    test('and it still decrypts back to exactly what went in', () async {
      final file = p.join(dir.path, 'offline.db');
      final s = OfflineStore(secure: _MemSecure(), path: file);
      await s.enqueue(
          module: 'expenses', op: Op.create, localId: 1,
          payload: {'note': 'RECOGNISABLE-SECRET-STRING', 'amount': 4242});
      final back = (await s.allPending()).single;
      expect(back.payload['note'], 'RECOGNISABLE-SECRET-STRING');
      expect(back.payload['amount'], 4242);
      await s.close();
    });

    test('a tampered body is refused rather than half-read', () async {
      final file = p.join(dir.path, 'offline.db');
      final s = OfflineStore(secure: _MemSecure(), path: file);
      await s.enqueue(
          module: 'expenses', op: Op.create, localId: 1,
          payload: {'note': 'original'});
      await s.close();

      // Flip the ciphertext without touching the tag, exactly as an attacker
      // editing the file would. Encrypt-then-MAC is what makes this detectable;
      // without the check it would decrypt into plausible-looking rubbish.
      final raw = await databaseFactory.openDatabase(file);
      final row = (await raw.query('pending', columns: ['seq', 'body'])).single;
      final parts = '${row['body']}'.split('.');
      final ct = base64Decode(parts[1]);
      ct[0] ^= 0xFF;
      await raw.update(
          'pending',
          {'body': '${parts[0]}.${base64Encode(ct)}.${parts[2]}'},
          where: 'seq = ?', whereArgs: [row['seq']]);
      await raw.close();

      final reopened = OfflineStore(secure: _MemSecure(), path: file);
      final back = (await reopened.allPending()).single;
      expect(back.payload, isEmpty,
          reason: 'a row that fails its tag must come back empty, not as '
              'whatever the bytes happened to decode to');
      await reopened.close();
    });
  });
}
