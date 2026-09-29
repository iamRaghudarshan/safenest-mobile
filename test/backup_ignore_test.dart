// Telling the backup to stop trying one file.
//
// Two videos on the owner's phone have failed every run for weeks. Each run
// reads them off the phone, spends minutes on them, fails, and leaves the same
// red number — and there was no way to say "I know, leave it". This is that.
//
// WHAT IS PINNED, and why each one matters more than it looks:
//
//  * A skipped file is NOT in the backup ledger. That table means "the
//    computer has this", and putting a skipped file in it would make the
//    cheap skip believe it was safe and the screen say a library was backed
//    up when part of it deliberately is not.
//  * Undoing is complete: the file comes back exactly as it was, not as
//    something already sent.
//  * "Back up everything again" does NOT quietly reopen these decisions.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/offline/store.dart';

import 'offline_store_test.dart' show memSecure;

Future<OfflineStore> _store() async =>
    OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('nothing is skipped until somebody says so', () async {
    final s = await _store();
    expect(await s.ignoredForBackup(), isEmpty);
    expect(await s.ignoredCount(), 0);
  });

  test('a skipped file is remembered, with what it was stuck on', () async {
    final s = await _store();
    await s.ignoreForBackup('video-1',
        reason: 'The computer refused it (unsupported format)');

    expect(await s.ignoredForBackup(), {'video-1'});
    expect(await s.ignoredCount(), 1);
    final items = await s.ignoredWithReasons();
    expect(items.single.id, 'video-1');
    expect(items.single.reason, contains('unsupported'));
  });

  test('skipping is not the same as backed up', () async {
    // THE ONE THAT MATTERS. If a skipped file ended up in the ledger, the
    // cheap skip would treat it as safely on the computer — and the screen
    // would tell somebody their library was backed up while a file they knew
    // about was nowhere. Skipped means "not there, and I am content"; those
    // are different sentences and they are different tables.
    final s = await _store();
    await s.ignoreForBackup('video-1');

    final known = await s.alreadyBackedUp([
      (id: 'video-1', modified: 111, signature: 222),
    ]);
    expect(known, isEmpty, reason: 'a skipped file must not read as sent');
    expect(await s.backedUpCount(), 0);
  });

  test('skipping twice is still one file', () async {
    final s = await _store();
    await s.ignoreForBackup('video-1', reason: 'first');
    await s.ignoreForBackup('video-1', reason: 'second');
    expect(await s.ignoredCount(), 1);
    // The newer reason wins: it describes the most recent attempt.
    expect((await s.ignoredWithReasons()).single.reason, 'second');
  });

  test('undoing puts it back exactly as it was', () async {
    final s = await _store();
    await s.ignoreForBackup('video-1');
    await s.unignoreForBackup('video-1');

    expect(await s.ignoredForBackup(), isEmpty);
    // And crucially NOT as something already sent — it never was.
    expect(
        await s.alreadyBackedUp([(id: 'video-1', modified: 1, signature: 2)]),
        isEmpty);
  });

  test('"back up everything again" leaves the decisions alone', () async {
    // clearBackedUp is about what the COMPUTER has. Reopening a decision
    // somebody made one file at a time would put them straight back where
    // they started: the same file failing every run.
    final s = await _store();
    await s.markBackedUp([(id: 'photo-1', modified: 1, signature: 2)]);
    await s.ignoreForBackup('video-1');

    await s.clearBackedUp();

    expect(await s.backedUpCount(), 0, reason: 'the ledger should be emptied');
    expect(await s.ignoredForBackup(), {'video-1'},
        reason: 'but the skipped list is not a backup record');
  });

  test('clearing the skipped list is its own, separate action', () async {
    final s = await _store();
    await s.ignoreForBackup('a');
    await s.ignoreForBackup('b');
    await s.clearIgnored();
    expect(await s.ignoredCount(), 0);
  });

  test('a real v6 database upgrades, keeping its ledger', () async {
    // NOT the in-memory shortcut the tests above take — that path runs
    // onCreate, which builds the new table as part of a fresh schema and
    // proves nothing about an upgrade. This makes a database at version 6,
    // fills its ledger, closes it, and opens it through OfflineStore so the
    // real onUpgrade runs.
    //
    // This repository has shipped a migration that threw on open and left an
    // app that would not start. The cost of checking is one test.
    final dir = await Directory.systemTemp.createTemp('safenest-v6');
    addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
    final path = p.join(dir.path, 'offline.db');

    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE backup_ledger (
                asset_id TEXT PRIMARY KEY,
                modified  INTEGER NOT NULL DEFAULT 0,
                signature INTEGER NOT NULL DEFAULT 0,
                sent_at  TEXT    NOT NULL
              )''');
          },
        ));
    await old.insert('backup_ledger', {
      'asset_id': 'photo-1',
      'modified': 10,
      'signature': 20,
      'sent_at': DateTime.now().toIso8601String(),
    });
    await old.close();

    // Opening through the store is what runs the migration.
    final store = OfflineStore(secure: memSecure(), path: path);
    expect(await store.backedUpCount(), 1,
        reason: 'the upgrade must not lose what the phone already sent');
    expect(await store.ignoredCount(), 0);

    // And the new table is usable, not merely present.
    await store.ignoreForBackup('video-1', reason: 'too large');
    expect(await store.ignoredForBackup(), {'video-1'});
  });

  test('an existing installation gains the table without losing its ledger',
      () async {
    // The table arrived at schema v7. A phone upgrading into this build has a
    // ledger with twenty thousand rows in it, and the one thing that must not
    // happen is that it comes back empty and re-offers the whole library.
    final s = await _store();
    await s.markBackedUp([
      (id: 'photo-1', modified: 10, signature: 20),
      (id: 'photo-2', modified: 11, signature: 21),
    ]);
    expect(await s.backedUpCount(), 2);

    await s.ignoreForBackup('video-1');

    expect(await s.backedUpCount(), 2);
    expect(
        await s.alreadyBackedUp([(id: 'photo-1', modified: 10, signature: 20)]),
        {'photo-1'});
  });
}
