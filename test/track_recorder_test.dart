// Taking the fixes, and keeping them.
//
// The recorder is the part nobody can check by hand: no machine this app is
// developed on has a GPS, and the behaviour that matters most — what happens
// when a permission is refused, or granted only while the app is open — cannot
// be reproduced on demand even on a phone.
//
// THE DEFAULT IS THE MOST IMPORTANT ASSERTION IN THIS FILE. A location recorder
// that starts recording because somebody opened a screen is the thing nobody
// should ship, and a default is exactly the kind of thing a later change breaks
// without noticing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/offline/store.dart';
import 'package:safenest/track/recorder.dart';

import 'offline_store_test.dart' show memSecure;

var _seq = 0;
Future<OfflineStore> _store() async {
  final dir = await Directory.systemTemp.createTemp('safenest-track');
  addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
  return OfflineStore(
      secure: memSecure(), path: p.join(dir.path, 'track${_seq++}.db'));
}

final start = DateTime(2026, 10, 3, 6, 0);

/// Wait until the store holds [n] fixes, or give up.
///
/// POLLING, not a fixed delay. The store opens its database lazily, so the
/// first write includes a file open and a migration check — fifty milliseconds
/// is plenty on a quiet machine and nowhere near enough on a busy one, and a
/// test that fails only under load is one people learn to re-run rather than
/// read.
Future<void> untilCount(OfflineStore store, int n) async {
  for (var i = 0; i < 100; i++) {
    if (await store.fixCount() >= n) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Spot spot(int minute, double lat, double lon, {double accuracy = 10}) => Spot(
      at: start.add(Duration(minutes: minute)),
      lat: lat,
      lon: lon,
      accuracy: accuracy,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  group('the switch', () {
    test('a fresh install is NOT recording', () async {
      // The most important assertion in this file.
      final rec = Recorder(store: await _store(), positions: FakePositions());
      addTearDown(rec.dispose);
      expect(rec.recording, isFalse);
    });

    test('restoring does not start it unless it was already on', () async {
      SharedPreferences.setMockInitialValues({});
      final positions = FakePositions();
      final rec = Recorder(store: await _store(), positions: positions);
      addTearDown(rec.dispose);

      await rec.restore();
      expect(rec.recording, isFalse);
      expect(positions.watching, isFalse,
          reason: 'nothing may even ask the phone where it is');
    });

    test('and does start it when it was', () async {
      SharedPreferences.setMockInitialValues({'track.recording': true});
      final positions = FakePositions();
      final rec = Recorder(store: await _store(), positions: positions);
      addTearDown(rec.dispose);

      await rec.restore();
      expect(rec.recording, isTrue);
      expect(positions.watching, isTrue);
    });

    test('turning it on is remembered', () async {
      SharedPreferences.setMockInitialValues({});
      final rec = Recorder(store: await _store(), positions: FakePositions());
      addTearDown(rec.dispose);

      await rec.start();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('track.recording'), isTrue);
    });

    test('and turning it off is too', () async {
      SharedPreferences.setMockInitialValues({'track.recording': true});
      final rec = Recorder(store: await _store(), positions: FakePositions());
      addTearDown(rec.dispose);

      await rec.start();
      await rec.stop();
      expect(rec.recording, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('track.recording'), isFalse);
    });
  });

  group('when the phone will not say where it is', () {
    test('a refusal does not start recording, and says which refusal',
        () async {
      // Four reasons, kept apart because the way out of each is different and a
      // single "location unavailable" leaves somebody nothing to do about it.
      for (final why in [
        NoLocation.turnedOff,
        NoLocation.refused,
        NoLocation.refusedForGood,
      ]) {
        final rec = Recorder(
            store: await _store(), positions: FakePositions(problem: why));
        addTearDown(rec.dispose);
        expect(await rec.start(), isFalse);
        expect(rec.recording, isFalse);
        expect(rec.problem, why);
      }
    });

    test('"only while the app is open" DOES record, and flags itself',
        () async {
      // It looks like it works: the timeline fills in while you are looking at
      // the phone and stops the moment it goes in a pocket. Recording what can
      // be recorded is better than nothing, as long as the screen says so.
      final rec = Recorder(
          store: await _store(),
          positions: FakePositions(problem: NoLocation.onlyWhileOpen));
      addTearDown(rec.dispose);

      expect(await rec.start(), isTrue);
      expect(rec.recording, isTrue);
      expect(rec.problem, NoLocation.onlyWhileOpen);
    });
  });

  group('keeping what comes in', () {
    test('a fix is written down', () async {
      final store = await _store();
      final positions = FakePositions();
      final rec = Recorder(store: store, positions: positions);
      addTearDown(rec.dispose);

      await rec.start();
      positions.moveTo(spot(0, 12.9279, 77.6271));
      await untilCount(store, 1);

      expect(await store.fixCount(), 1);
    });

    test('standing still does not fill the database', () async {
      // A phone that has not moved still reports every couple of minutes, and a
      // year of that is a quarter of a million rows saying the same thing.
      final store = await _store();
      final positions = FakePositions();
      final rec = Recorder(store: store, positions: positions);
      addTearDown(rec.dispose);

      await rec.start();
      for (var i = 0; i < 6; i++) {
        positions.moveTo(spot(i, 12.9279, 77.6271));
        await untilCount(store, 1);
      }
      expect(await store.fixCount(), 1,
          reason: 'six fixes a minute apart in one spot is one fix');
    });

    test('but moving does', () async {
      final store = await _store();
      final positions = FakePositions();
      final rec = Recorder(store: store, positions: positions);
      addTearDown(rec.dispose);

      await rec.start();
      positions.moveTo(spot(0, 12.9279, 77.6271));
      await untilCount(store, 1);
      positions.moveTo(spot(2, 12.9716, 77.5946));
      await untilCount(store, 2);

      expect(await store.fixCount(), 2);
    });

    test('and so does sitting still for long enough', () async {
      // The thinning is distance AND time: a stay still needs fixes through it,
      // or a day at home is one point and `day.dart` cannot tell how long.
      final store = await _store();
      final positions = FakePositions();
      final rec = Recorder(store: store, positions: positions);
      addTearDown(rec.dispose);

      await rec.start();
      positions.moveTo(spot(0, 12.9279, 77.6271));
      await untilCount(store, 1);
      positions.moveTo(spot(20, 12.9279, 77.6271));
      await untilCount(store, 2);

      expect(await store.fixCount(), 2);
    });

    test('stopping stops it', () async {
      final store = await _store();
      final positions = FakePositions();
      final rec = Recorder(store: store, positions: positions);
      addTearDown(rec.dispose);

      // The store is opened first, so "nothing was written" cannot be the
      // database simply not being ready yet.
      await store.fixCount();
      await rec.start();
      await rec.stop();
      positions.moveTo(spot(0, 12.9279, 77.6271));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(await store.fixCount(), 0);
    });

    test('turning it on takes one straight away', () async {
      // Otherwise the screen is blank until the phone next moves a hundred
      // metres, which reads as the switch not having worked.
      final store = await _store();
      final positions =
          FakePositions(spots: [spot(0, 12.9279, 77.6271)]);
      final rec = Recorder(store: store, positions: positions);
      addTearDown(rec.dispose);

      await rec.start();
      await rec.markNow();
      expect(await store.fixCount(), greaterThanOrEqualTo(1));
    });
  });

  group('reading it back', () {
    test('a day is the LOCAL day, not the UTC one', () async {
      // Stored UTC, read by local calendar. In India an evening is already
      // tomorrow in UTC, so grouping on the stored string puts half of every
      // day on the wrong one.
      final store = await _store();
      final evening = DateTime(2026, 10, 3, 23, 30);
      await store.addFix(at: evening, lat: 12.9279, lon: 77.6271);

      final onThird = await store.fixesOn(DateTime(2026, 10, 3));
      expect(onThird, hasLength(1));
      final onFourth = await store.fixesOn(DateTime(2026, 10, 4));
      expect(onFourth, isEmpty);
    });

    test('the days with anything on them are listed', () async {
      final store = await _store();
      await store.addFix(
          at: DateTime(2026, 10, 1, 9), lat: 12.9279, lon: 77.6271);
      await store.addFix(
          at: DateTime(2026, 10, 3, 9), lat: 12.9716, lon: 77.5946);

      final days = await store.trackedDays();
      expect(days, hasLength(2));
      expect(days.first.day, 3, reason: 'newest first');
    });

    test('forgetting a day leaves the others', () async {
      final store = await _store();
      await store.addFix(
          at: DateTime(2026, 10, 1, 9), lat: 12.9279, lon: 77.6271);
      await store.addFix(
          at: DateTime(2026, 10, 3, 9), lat: 12.9716, lon: 77.5946);

      await store.clearTrackDay(DateTime(2026, 10, 1));
      expect(await store.fixCount(), 1);
    });

    test('forgetting everything leaves nothing', () async {
      final store = await _store();
      await store.addFix(
          at: DateTime(2026, 10, 1, 9), lat: 12.9279, lon: 77.6271);
      await store.clearTrack();
      expect(await store.fixCount(), 0);
    });
  });

  group('naming places', () {
    test('a name is kept with a radius', () async {
      final store = await _store();
      await store.nameTrackPlace(name: 'Home', lat: 12.9279, lon: 77.6271);
      final places = await store.trackPlaces();
      expect(places.single['name'], 'Home');
      expect(places.single['radius'], 150);
    });

    test('and can be taken back', () async {
      final store = await _store();
      final id =
          await store.nameTrackPlace(name: 'Home', lat: 12.9279, lon: 77.6271);
      await store.forgetTrackPlace(id);
      expect(await store.trackPlaces(), isEmpty);
    });
  });

  group('what the computer does not have', () {
    test('every fix starts unsent, and carries its own key', () async {
      final store = await _store();
      await store.addFix(at: start, lat: 12.9279, lon: 77.6271);
      expect(await store.unsyncedFixCount(), 1);

      final waiting = await store.unsyncedFixes();
      // Minted at insert, not derived at push time: two phones in one household
      // both start at row id 1, and a collision re-cuts somebody's day into
      // places that were never places.
      expect(waiting.single['client_uuid'], isNotNull);
      expect('${waiting.single['client_uuid']}'.length, greaterThan(20));
    });

    test('marking a batch sent takes them out of the queue', () async {
      final store = await _store();
      await store.addFix(at: start, lat: 12.9279, lon: 77.6271);
      await store.addFix(
          at: start.add(const Duration(minutes: 30)),
          lat: 12.9716,
          lon: 77.5946);

      final waiting = await store.unsyncedFixes();
      await store.markFixesSynced({
        for (var i = 0; i < waiting.length; i++)
          waiting[i]['id'] as int: 1000 + i
      });
      expect(await store.unsyncedFixCount(), 0);
    });

    test('oldest first, so a half-finished sync is not back to front', () async {
      final store = await _store();
      await store.addFix(
          at: DateTime(2026, 10, 3, 18), lat: 12.97, lon: 77.59);
      await store.addFix(
          at: DateTime(2026, 10, 1, 9), lat: 12.92, lon: 77.62);

      final waiting = await store.unsyncedFixes();
      expect('${waiting.first['at']}'.startsWith('2026-10-01'), isTrue);
    });
  });
}
