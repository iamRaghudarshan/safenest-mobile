// Getting memories to the computer.
//
// Against a fake server, because what needs pinning is how the push reacts to
// each ANSWER, and the answers worth testing — a dropped reply, a replay, one
// item the server will never accept, a reordered result list — are the ones a
// real server will not produce on demand.
//
// The rule underneath every case here: the phone's row is the ORIGINAL, not a
// cache. So a memory wrongly marked as sent is a memory that never goes up
// again, and a memory wrongly left unsent costs one harmless retry. Every
// uncertain case has to fall the second way.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:safenest/api.dart';
import 'package:safenest/memory/push.dart';
import 'package:safenest/offline/store.dart';

import 'offline_store_test.dart' show memSecure;

/// A server that answers from a script.
class _FakeApi implements Api {
  _FakeApi({this.answer, this.fail, this.malformed = false});

  /// Given the items it was sent, what to reply with.
  final List<dynamic> Function(List items)? answer;
  final ApiError? fail;
  final bool malformed;

  final batches = <List>[];

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    expect(path, '/api/memories/batch');
    if (fail != null) throw fail!;
    final items = ((body as Map)['items'] as List);
    batches.add(items);
    if (malformed) return {'nothing': 'useful'};
    return {'results': answer?.call(items) ?? [for (final _ in items) {}]};
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Accepted, with a server id derived from the phone's row id.
List<dynamic> _accept(List items, {bool duplicate = false}) => [
      for (final i in items)
        {
          'client_uuid': (i as Map)['client_uuid'],
          'device_row_id': i['device_row_id'],
          'id': 1000 + (i['device_row_id'] as int),
          'duplicate': duplicate,
        }
    ];

var _seq = 0;
Future<OfflineStore> _store() async {
  final dir = await Directory.systemTemp.createTemp('safenest-push');
  addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
  return OfflineStore(
      secure: memSecure(), path: p.join(dir.path, 'push${_seq++}.db'));
}

Future<OfflineStore> _withTwo() async {
  final s = await _store();
  await s.addMemory(
      body: 'Bought the washing machine from Vijay Sales',
      saidAt: DateTime(2026, 9, 20),
      spoken: true,
      facts: [
        (kind: 'shop', value: 'Vijay Sales', at: null),
        (
          kind: 'expiry',
          value: 'Warranty ends 20 Sep 2028',
          at: DateTime(2028, 9, 20)
        ),
      ]);
  await s.addMemory(
      body: 'Amma says tamarind first', saidAt: DateTime(2026, 9, 25));
  return s;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('nothing to send does not call the server at all', () async {
    final store = await _store();
    final api = _FakeApi();
    final r = await pushMemories(store, api);
    expect(api.batches, isEmpty);
    expect(r.sent, 0);
  });

  test('what the computer does not have goes up, and is marked', () async {
    final store = await _withTwo();
    final api = _FakeApi(answer: _accept);

    final r = await pushMemories(store, api);
    expect(r.sent, 2);
    expect(r.already, 0);
    expect(r.problems, isEmpty);
    expect(await store.unsyncedMemoryCount(), 0);

    // And the ids came back onto the right rows, which is what the cloud mark on
    // each card reads.
    final rows = await store.memories();
    expect({for (final m in rows) m['body']: m['server_id']}.values,
        everyElement(isNotNull));
  });

  test('the words, the time they were said, and the facts all travel',
      () async {
    final store = await _withTwo();
    final api = _FakeApi(answer: _accept);
    await pushMemories(store, api);

    final sent = api.batches.single;
    final washing = sent.firstWhere(
        (i) => '${(i as Map)['body']}'.contains('washing')) as Map;

    expect(washing['body'], 'Bought the washing machine from Vijay Sales');
    expect(washing['spoken'], isTrue);
    // WHEN IT WAS SAID, not when it was sent. Otherwise a week of memories
    // spoken abroad all arrive stamped with the afternoon of the flight home.
    expect('${washing['said_at']}', startsWith('2026-09-20'));
    expect((washing['facts'] as List), hasLength(2));
    expect(washing['client_uuid'], isNotNull,
        reason: 'the idempotency key is the whole contract');
  });

  test('every memory gets its own uuid', () async {
    final store = await _withTwo();
    final api = _FakeApi(answer: _accept);
    await pushMemories(store, api);
    final uuids = {
      for (final i in api.batches.single) '${(i as Map)['client_uuid']}'
    };
    expect(uuids, hasLength(2));
  });

  test('oldest first, so the computer fills forwards', () async {
    final store = await _withTwo();
    final api = _FakeApi(answer: _accept);
    await pushMemories(store, api);
    expect('${(api.batches.single.first as Map)['body']}',
        contains('washing machine'));
  });

  group('when the computer cannot be reached', () {
    test('nothing is marked, so everything is offered again', () async {
      // The most important case in this file. The words are on the phone either
      // way; what must not happen is a row quietly recorded as sent.
      final store = await _withTwo();
      final api = _FakeApi(fail: ApiError(0, 'Could not reach your SafeNest'));

      final r = await pushMemories(store, api);
      expect(r.sent, 0);
      expect(r.problems, hasLength(1));
      expect(r.problems.single, contains('could not be sent'));
      expect(await store.unsyncedMemoryCount(), 2);
    });

    test('a reply this phone cannot read is treated the same way', () async {
      final store = await _withTwo();
      final api = _FakeApi(malformed: true);
      final r = await pushMemories(store, api);
      expect(await store.unsyncedMemoryCount(), 2);
      expect(r.problems, isNotEmpty);
    });
  });

  test('a replay is counted separately from something new', () async {
    // A sync reporting "2 sent" when it re-sent the same two is a sync nobody
    // can use to tell whether anything is wrong.
    final store = await _withTwo();
    final api = _FakeApi(answer: (items) => _accept(items, duplicate: true));

    final r = await pushMemories(store, api);
    expect(r.sent, 0);
    expect(r.already, 2);
    expect(await store.unsyncedMemoryCount(), 0,
        reason: 'the computer has it, however it got there');
  });

  test('one the computer refuses does not block the rest', () async {
    final store = await _withTwo();
    final api = _FakeApi(answer: (items) => [
          for (var i = 0; i < items.length; i++)
            if (i == 0)
              {
                'device_row_id': (items[i] as Map)['device_row_id'],
                'error': 'a memory with no words is not a memory',
              }
            else
              {
                'device_row_id': (items[i] as Map)['device_row_id'],
                'id': 77,
                'duplicate': false,
              }
        ]);

    final r = await pushMemories(store, api);
    expect(r.refused, 1);
    expect(r.sent, 1);
    // The refused one stays unsent on the phone, which is where it is safe —
    // and it is not marked, so nothing has been quietly lost.
    expect(await store.unsyncedMemoryCount(), 1);
  });

  test('results are matched by row id, not by position', () async {
    // A server that filters or reorders would otherwise have this marking the
    // wrong memories as sent, and a memory wrongly marked never goes up again.
    final store = await _withTwo();
    final api = _FakeApi(
        answer: (items) => _accept(items).reversed.toList());

    await pushMemories(store, api);
    final rows = await store.memories();
    for (final m in rows) {
      expect(m['server_id'], 1000 + (m['id'] as int),
          reason: 'each id must land on the row it belongs to');
    }
  });

  test('a reply that says nothing about a memory leaves it unsent', () async {
    final store = await _withTwo();
    final api = _FakeApi(answer: (items) => [_accept(items).first]);

    final r = await pushMemories(store, api);
    expect(r.sent, 1);
    expect(r.problems, isNotEmpty);
    expect(await store.unsyncedMemoryCount(), 1);
  });

  test('a server that answers nothing at all does not spin for ever',
      () async {
    // Without a progress check the next query returns the same rows and the
    // sync loops until the app is killed — and it would do it holding the
    // Sync button open.
    final store = await _withTwo();
    final api = _FakeApi(answer: (_) => const []);

    final r = await pushMemories(store, api);
    expect(api.batches, hasLength(1), reason: 'it must stop after one try');
    expect(r.sent, 0);
    expect(await store.unsyncedMemoryCount(), 2);
  });

  test('a long backlog is sent in batches and keeps its place', () async {
    final store = await _store();
    for (var i = 0; i < 7; i++) {
      await store.addMemory(
          body: 'memory $i', saidAt: DateTime(2026, 9, 1).add(Duration(days: i)));
    }
    final api = _FakeApi(answer: _accept);

    final r = await pushMemories(store, api, batch: 3);
    expect(r.sent, 7);
    expect(api.batches.map((b) => b.length), [3, 3, 1]);
    expect(await store.unsyncedMemoryCount(), 0);
  });

  test('one run is capped, and the rest goes next time', () async {
    final store = await _store();
    for (var i = 0; i < 6; i++) {
      await store.addMemory(body: 'memory $i', saidAt: DateTime(2026, 9, 1));
    }
    final api = _FakeApi(answer: _accept);

    final r = await pushMemories(store, api, batch: 2, limit: 4);
    expect(r.sent, 4);
    expect(await store.unsyncedMemoryCount(), 2,
        reason: 'what is left is still derived from the data, not remembered');
  });
}
