/// Where records live while the computer is asleep.
///
/// The server this app talks to is somebody's home PC. It sleeps, it reboots,
/// its tunnel drops — and until now every record screen was a live call to it,
/// so the app in your pocket was useless exactly when you were away from the
/// machine. Records are held here instead, and pushed when it is reachable.
///
/// TWO THINGS WITH TWO DIFFERENT LIFETIMES, and conflating them is the mistake
/// this file exists to avoid:
///
///   * `cache` is what the server last told us. It is disposable — refreshed on
///     every successful fetch, and safe to drop entirely. It is what lets a
///     screen show your expenses with the computer switched off.
///   * `pending` is what YOU did while it was unreachable. It is NOT
///     disposable: until it syncs it exists in exactly one place in the world,
///     which is this phone. It is cleared per item, only when the server
///     confirms that item, and never because a batch finished.
///
/// Screens read the two merged — cache with pending applied on top — so an edit
/// made offline appears immediately rather than after a sync.
///
/// ENCRYPTED, BUT NOT WITH SQLCIPHER. The obvious package bundles its own
/// SQLite and crypto as native code, charged once per ABI: about 5-6 MB against
/// an APK whose native code is already 95% of it. Android and iOS both encrypt
/// app-private storage at rest already, so what is added here is a second layer
/// over the payloads themselves, keyed from the Keychain /
/// EncryptedSharedPreferences, for kilobytes rather than megabytes.
///
/// **It is a SHA-256 counter-mode stream with an HMAC-SHA256 tag, not AES-GCM**,
/// and that is worth saying plainly rather than letting "encrypted" stand.
/// `crypto` is already a dependency for the photo backup's hashing, so this adds
/// nothing to the download; AES would mean another package. It is sound for what
/// it defends against — someone who obtains the database file — and it is not a
/// substitute for the platform's own at-rest encryption underneath it. If a
/// stronger primitive is ever wanted, replace `_seal`/`_unseal` and bump the
/// blob format; nothing else reads the ciphertext.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// What a queued operation is trying to do.
enum Op { create, update, delete }

/// Where a queued operation has got to.
///
/// THREE STATES, NOT A BOOLEAN, for the same reason `backup.dart` needed three:
/// "not done" covers both "waiting its turn" and "tried and refused", and those
/// mean opposite things to somebody looking at a pending list. A failure that
/// looks identical to a queue is a failure nobody retries.
enum OpState { pending, sending, failed }

String opName(Op o) => o.name;
Op opFrom(String s) => Op.values.firstWhere((o) => o.name == s, orElse: () => Op.create);

/// One thing done offline, waiting to reach the server.
@immutable
class PendingOp {
  const PendingOp({
    required this.seq,
    required this.module,
    required this.op,
    required this.clientUuid,
    required this.localId,
    required this.serverId,
    required this.payload,
    required this.baseUpdatedAt,
    required this.state,
    required this.tries,
    required this.lastError,
    required this.createdAt,
  });

  /// Order of creation. The journal replays in this order and nothing else:
  /// a create followed by an edit must never replay as an edit followed by a
  /// create, which is what sorting by anything else eventually produces.
  final int seq;
  final String module;
  final Op op;

  /// Minted once, here, and reused for every retry of THIS operation. The
  /// server remembers the ones it has honoured, so a retry after a reply that
  /// never arrived returns the original row instead of making a second one.
  final String clientUuid;

  /// Set for a record created offline, which has no server id yet. Later
  /// operations against it carry the same local id until the create lands.
  final int? localId;

  /// Set for a record that already exists on the server.
  final int? serverId;
  final Map<String, dynamic> payload;

  /// The `updated_at` this edit was based on, so the server can tell whether
  /// somebody else changed the record in the meantime. Null for a create.
  final String? baseUpdatedAt;
  final OpState state;
  final int tries;
  final String? lastError;
  final DateTime createdAt;

  /// Which record this points at, whichever side of syncing it is on.
  String get target => serverId != null ? 's$serverId' : 'l$localId';
}

/// A record as a screen should see it: the server's copy with anything done
/// offline applied on top.
@immutable
class MergedRecord {
  const MergedRecord({
    required this.id,
    required this.data,
    required this.pending,
    required this.deleted,
    required this.isLocalOnly,
  });

