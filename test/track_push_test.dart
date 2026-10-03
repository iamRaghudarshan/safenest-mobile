// Getting a day of positions to the computer.
//
// The same shape as memory_push_test.dart, and the same rule underneath: a fix
// wrongly marked as sent never goes up again, while one wrongly left unsent
// costs a harmless retry — so every uncertain case must fall the second way.
//
// WHAT IS DIFFERENT HERE IS VOLUME. A day is hundreds of fixes and a fortnight
// abroad is thousands, so the batching, the cap on one run, and marking a whole
// batch in one transaction are not tidiness: a sync that takes a minute is one
// people cancel, and a cancelled sync is a queue that never empties.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/api.dart';
import 'package:safenest/offline/store.dart';
import 'package:safenest/track/push.dart';

import 'offline_store_test.dart' show memSecure;

/// A server that answers from a script.
class _FakeApi implements Api {
  _FakeApi({this.answer, this.fail, this.malformed = false});

  final List<dynamic> Function(List items)? answer;
  final ApiError? fail;
  final bool malformed;

  final batches = <List>[];

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    expect(path, '/api/track/batch');
    if (fail != null) throw fail!;
    final items = ((body as Map)['items'] as List);
    batches.add(items);
    if (malformed) return {'nothing': 'useful'};
    return {'results': answer?.call(items) ?? [for (final _ in items) {}]};
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

List<dynamic> _accept(List items, {bool duplicate = false}) => [
      for (final i in items)
        {
          'device_row_id': (i as Map)['device_row_id'],
          'id': 1000 + (i['device_row_id'] as int),
          'duplicate': duplicate,
        }
    ];

var _seq = 0;
Future<OfflineStore> _store() async {
  final dir = await Directory.systemTemp.createTemp('safenest-tpush');
  addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
  return OfflineStore(
      secure: memSecure(), path: p.join(dir.path, 'tpush${_seq++}.db'));
}

final start = DateTime(2026, 10, 3, 6, 0);

/// [n] fixes, far enough apart in time that none is thinned away.
Future<OfflineStore> _withFixes(int n) async {
  final s = await _store();
  for (var i = 0; i < n; i++) {
    await s.addFix(
      at: start.add(Duration(minutes: i * 20)),
      lat: 12.9279 + i * 0.01,
      lon: 77.6271,
      accuracy: 10,
      battery: 80 - i,
    );
  }
  return s;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('nothing to send does not call the server', () async {
    final store = await _store();
    final api = _FakeApi();
    final r = await pushFixes(store, api);
    expect(api.batches, isEmpty);
    expect(r.sent, 0);
  });

  test('what the computer does not have goes up, and is marked', () async {
    final store = await _withFixes(3);
    final api = _FakeApi(answer: _accept);

    final r = await pushFixes(store, api);
    expect(r.sent, 3);
    expect(r.problems, isEmpty);
    expect(await store.unsyncedFixCount(), 0);
  });

  test('the time, the place and how sure the phone was all travel', () async {
    // Accuracy matters on the wire because the reader throws away anything
    // worse than 200m — a cell-tower guess averaged into a stay moves the place
    // to one nobody has ever been.
    final store = await _withFixes(1);
    final api = _FakeApi(answer: _accept);
    await pushFixes(store, api);

    final sent = api.batches.single.single as Map;
    expect(sent['lat'], closeTo(12.9279, 0.0001));
    expect(sent['accuracy'], 10);
    expect(sent['battery'], 80);
    expect('${sent['at']}', startsWith('2026-10-03'));
    expect(sent['client_uuid'], isNotNull,
        reason: 'the idempotency key is the whole contract');
  });

  test('every fix carries a key of its own', () async {
    final store = await _withFixes(4);
    final api = _FakeApi(answer: _accept);
    await pushFixes(store, api);
    final keys = {
      for (final i in api.batches.single) '${(i as Map)['client_uuid']}'
    };
    expect(keys, hasLength(4));
  });

  group('when the computer cannot be reached', () {
    test('nothing is marked, so everything is offered again', () async {
      final store = await _withFixes(3);
      final api = _FakeApi(fail: ApiError(0, 'Could not reach your SafeNest'));

      final r = await pushFixes(store, api);
      expect(r.sent, 0);
      expect(r.problems, hasLength(1));
      expect(await store.unsyncedFixCount(), 3);
    });

    test('a reply this phone cannot read is treated the same way', () async {
      final store = await _withFixes(3);
      final api = _FakeApi(malformed: true);
      final r = await pushFixes(store, api);
      expect(await store.unsyncedFixCount(), 3);
      expect(r.problems, isNotEmpty);
    });
  });

  test('a replay is counted apart from something new', () async {
    // A sync reporting "600 sent" when it re-sent the same six hundred is one
    // nobody can use to tell whether anything is wrong.
    final store = await _withFixes(3);
    final api = _FakeApi(answer: (items) => _accept(items, duplicate: true));

    final r = await pushFixes(store, api);
    expect(r.sent, 0);
    expect(r.already, 3);
    expect(await store.unsyncedFixCount(), 0,
        reason: 'the computer has them, however they got there');
  });

  test('one the computer refuses does not block the rest', () async {
    final store = await _withFixes(3);
    final api = _FakeApi(answer: (items) => [
          for (var i = 0; i < items.length; i++)
            if (i == 0)
              {
                'device_row_id': (items[i] as Map)['device_row_id'],
                'error': 'that is not a place on Earth',
              }
            else
              {
                'device_row_id': (items[i] as Map)['device_row_id'],
                'id': 500 + i,
                'duplicate': false,
              }
        ]);

    final r = await pushFixes(store, api);
    expect(r.refused, 1);
    expect(r.sent, 2);
    expect(await store.unsyncedFixCount(), 1,
        reason: 'the refused one stays on the phone, where it is safe');
  });

  test('results are matched by row id, not by position', () async {
    // A server that filtered or reordered would otherwise mark the wrong fixes
    // as sent, and a fix wrongly marked never goes up again.
    final store = await _withFixes(3);
    final api =
        _FakeApi(answer: (items) => _accept(items).reversed.toList());

    await pushFixes(store, api);
    expect(await store.unsyncedFixCount(), 0);
  });

  test('a reply that says nothing about a fix leaves it unsent', () async {
    final store = await _withFixes(3);
    final api = _FakeApi(answer: (items) => [_accept(items).first]);

    final r = await pushFixes(store, api);
    expect(r.sent, 1);
    expect(r.problems, isNotEmpty);
    expect(await store.unsyncedFixCount(), 2);
  });

  test('a server that answers nothing does not spin for ever', () async {
    // Without a progress check the next query returns the same rows and the
    // sync loops until the app is killed — holding the Sync button open.
    final store = await _withFixes(3);
    final api = _FakeApi(answer: (_) => const []);

    final r = await pushFixes(store, api);
    expect(api.batches, hasLength(1));
    expect(r.sent, 0);
    expect(await store.unsyncedFixCount(), 3);
  });

  test('a long backlog goes in batches', () async {
    final store = await _withFixes(7);
    final api = _FakeApi(answer: _accept);

    final r = await pushFixes(store, api, batch: 3);
    expect(r.sent, 7);
    expect(api.batches.map((b) => b.length), [3, 3, 1]);
    expect(await store.unsyncedFixCount(), 0);
  });

  test('one run is capped, and the rest goes next time', () async {
    // A fortnight abroad is thousands of fixes, and a sync that holds the
    // button for a minute is one people cancel.
    final store = await _withFixes(6);
    final api = _FakeApi(answer: _accept);

    final r = await pushFixes(store, api, batch: 2, limit: 4);
    expect(r.sent, 4);
    expect(await store.unsyncedFixCount(), 2);
  });
}
