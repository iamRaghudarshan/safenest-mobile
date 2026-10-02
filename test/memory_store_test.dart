// Keeping what somebody told the app, on the phone.
//
// Life Memory inverts how every other module here works. The others are a
// cache of what the server holds; this one is CREATED on the phone, by
// speaking, very often with no signal — so the local store is the original and
// not a copy, and losing a row loses the only one there is.
//
// Run against the real SQLite engine, including an actual upgrade from v7,
// because this repository has shipped a migration that threw on open and left
// an app that would not start.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/offline/store.dart';

import 'offline_store_test.dart' show memSecure;

/// A database of its OWN for each test.
///
/// `inMemoryDatabasePath` looks like isolation and is not: sqflite_common_ffi
/// caches open databases by path, so every `:memory:` store in a file is the
/// same database and rows pile up across tests. That showed here as four
/// failures that each passed when run alone — the worst shape a test failure
/// has, because it points at the code and the code is fine.
var _seq = 0;
Future<OfflineStore> _store() async {
  final dir = await Directory.systemTemp.createTemp('safenest-mem');
  addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
  return OfflineStore(
      secure: memSecure(), path: p.join(dir.path, 'offline${_seq++}.db'));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('a fresh install has nothing and says so', () async {
    final s = await _store();
    expect(await s.memoryCount(), 0);
    expect(await s.memories(), isEmpty);
  });

  test('what was said is kept verbatim, with its facts', () async {
    final s = await _store();
    await s.addMemory(
      body: 'Bought the washing machine from Vijay Sales in Jayanagar.',
      saidAt: DateTime(2026, 9, 14),
      spoken: true,
      facts: [
        (kind: 'expiry', value: 'Warranty ends 14 Sep 2028', at: DateTime(2028, 9, 14)),
        (kind: 'shop', value: 'Vijay Sales', at: null),
      ],
    );

    final rows = await s.memories();
    expect(rows, hasLength(1));
    expect(rows.single['body'], contains('Vijay Sales'));
    expect(rows.single['spoken'], 1);
    expect((rows.single['facts'] as List), hasLength(2));
  });

  test('the newest is at the top, whatever order it arrived in', () async {
    // The thread reads newest first, and a memory added today about something
    // from last year must not jump above today's.
    final s = await _store();
    await s.addMemory(body: 'older', saidAt: DateTime(2026, 1, 1));
    await s.addMemory(body: 'newest', saidAt: DateTime(2026, 9, 14));
    await s.addMemory(body: 'middle', saidAt: DateTime(2026, 5, 1));

    final rows = await s.memories();
    expect([for (final r in rows) r['body']], ['newest', 'middle', 'older']);
  });

  test('a memory with no facts is perfectly ordinary', () async {
    // Most of what anybody says has nothing to extract, and the thread must
    // not treat that as a failure.
    final s = await _store();
    await s.addMemory(body: 'it rained all afternoon', saidAt: DateTime(2026, 9, 1));
    expect((await s.memories()).single['facts'], isEmpty);
  });

  group('finding it again', () {
    Future<OfflineStore> filled() async {
      final s = await _store();
      await s.addMemory(
          body: 'Bought the washing machine from Vijay Sales.',
          saidAt: DateTime(2026, 9, 14),
          facts: [(kind: 'place', value: 'Jayanagar', at: null)]);
      await s.addMemory(
          body: 'The blue suitcase is on top of the wardrobe.',
          saidAt: DateTime(2026, 9, 10));
      return s;
    }

    test('it searches the WORDS', () async {
      // THE CASE THIS EXISTS FOR. Nobody tagged the suitcase. Somebody
      // looking for it is remembering how they said it, not what was labelled.
      final s = await filled();
      final hits = await s.searchMemories('blue suitcase');
      expect(hits, hasLength(1));
      expect(hits.single['body'], contains('suitcase'));
    });

    test('and the confirmed facts, which the words may not repeat', () async {
      final s = await filled();
      final hits = await s.searchMemories('Jayanagar');
      expect(hits, hasLength(1));
      expect(hits.single['body'], contains('washing machine'));
    });

    test('case does not matter', () async {
      final s = await filled();
      expect(await s.searchMemories('WASHING'), hasLength(1));
    });

    test('an empty search asks for nothing rather than everything', () async {
      // Returning the whole library for an empty box is how a search screen
      // appears to hang on a long list.
      final s = await filled();
      expect(await s.searchMemories('   '), isEmpty);
    });

    test('a per-cent sign is a character, not a wildcard', () async {
      // Without escaping, typing % returns every memory — which looks like
      // the search is broken in the other direction.
      final s = await filled();
      expect(await s.searchMemories('%'), isEmpty);
    });
  });

  group('what is coming', () {
    test('only dates still ahead, soonest first', () async {
      final s = await _store();
      await s.addMemory(body: 'mixer', saidAt: DateTime(2026, 1, 1), facts: [
        (kind: 'expiry', value: 'Mixer warranty', at: DateTime(2026, 10, 20)),
      ]);
      await s.addMemory(body: 'machine', saidAt: DateTime(2026, 9, 14), facts: [
        (kind: 'expiry', value: 'Machine warranty', at: DateTime(2028, 9, 14)),
      ]);
      await s.addMemory(body: 'old', saidAt: DateTime(2020, 1, 1), facts: [
        (kind: 'expiry', value: 'Expired long ago', at: DateTime(2021, 1, 1)),
      ]);

      final due = await s.memoryDates(from: DateTime(2026, 10, 1));
      expect([for (final d in due) d['value']],
          ['Mixer warranty', 'Machine warranty']);
    });

    test('and it carries enough to show the memory it came from', () async {
      final s = await _store();
      await s.addMemory(body: 'the words', saidAt: DateTime(2026, 9, 14), facts: [
        (kind: 'expiry', value: 'Something', at: DateTime(2027, 1, 1)),
      ]);
      final due = await s.memoryDates(from: DateTime(2026, 10, 1));
      expect(due.single['body'], 'the words');
    });
  });

  test('editing the chips leaves the words alone', () async {
    // The words are the only thing that cannot be rebuilt. Everything else is
    // derived from them, so changing a fact must never touch them.
    final s = await _store();
    final id = await s.addMemory(
        body: 'exactly these words',
        saidAt: DateTime(2026, 9, 14),
        facts: [(kind: 'person', value: 'Wrong', at: null)]);

    await s.setMemoryFacts(id, [(kind: 'person', value: 'Right', at: null)]);

    final row = (await s.memories()).single;
    expect(row['body'], 'exactly these words');
    expect((row['facts'] as List).single['value'], 'Right');
  });

  test('deleting takes the facts with it', () async {
    final s = await _store();
    final id = await s.addMemory(
        body: 'gone', saidAt: DateTime(2026, 9, 14),
        facts: [(kind: 'place', value: 'Somewhere', at: null)]);
    await s.deleteMemory(id);
    expect(await s.memoryCount(), 0);
    expect(await s.memoryDates(from: DateTime(2020)), isEmpty);
  });

  group('candidates for a question', () {
    Future<OfflineStore> filled() async {
      final s = await _store();
      await s.addMemory(
          body: 'Bought the washing machine from Vijay Sales',
          saidAt: DateTime(2026, 9, 26),
          facts: [(kind: 'shop', value: 'Vijay Sales', at: null)]);
      await s.addMemory(
          body: 'Amma says tamarind first', saidAt: DateTime(2026, 9, 20));
      await s.addMemory(
          body: 'Mixer, four thousand', saidAt: DateTime(2026, 9, 10));
      return s;
    }

    test('ANY of the words, not all of them', () async {
      // The opposite of searchMemories, deliberately: the scorer in ask.dart
      // needs the near misses so it can rank them and so it can honestly say
      // "I cannot answer that, but this mentions it".
      final s = await filled();
      final hits = await s.memoriesMatchingAny(['fridge', 'washing']);
      expect(hits, hasLength(1));
      expect('${hits.single['body']}', contains('washing machine'));
    });

    test('a confirmed fact is searched as well as the words', () async {
      final s = await filled();
      final hits = await s.memoriesMatchingAny(['vijay']);
      expect(hits, hasLength(1));
    });

    test('plurals find singulars, on the same stem ask.dart scores with',
        () async {
      final s = await filled();
      expect(await s.memoriesMatchingAny(['machines']), hasLength(1));
    });

    test('no usable words means everything recent, newest first', () async {
      // "how much have I spent in all" has no subject. The scorer decides;
      // this only has to hand it a bounded, ordered pool.
      final s = await filled();
      final all = await s.memoriesMatchingAny(const []);
      expect(all, hasLength(3));
      expect('${all.first['body']}', contains('washing machine'));
    });

    test('a wildcard typed into a question is a character, not a pattern',
        () async {
      // LIKE treats % as "anything". Unescaped, asking about "100%" would
      // return every memory there is and the answer would be built from a
      // random one.
      final s = await filled();
      expect(await s.memoriesMatchingAny(['%']), isEmpty);
    });

    test('facts come attached, because the scorer ranks on them', () async {
      final s = await filled();
      final hits = await s.memoriesMatchingAny(['washing']);
      expect((hits.single['facts'] as List), hasLength(1));
    });
  });

  group('what the computer does not have yet', () {
    test('everything is unsynced until it is told otherwise', () async {
      final s = await _store();
      final id = await s.addMemory(body: 'said offline', saidAt: DateTime(2026, 9, 1));
      expect(await s.unsyncedMemoryCount(), 1);

      await s.markMemorySynced(id, 4242);
      expect(await s.unsyncedMemoryCount(), 0);
      final row = (await s.memories()).single;
      expect(row['server_id'], 4242);
      expect(row['body'], 'said offline',
          reason: 'syncing changes where it is, never what it says');
    });

    test('oldest first, so a half-finished sync is not back to front',
        () async {
      final s = await _store();
      await s.addMemory(body: 'newer', saidAt: DateTime(2026, 9, 20));
      await s.addMemory(body: 'older', saidAt: DateTime(2026, 9, 1));
      final queue = await s.unsyncedMemories();
      expect([for (final r in queue) r['body']], ['older', 'newer']);
    });

    test('a photograph and its facts ride along', () async {
      final s = await _store();
      await s.addMemory(
          body: 'with a picture',
          saidAt: DateTime(2026, 9, 1),
          photoPath: '/x/memories/m_1.jpg',
          facts: [(kind: 'place', value: 'Lalbagh', at: null)]);
      final q = (await s.unsyncedMemories()).single;
      expect(q['photo_path'], '/x/memories/m_1.jpg');
      expect((q['facts'] as List), hasLength(1));
    });
  });

  test('a real v7 database upgrades, keeping what it held', () async {
    // Not the in-memory shortcut, which runs onCreate and proves nothing about
    // an upgrade. A phone coming into this build has a ledger and a skipped
    // list already, and neither may be lost to make room for memories.
    final dir = await Directory.systemTemp.createTemp('safenest-v7');
    addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
    final path = p.join(dir.path, 'offline.db');

    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE backup_ledger ('
                'asset_id TEXT PRIMARY KEY, modified INTEGER NOT NULL DEFAULT 0,'
                'signature INTEGER NOT NULL DEFAULT 0, sent_at TEXT NOT NULL)');
            await db.execute('CREATE TABLE backup_ignored ('
                "asset_id TEXT PRIMARY KEY, reason TEXT NOT NULL DEFAULT '',"
                'at TEXT NOT NULL)');
          },
        ));
    await old.insert('backup_ledger', {
      'asset_id': 'photo-1',
      'modified': 10,
      'signature': 20,
      'sent_at': DateTime.now().toIso8601String(),
    });
    await old.close();

    final store = OfflineStore(secure: memSecure(), path: path);
    expect(await store.backedUpCount(), 1,
        reason: 'the upgrade must not lose what the phone already sent');

    // And the new tables work, not merely exist.
    final id = await store.addMemory(
        body: 'first memory after the upgrade', saidAt: DateTime(2026, 9, 14));
    expect(id, greaterThan(0));
    expect(await store.memoryCount(), 1);
  });

  group('the v9 column, which is the one that could stop the app starting',
      () {
    test('a v8 phone gains client_uuid and keeps its memories', () async {
      final dir = await Directory.systemTemp.createTemp('safenest-v8');
      addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
      final path = p.join(dir.path, 'offline.db');

      // v8 as it actually was: memories without client_uuid.
      final old = await databaseFactory.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 8,
            onCreate: (db, _) async {
              await db.execute('CREATE TABLE memories ('
                  'id INTEGER PRIMARY KEY AUTOINCREMENT, server_id INTEGER,'
                  'said_at TEXT NOT NULL, body TEXT NOT NULL,'
                  'spoken INTEGER NOT NULL DEFAULT 0, photo_id TEXT,'
                  'photo_path TEXT, created_at TEXT NOT NULL,'
                  'updated_at TEXT NOT NULL)');
              await db.execute('CREATE TABLE memory_facts ('
                  'id INTEGER PRIMARY KEY AUTOINCREMENT,'
                  'memory_id INTEGER NOT NULL, kind TEXT NOT NULL,'
                  'value TEXT NOT NULL, at TEXT)');
            },
          ));
      await old.insert('memories', {
        'said_at': DateTime(2026, 9, 1).toIso8601String(),
        'body': 'said before the upgrade',
        'spoken': 1,
        'created_at': DateTime(2026, 9, 1).toIso8601String(),
        'updated_at': DateTime(2026, 9, 1).toIso8601String(),
      });
      await old.close();

      final store = OfflineStore(secure: memSecure(), path: path);
      final rows = await store.memories();
      expect(rows, hasLength(1),
          reason: 'the words are the only copy there is');
      expect(rows.single['body'], 'said before the upgrade');

      // The column is there, and a new memory gets a uuid even though the old
      // one has none — which is right: an old row has nothing to push with and
      // is left alone rather than being invented one.
      await store.addMemory(body: 'said after', saidAt: DateTime(2026, 10, 1));
      final after = await store.memories();
      final fresh = after.firstWhere((r) => r['body'] == 'said after');
      expect(fresh['client_uuid'], isNotNull);
    });

    test('a v7 phone upgrades straight through without a duplicate column',
        () async {
      // THE SHAPE THAT ONCE SHIPPED AN APP THAT WOULD NOT START. Going from v7
      // creates `memories` whole from the CURRENT definition — client_uuid
      // included — and then the v9 step would add it a second time, throwing
      // "duplicate column name" inside onUpgrade and failing the open. Nothing
      // about this is visible without running it.
      final dir = await Directory.systemTemp.createTemp('safenest-v7to9');
      addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
      final path = p.join(dir.path, 'offline.db');

      final old = await databaseFactory.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 7,
            onCreate: (db, _) async {
              await db.execute('CREATE TABLE backup_ledger ('
                  'asset_id TEXT PRIMARY KEY, modified INTEGER NOT NULL DEFAULT 0,'
                  'signature INTEGER NOT NULL DEFAULT 0, sent_at TEXT NOT NULL)');
              await db.execute('CREATE TABLE backup_ignored ('
                  "asset_id TEXT PRIMARY KEY, reason TEXT NOT NULL DEFAULT '',"
                  'at TEXT NOT NULL)');
            },
          ));
      await old.close();

      final store = OfflineStore(secure: memSecure(), path: path);
      // Opening at all is the assertion. The rest proves the table is usable
      // rather than merely present.
      final id = await store.addMemory(
          body: 'first after a two-version jump', saidAt: DateTime(2026, 10, 1));
      expect(id, greaterThan(0));
      expect(await store.unsyncedMemoryCount(), 1);
      expect((await store.unsyncedMemories()).single['client_uuid'], isNotNull);
    });
  });
}