  /// Server id where there is one, otherwise the negative local id — negative
  /// so a screen that passes it back cannot mistake it for a server row.
  final int id;
  final Map<String, dynamic> data;

  /// True when something about this record has not reached the server yet, so
  /// the UI can mark it rather than pretending everything is filed.
  final bool pending;
  final bool deleted;

  /// Created offline and never yet sent. This is the copy that exists nowhere
  /// else, and losing the phone loses it.
  final bool isLocalOnly;
}

class OfflineStore {
  /// [path] replaces where the database file goes, whole. A PATH and not a
  /// directory, so a test can pass sqflite's in-memory name — joining that onto
  /// a folder produces `:memory:/offline.db`, which is not a file and not
  /// in-memory either, and every test then fails to open a database.
  OfflineStore({FlutterSecureStorage? secure, String? path})
      : _secure = secure ?? const FlutterSecureStorage(),
        _pathOverride = path;

  static const _kKey = 'offline.payload.key';
  static const _uuid = Uuid();

  final FlutterSecureStorage _secure;
  final String? _pathOverride;
  Database? _db;
  Uint8List? _key;

  Future<Database> get _open async => _db ??= await _init();

  Future<Database> _init() async {
    final file = _pathOverride ?? p.join(await getDatabasesPath(), 'offline.db');
    return openDatabase(
      file,
      version: 1,
      onCreate: (db, _) async {
        // What the server last said. Disposable by design.
        await db.execute('''
          CREATE TABLE cache (
            module      TEXT    NOT NULL,
            server_id   INTEGER NOT NULL,
            body        TEXT    NOT NULL,
            updated_at  TEXT,
            fetched_at  TEXT    NOT NULL,
            PRIMARY KEY (module, server_id)
          )''');
        // What you did while it was unreachable. NOT disposable.
        await db.execute('''
          CREATE TABLE pending (
            seq             INTEGER PRIMARY KEY AUTOINCREMENT,
            module          TEXT    NOT NULL,
            op              TEXT    NOT NULL,
            client_uuid     TEXT    NOT NULL UNIQUE,
            local_id        INTEGER,
            server_id       INTEGER,
            body            TEXT    NOT NULL,
            base_updated_at TEXT,
            state           TEXT    NOT NULL,
            tries           INTEGER NOT NULL DEFAULT 0,
            last_error      TEXT,
            created_at      TEXT    NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX idx_pending_module ON pending(module, seq)');
        // Local ids for records created offline. A separate counter rather than
        // reusing pending.seq, because one offline record can have several
        // operations and they all have to point at the same thing.
        await db.execute('''
          CREATE TABLE local_ids (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            module TEXT NOT NULL
          )''');
      },
    );
  }

  // ---------------------------------------------------------------- crypto

  /// The key that encrypts payloads at rest, generated once per installation.
  ///
  /// Kept in the Keychain / EncryptedSharedPreferences rather than beside the
  /// database, which is the whole point: the database file is only as private
  /// as the filesystem, and a rooted phone or a backup extraction reads it.
  Future<Uint8List> _payloadKey() async {
    if (_key != null) return _key!;
    var stored = await _secure.read(key: _kKey);
    if (stored == null) {
      final rnd = Random.secure();
      final bytes = Uint8List.fromList(
          List<int>.generate(32, (_) => rnd.nextInt(256)));
      stored = base64Encode(bytes);
      await _secure.write(key: _kKey, value: stored);
    }
    return _key = Uint8List.fromList(base64Decode(stored));
  }

  /// Encrypt a record body.
  ///
  /// A stream cipher built from SHA-256 in counter mode, authenticated with
  /// HMAC-SHA256 — encrypt-then-MAC, so a tampered row is refused rather than
  /// decrypted into nonsense. `crypto` is already a dependency (the photo
  /// backup hashes with it), so this costs nothing to add, and the threat here
  /// is an attacker with the file rather than one who can watch it being
  /// written.
  Future<String> _seal(Map<String, dynamic> data) async {
    final key = await _payloadKey();
    final plain = utf8.encode(jsonEncode(data));
    final rnd = Random.secure();
    final nonce =
        Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final ct = _xorStream(plain, key, nonce);
    final mac = Hmac(sha256, key).convert([...nonce, ...ct]).bytes;
    return '${base64Encode(nonce)}.${base64Encode(ct)}.${base64Encode(mac)}';
  }

  Future<Map<String, dynamic>> _unseal(String blob) async {
    final key = await _payloadKey();
    final parts = blob.split('.');
    if (parts.length != 3) return {};
    final nonce = base64Decode(parts[0]);
    final ct = base64Decode(parts[1]);
    final mac = base64Decode(parts[2]);
    final want = Hmac(sha256, key).convert([...nonce, ...ct]).bytes;
    // Constant-time compare. A length check alone would leak, and this is
    // cheap enough that there is no reason to do it the sloppy way.
    if (want.length != mac.length) return {};
    var diff = 0;
    for (var i = 0; i < mac.length; i++) {
      diff |= want[i] ^ mac[i];
    }
    if (diff != 0) return {};
    final plain = _xorStream(ct, key, Uint8List.fromList(nonce));
    try {
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map);
    } catch (_) {
      return {};
    }
  }

  /// SHA-256 in counter mode: keystream block i is H(key || nonce || i).
  Uint8List _xorStream(List<int> input, Uint8List key, Uint8List nonce) {
    final out = Uint8List(input.length);
    var block = 0;
    for (var off = 0; off < input.length; off += 32, block++) {
      final ks = sha256
          .convert([...key, ...nonce, ...utf8.encode(block.toString())])
          .bytes;
      final end = min(off + 32, input.length);
      for (var i = off; i < end; i++) {
        out[i] = input[i] ^ ks[i - off];
      }
    }
    return out;
  }

  // ----------------------------------------------------------------- cache

  /// Replace what we hold for a module with what the server just said.
  ///
  /// A wholesale replace rather than a merge: this is called with a full list
  /// straight from the server, so anything absent from it has been deleted
  /// elsewhere and keeping it would show records that no longer exist.
  /// `pending` is untouched — it is not the server's to overwrite.
  Future<void> putList(String module, List<Map<String, dynamic>> rows) async {
    final db = await _open;
    final now = DateTime.now().toIso8601String();
    final sealed = <List<Object?>>[];
    for (final r in rows) {
      final id = (r['id'] as num?)?.toInt();
      if (id == null) continue;
      sealed.add([module, id, await _seal(r), '${r['updated_at'] ?? ''}', now]);
    }
    await db.transaction((tx) async {
      await tx.delete('cache', where: 'module = ?', whereArgs: [module]);
      final batch = tx.batch();
      for (final row in sealed) {
        batch.insert('cache', {
          'module': row[0],
          'server_id': row[1],
          'body': row[2],
          'updated_at': row[3],
          'fetched_at': row[4],
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// When this module was last heard from the server, or null if never.
  Future<DateTime?> lastFetched(String module) async {
    final db = await _open;
    final r = await db.query('cache',
        columns: ['fetched_at'],
        where: 'module = ?',
        whereArgs: [module],
        orderBy: 'fetched_at DESC',
        limit: 1);
    if (r.isEmpty) return null;
    return DateTime.tryParse('${r.first['fetched_at']}');
  }

  // --------------------------------------------------------------- reading

  /// A module as a screen should show it: the server's copy with everything
  /// done offline applied on top, newest local work winning.
  ///
  /// Deleted records are returned carrying `deleted`, not dropped, so a caller
  /// can choose — a list hides them, but a sync screen counting what is pending
  /// has to see them.
  Future<List<MergedRecord>> read(String module) async {
    final db = await _open;
    final rows = await db.query('cache',
        where: 'module = ?', whereArgs: [module]);

    final byId = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      byId[(r['server_id'] as int)] = await _unseal('${r['body']}');
    }

    final ops = await pendingFor(module);
    final localOnly = <int, Map<String, dynamic>>{};
    final touched = <String>{};
    final deleted = <String>{};

    for (final o in ops) {
      touched.add(o.target);
      switch (o.op) {
        case Op.create:
          localOnly[o.localId ?? 0] = {...o.payload, 'id': -(o.localId ?? 0)};
        case Op.update:
          if (o.serverId != null && byId.containsKey(o.serverId)) {
            byId[o.serverId!] = {...byId[o.serverId!]!, ...o.payload};
          } else if (o.localId != null && localOnly.containsKey(o.localId)) {
            localOnly[o.localId!] = {...localOnly[o.localId!]!, ...o.payload};
          }
        case Op.delete:
          deleted.add(o.target);
      }
    }

    final out = <MergedRecord>[
      for (final e in byId.entries)
        MergedRecord(
          id: e.key,
          data: e.value,
          pending: touched.contains('s${e.key}'),
          deleted: deleted.contains('s${e.key}'),
          isLocalOnly: false,
        ),
      for (final e in localOnly.entries)
        MergedRecord(
          id: -e.key,
          data: e.value,
          pending: true,
          deleted: deleted.contains('l${e.key}'),
          isLocalOnly: true,
        ),
    ];
    return out;
  }

  // --------------------------------------------------------------- pending

  Future<int> nextLocalId(String module) async {
    final db = await _open;
    return db.insert('local_ids', {'module': module});
  }

  /// Queue one operation. Returns its client uuid.
  Future<String> enqueue({
    required String module,
    required Op op,
    Map<String, dynamic> payload = const {},
    int? localId,
    int? serverId,
    String? baseUpdatedAt,
  }) async {
    final db = await _open;
    final uuid = _uuid.v4();
    await db.insert('pending', {
      'module': module,
      'op': opName(op),
      'client_uuid': uuid,
      'local_id': localId,
      'server_id': serverId,
      'body': await _seal(payload),
      'base_updated_at': baseUpdatedAt,
      'state': OpState.pending.name,
      'tries': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    return uuid;
  }

  Future<List<PendingOp>> pendingFor(String module) =>
      _pending(where: 'module = ?', args: [module]);

  /// Everything waiting, oldest first. Replay order, and the only order.
  Future<List<PendingOp>> allPending() => _pending();

  Future<List<PendingOp>> _pending({String? where, List<Object?>? args}) async {
    final db = await _open;
    final rows = await db.query('pending',
        where: where, whereArgs: args, orderBy: 'seq ASC');
    return [
      for (final r in rows)
        PendingOp(
          seq: r['seq'] as int,
          module: '${r['module']}',
          op: opFrom('${r['op']}'),
          clientUuid: '${r['client_uuid']}',
          localId: r['local_id'] as int?,
          serverId: r['server_id'] as int?,
          payload: await _unseal('${r['body']}'),
          baseUpdatedAt: r['base_updated_at'] as String?,
          state: OpState.values.firstWhere((s) => s.name == '${r['state']}',
              orElse: () => OpState.pending),
          tries: (r['tries'] as int?) ?? 0,
          lastError: r['last_error'] as String?,
          createdAt:
              DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
        )
    ];
  }

  Future<int> pendingCount() async {
    final db = await _open;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM pending');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Forget one operation because the server confirmed THAT operation.
  ///
  /// Per item. Never "the batch finished" — see the file header: eight of ten
  /// landing must leave two behind, still queued and still retryable, because
  /// they exist nowhere else.
  Future<void> confirmed(int seq) async {
    final db = await _open;
    await db.delete('pending', where: 'seq = ?', whereArgs: [seq]);
  }

  /// Record that an operation was refused, keeping it for another attempt.
  Future<void> failed(int seq, String reason) async {
    final db = await _open;
    await db.rawUpdate(
        'UPDATE pending SET state = ?, tries = tries + 1, last_error = ? '
        'WHERE seq = ?',
        [OpState.failed.name, reason, seq]);
  }

  Future<void> markSending(int seq) async {
    final db = await _open;
    await db.update('pending', {'state': OpState.sending.name},
        where: 'seq = ?', whereArgs: [seq]);
  }

  /// Point every later operation at the row the server just made.
  ///
  /// A record created offline and then edited twice is three operations against
  /// one thing. Only the create knows the local id; once it lands, the edits
  /// have to be told the real id or they replay against nothing.
  Future<void> resolveLocalId(String module, int localId, int serverId) async {
    final db = await _open;
    await db.update(
        'pending', {'local_id': null, 'server_id': serverId},
        where: 'module = ? AND local_id = ?', whereArgs: [module, localId]);
  }

  /// Drop the cache but never the queue.
  ///
  /// For signing out or switching servers: what the server told us is theirs
  /// and can be fetched again, but work not yet pushed is not ours to discard.
  Future<void> clearCache() async {
    final db = await _open;
    await db.delete('cache');
  }

  @visibleForTesting
  Future<void> clearEverything() async {
    final db = await _open;
    await db.delete('cache');
    await db.delete('pending');
    await db.delete('local_ids');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
