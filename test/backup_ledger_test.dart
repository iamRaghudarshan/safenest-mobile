// The ledger that makes a repeat backup fast.
//
// THE COMPLAINT THIS ANSWERS: "backup is not smart like Google Photos, it keeps
// running a long time." It decided "have I sent this?" by opening every file
// and running sha256 over every byte, then asking the computer — a read of the
// entire photo library, tens of gigabytes, performed to ask a question.
//
// Google Photos does not do that. It keeps a local record of what it has sent
// and diffs against it instantly. These tests pin that record's behaviour: it
// must skip what is unchanged, and it must NOT skip what has changed.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/offline/store.dart';

import 'offline_store_test.dart' show memSecure;

Future<OfflineStore> _store() async {
  final s = OfflineStore(secure: memSecure(), path: inMemoryDatabasePath);
  await s.clearEverything();
  return s;
}

({String id, int modified, int signature}) _a(String id,
        {int modified = 1000, int signature = 500}) =>
    (id: id, modified: modified, signature: signature);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('what has already been backed up', () {
    test('nothing is known before anything is sent', () async {
      final s = await _store();
      expect(await s.alreadyBackedUp([_a('p1'), _a('p2')]), isEmpty);
      await s.close();
    });

    test('THE POINT: an unchanged photo is recognised without its file', () async {
      final s = await _store();
      await s.markBackedUp([_a('p1'), _a('p2')]);
      final known = await s.alreadyBackedUp([_a('p1'), _a('p2'), _a('p3')]);
      expect(known, {'p1', 'p2'},
          reason: 'these are skipped with no file opened and no hash computed '
              '— which is the whole difference in a repeat run');
      expect(known, isNot(contains('p3')));
      await s.close();
    });

    test('a photo EDITED IN PLACE is not skipped', () async {
      final s = await _store();
      await s.markBackedUp([_a('p1', modified: 1000, signature: 500)]);
      // Same id, later modified time: the picture changed.
      final known = await s.alreadyBackedUp([_a('p1', modified: 2000, signature: 500)]);
      expect(known, isEmpty,
          reason: 'an id alone would skip it and the new version would never '
              'reach the computer — this is why modified time is stored');
      await s.close();
    });

    test('a re-encoded video is not skipped — duration is in the signature', () async {
      final s = await _store();
      await s.markBackedUp([_a('p1', signature: 500)]);
      expect(await s.alreadyBackedUp([_a('p1', signature: 900)]), isEmpty);
      await s.close();
    });

    test('ids carried from the old list are trusted, so upgrading is free', () async {
      final s = await _store();
      // The old SharedPreferences list knew only ids — no modified time, no
      // size. They import as zeroes and must count as unchanged, or upgrading
      // would re-hash somebody's entire library.
      await s.importBackedUpIds(['old1', 'old2']);
      final known =
          await s.alreadyBackedUp([_a('old1', modified: 999), _a('old2')]);
      expect(known, {'old1', 'old2'});
      await s.close();
    });

    test('one query answers for a whole page', () async {
      final s = await _store();
      await s.markBackedUp([for (var i = 0; i < 200; i++) _a('p$i')]);
      final known =
          await s.alreadyBackedUp([for (var i = 0; i < 200; i++) _a('p$i')]);
      expect(known, hasLength(200),
          reason: 'a round trip per asset would put the cost back where this '
              'table exists to remove it');
      await s.close();
    });

    test('it counts what it holds', () async {
      final s = await _store();
      await s.markBackedUp([_a('p1'), _a('p2'), _a('p3')]);
      expect(await s.backedUpCount(), 3);
      await s.close();
    });

    test('clearing it offers the whole library again', () async {
      final s = await _store();
      await s.markBackedUp([_a('p1')]);
      await s.clearBackedUp();
      expect(await s.alreadyBackedUp([_a('p1')]), isEmpty,
          reason: 'this is what "photos are missing on my computer" undoes, and '
              'leaving the ledger would make it offer nothing');
      await s.close();
    });

    test('recording the same asset twice does not duplicate it', () async {
      final s = await _store();
      await s.markBackedUp([_a('p1')]);
      await s.markBackedUp([_a('p1', modified: 2000)]);
      expect(await s.backedUpCount(), 1);
      // And the newer facts win, so the edit above is what is remembered.
      expect(await s.alreadyBackedUp([_a('p1', modified: 2000)]), {'p1'});
      await s.close();
    });

    test('an empty page asks the database nothing', () async {
      final s = await _store();
      expect(await s.alreadyBackedUp(const []), isEmpty);
      await s.markBackedUp(const []);
      expect(await s.backedUpCount(), 0);
      await s.close();
    });
  });
}
