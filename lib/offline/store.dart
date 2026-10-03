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
import 'dart:math' as math;
import 'dart:math' show Random, min;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// What a queued operation is trying to do.
///
/// `action` is the fourth because create/update/delete does not describe what
/// people actually do to some records. Ticking a habit is `POST
/// /api/habits/{id}/check`, and a habit tracker that cannot be ticked without
/// the computer is not working offline in any sense the owner would recognise.
/// Pinning and archiving a note are the same shape.
enum Op { create, update, delete, action }

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
    this.action,
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

  /// For [Op.action]: which one, e.g. `check` for a habit or `pin` for a note.
  /// The server keeps a fixed list of the actions it will accept — this is not
  /// a path a client gets to choose.
  final String? action;
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

/// Scans and other uploads waiting to go, held as FILES rather than payloads.
///
/// A scanned page is a few megabytes of JPEG. Putting that through the same
/// journal as an expense would mean base64 inside an encrypted JSON blob inside
/// a row — several times the size, all of it in memory at once, for something
/// the filesystem already stores perfectly well. So the bytes stay on disk and
/// this table remembers where they are and what they were for.
///
/// `paths` is a newline-joined list because one scan is often several pages and
/// they must arrive as ONE document, not five.
const _pendingFilesDDL = '''
  CREATE TABLE pending_files (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    module      TEXT    NOT NULL,
    client_uuid TEXT    NOT NULL UNIQUE,
    paths       TEXT    NOT NULL,
    fields      TEXT    NOT NULL,
    state       TEXT    NOT NULL,
    tries       INTEGER NOT NULL DEFAULT 0,
    last_error  TEXT,
    created_at  TEXT    NOT NULL
  )''';

/// What this phone has already backed up, and enough about each item to know
/// it has not changed since.
///
/// THE POINT OF THIS TABLE IS THE WORK IT AVOIDS. The backup used to decide
/// "have I sent this?" by hashing the file — sha256 over every byte — and then
/// asking the computer. That is a read of the entire photo library, tens of
/// gigabytes, performed to ask a question. It is why a repeat backup "keeps
/// running for a long time".
///
/// Google Photos does not do that, and neither does this now: an asset whose
/// id, modified time and size all match a row here is skipped without the file
/// being opened at all. Hashing is kept for what is genuinely NEW, where the
/// file has to be read anyway to upload it.
///
/// `modified` and `signature` are what make it safe. An id alone would skip a
/// photo edited in place — same id, different picture — and it would never
/// reach the computer.
///
/// **`signature` is cheap metadata, NOT a byte count.** Width, height and
/// duration, combined. The real file size would be a better signal and costs
/// exactly the thing this table exists to avoid: opening the file. These three
/// come from the library index the phone already holds, so the check stays
/// free, and together with the modified time they catch every ordinary edit.
///
/// In SQLite rather than the StringList this replaces: twenty thousand ids in
/// SharedPreferences is a multi-megabyte blob rewritten whole on every save and
/// re-parsed at every launch.
const _ledgerDDL = '''
  CREATE TABLE backup_ledger (
    asset_id TEXT PRIMARY KEY,
    modified  INTEGER NOT NULL DEFAULT 0,
    signature INTEGER NOT NULL DEFAULT 0,
    sent_at  TEXT    NOT NULL
  )''';

const _ledgerIndexDDL =
    'CREATE INDEX idx_ledger_sent ON backup_ledger(sent_at)';

/// Assets the person has told the backup to stop trying.
///
/// WHY THIS IS NOT backup_ledger WITH A FLAG. That table means "the computer
/// has this". Putting a skipped item in it would make the cheap skip believe
/// the file was safely on the computer, and the count on screen would say a
/// library was backed up when part of it deliberately is not. The distinction
/// is the whole point: skipped means "I know it is not there and I am content
/// with that", which is a different sentence and has to be a different table.
///
/// The reason is kept so the list can say what it was stuck on, and `at` so
/// the newest decision is shown first. Nothing here is sent anywhere; it is
/// one phone's opinion about its own library.
const _ignoredDDL = '''
  CREATE TABLE backup_ignored (
    asset_id TEXT PRIMARY KEY,
    reason   TEXT NOT NULL DEFAULT '',
    at       TEXT NOT NULL
  )''';

/// LIFE MEMORY: the things somebody has told the app.
///
/// On the PHONE first and always. Every other module in SafeNest is a cache of
/// what the server holds, refreshed when it can be; this one is the opposite —
/// the phone is where a memory is created, by speaking, and very often with no
/// signal at all. It is written here, shown at once, and queued for the
/// computer; `server_id` stays null until the computer has it, and that is the
/// only thing the cloud mark on a card reads.
///
/// `body` is the words, verbatim. Everything else is derived from them and can
/// be rebuilt; the words cannot, so they are what is protected.
const _memoriesDDL = '''
  CREATE TABLE memories (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    server_id  INTEGER,
    client_uuid TEXT,
    said_at    TEXT    NOT NULL,
    body       TEXT    NOT NULL,
    spoken     INTEGER NOT NULL DEFAULT 0,
    photo_id   TEXT,
    photo_path TEXT,
    created_at TEXT    NOT NULL,
    updated_at TEXT    NOT NULL
  )''';

const _memoriesIndexDDL =
    'CREATE INDEX idx_memories_said ON memories(said_at DESC)';

/// The facts a person CONFIRMED about a memory.
///
/// A separate table rather than columns on `memories`, because one memory can
/// carry several of the same kind — two people, a place and a shop — and
/// because only what was confirmed is here at all. What the reader merely
/// guessed is not stored anywhere: it is re-read from the words whenever it is
/// wanted, so a better reader later improves old memories instead of leaving
/// yesterday's guesses lying about as though somebody had agreed to them.
///
/// `at` is set only for the kinds that point at a moment, and it is what the
/// reminders are built from.
const _factsDDL = '''
  CREATE TABLE memory_facts (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_id INTEGER NOT NULL,
    kind      TEXT    NOT NULL,
    value     TEXT    NOT NULL,
    at        TEXT
  )''';

const _factsIndexDDL =
    'CREATE INDEX idx_facts_memory ON memory_facts(memory_id)';

const _factsAtIndexDDL =
    'CREATE INDEX idx_facts_at ON memory_facts(at)';

/// TRACK ME: where this phone has been.
///
/// PHONE-FIRST like Life Memory, and for a stronger reason. A fix is taken with
/// the screen off, often with no signal — in a basement, on a train, abroad —
/// and if it is not written down the moment it is taken there is nothing to
/// write down later. The server copy is a copy; `server_id` stays null until it
/// has been pushed, and that is the only thing syncing changes.
///
/// ONE ROW PER FIX, deliberately, rather than storing the stays and journeys
/// that `track/day.dart` works out from them. The rules for cutting a day up
/// WILL change — the first version of any such rule is wrong about somebody's
/// commute — and storing the conclusions would mean yesterday is stuck with
/// yesterday's rules for ever. The fixes are the evidence; everything else is
/// re-derived on read.
///
/// `at` is the phone's clock at the moment of the fix, in UTC, and the day
/// boundary is applied on read against the LOCAL calendar. Storing a local
/// timestamp instead would make a day abroad unreadable.
const _trackDDL = '''
  CREATE TABLE track_points (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    server_id INTEGER,
    at        TEXT    NOT NULL,
    lat       REAL    NOT NULL,
    lon       REAL    NOT NULL,
    accuracy  REAL    NOT NULL DEFAULT 0,
    speed     REAL,
    battery   INTEGER,
    created_at TEXT   NOT NULL
  )''';

const _trackIndexDDL = 'CREATE INDEX idx_track_at ON track_points(at)';

/// A place somebody has NAMED — home, the office, a parent's house.
///
/// Named by the person, never looked up. A reverse-geocode would send the
/// coordinates of your house to a stranger's server to be told what it is
/// already obvious you know, which is the whole thing this module is trying not
/// to do. A stay within `radius` of one of these takes its name, so naming
/// "Home" once names every evening you have ever spent there and every one you
/// will.
const _trackPlacesDDL = '''
  CREATE TABLE track_places (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    server_id INTEGER,
    name      TEXT    NOT NULL,
    lat       REAL    NOT NULL,
    lon       REAL    NOT NULL,
    radius    REAL    NOT NULL DEFAULT 150,
    created_at TEXT   NOT NULL
  )''';

/// A file's sha256, remembered so it is computed once and not once per run.
///
/// THE COST THIS REMOVES IS THE REAL ONE. Asking the computer "do you already
/// have this?" needs the file's hash, and computing it reads every byte. For a
/// photo that then uploads, that read was going to happen anyway. For anything
/// that FAILS to upload -- a video too big for a home upstream, say -- it
/// happens again on the next run, and the next, for ever: the file is never in
/// the sent list, so it is re-hashed every time and never gets any closer.
/// Twenty-two failed videos is several gigabytes read off the phone per run,
/// before a single byte is uploaded. That is what "the backup keeps running a
/// long time" was.
///
/// SEPARATE from backup_ledger on purpose. That table means "this is on the
/// computer"; this one means "this is what the file hashes to". Putting an
/// unsent asset in the ledger to hold its hash would make the cheap skip
/// believe it was backed up, and it would never be sent at all.
///
/// `modified` and `signature` are carried so an edited file is re-hashed rather
/// than answered from a stale digest.
const _hashesDDL = '''
  CREATE TABLE asset_hashes (
    asset_id  TEXT PRIMARY KEY,
    modified  INTEGER NOT NULL DEFAULT 0,
    signature INTEGER NOT NULL DEFAULT 0,
    hash      TEXT NOT NULL
  )''';

/// One upload waiting on this phone.
@immutable
class PendingFile {
  const PendingFile({
    required this.id,
    required this.module,
    required this.clientUuid,
    required this.paths,
    required this.fields,
    required this.state,
    required this.tries,
    required this.lastError,
    required this.createdAt,
  });

  final int id;
  final String module;
  final String clientUuid;

  /// Every page, in order. A scan is one document however many pages it has.
  final List<String> paths;
  final Map<String, dynamic> fields;
  final OpState state;
  final int tries;
  final String? lastError;
  final DateTime createdAt;

  String get title => '${fields['title'] ?? 'Untitled'}';
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
      version: 10,
      // v2 added `pending.action`. An upgrade rather than a recreate, because
      // by the time this shipped there were phones holding queued work in a v1
      // database — and that queue is the only copy of it anywhere.
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          await db.execute('ALTER TABLE pending ADD COLUMN action TEXT');
        }
        if (from < 3) {
          await db.execute(_pendingFilesDDL);
        }
        if (from < 4) {
          await db.execute(_ledgerDDL);
          await db.execute(_ledgerIndexDDL);
        }
        if (from < 5) {
          // v4 stored a pixel count in a column called `size`, which was both
          // misleading and weaker than it needed to be. Rebuilt rather than
          // renamed: the values themselves change meaning, so keeping them
          // would silently compare a new signature against an old pixel count
          // and re-offer every photo anyway. Dropping is the honest version of
          // the same outcome, and costs one re-check.
          await db.execute('DROP TABLE IF EXISTS backup_ledger');
          await db.execute(_ledgerDDL);
          await db.execute(_ledgerIndexDDL);
        }
        if (from < 6) {
          await db.execute(_hashesDDL);
        }
        if (from < 7) {
          await db.execute(_ignoredDDL);
        }
        if (from < 8) {
          await db.execute(_memoriesDDL);
          await db.execute(_memoriesIndexDDL);
          await db.execute(_factsDDL);
          await db.execute(_factsIndexDDL);
          await db.execute(_factsAtIndexDDL);
        }
        if (from < 9) {
          // GUARDED, not a plain ALTER, and this is the exact shape that once
          // shipped an app which would not start. An upgrade from v7 runs the
          // block above, which creates `memories` from the CURRENT definition —
          // client_uuid included — and then this block would add it a second
          // time and throw "duplicate column name" inside onUpgrade, failing
          // the open. Any column added to a table an earlier migration may have
          // created whole has to go on this way.
          await _addColumnIfMissing(db, 'memories', 'client_uuid', 'TEXT');
        }
        if (from < 10) {
          await db.execute(_trackDDL);
          await db.execute(_trackIndexDDL);
          await db.execute(_trackPlacesDDL);
        }
      },
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
            action          TEXT,
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
        await db.execute(_pendingFilesDDL);
        await db.execute(_ledgerDDL);
        await db.execute(_ledgerIndexDDL);
        await db.execute(_hashesDDL);
        await db.execute(_ignoredDDL);
        await db.execute(_memoriesDDL);
        await db.execute(_memoriesIndexDDL);
        await db.execute(_factsDDL);
        await db.execute(_factsIndexDDL);
        await db.execute(_factsAtIndexDDL);
        await db.execute(_trackDDL);
        await db.execute(_trackIndexDDL);
        await db.execute(_trackPlacesDDL);
        await db.execute('''
          CREATE TABLE local_ids (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            module TEXT NOT NULL
          )''');
      },
    );
  }

  /// Add a column only if the table does not already have it.
  ///
  /// See the v9 note above for why this exists rather than a bare ALTER.
  static Future<void> _addColumnIfMissing(
      Database db, String table, String column, String type) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final have = {for (final c in cols) '${c['name']}'};
    if (have.contains(column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
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
        case Op.action:
          // An action's EFFECT is the server's to work out — only it knows what
          // ticking a habit does to the streak. What the phone can do is carry
          // the optimistic fields the screen supplied, so the tick appears
          // immediately instead of after a sync, and mark the row pending.
          // Anything not supplied simply stays as the server last said.
          if (o.serverId != null && byId.containsKey(o.serverId)) {
            byId[o.serverId!] = {...byId[o.serverId!]!, ...o.payload};
          } else if (o.localId != null && localOnly.containsKey(o.localId)) {
            localOnly[o.localId!] = {...localOnly[o.localId!]!, ...o.payload};
          }
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
    String? action,
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
      'action': action,
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
          action: r['action'] as String?,
          state: OpState.values.firstWhere((s) => s.name == '${r['state']}',
              orElse: () => OpState.pending),
          tries: (r['tries'] as int?) ?? 0,
          lastError: r['last_error'] as String?,
          createdAt:
              DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
        )
    ];
  }

  // --------------------------------------------------- what is backed up

  /// Which of these assets are already backed up, unchanged.
  ///
  /// One query for the whole page rather than one per asset: the caller is
  /// asking about two hundred at a time and a round trip each would put the
  /// cost back where this table exists to remove it.
  Future<Set<String>> alreadyBackedUp(
      List<({String id, int modified, int signature})> assets) async {
    if (assets.isEmpty) return const {};
    final db = await _open;
    final ids = assets.map((a) => a.id).toList();
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
        'SELECT asset_id, modified, signature FROM backup_ledger '
        'WHERE asset_id IN ($marks)', ids);

    final held = {
      for (final r in rows)
        '${r['asset_id']}': (
          modified: (r['modified'] as int?) ?? 0,
          signature: (r['signature'] as int?) ?? 0,
        )
    };

    return {
      for (final a in assets)
        if (held.containsKey(a.id) &&
            // A row written before this carried modified/size has zeroes; treat
            // it as a match so an existing installation is not made to re-hash
            // its whole library the first time it runs this version.
            (held[a.id]!.modified == 0 ||
                (held[a.id]!.modified == a.modified &&
                    held[a.id]!.signature == a.signature)))
          a.id
    };
  }

  /// Record a page of assets as backed up, in one transaction.
  Future<void> markBackedUp(
      List<({String id, int modified, int signature})> assets) async {
    if (assets.isEmpty) return;
    final db = await _open;
    final now = DateTime.now().toIso8601String();
    await db.transaction((tx) async {
      final batch = tx.batch();
      for (final a in assets) {
        batch.insert(
          'backup_ledger',
          {'asset_id': a.id, 'modified': a.modified,
           'signature': a.signature, 'sent_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<int> backedUpCount() async {
    final db = await _open;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM backup_ledger');
    return (r.first['c'] as int?) ?? 0;
  }

  // ------------------------------------------------------- life memory

  /// Write down something that was said. Returns the new local id.
  ///
  /// Facts are written in the same transaction as the words. A memory whose
  /// warranty was confirmed and then lost to a crash between two writes is
  /// worse than one with no facts at all: the person saw it accepted.
  Future<int> addMemory({
    required String body,
    required DateTime saidAt,
    bool spoken = false,
    String? photoId,
    String? photoPath,
    List<({String kind, String value, DateTime? at})> facts = const [],
  }) async {
    final db = await _open;
    final now = DateTime.now().toIso8601String();
    return db.transaction((tx) async {
      final id = await tx.insert('memories', {
        // MINTED HERE, on the phone, and never again. The server remembers the
        // uuids it has honoured, so a push whose reply never arrived can be
        // retried without making a second copy — and with this module that
        // matters more than anywhere else, because the phone's row is the
        // original and a duplicate on the computer cannot be told from a second
        // thing somebody said.
        'client_uuid': _uuid.v4(),
        'said_at': saidAt.toIso8601String(),
        'body': body,
        'spoken': spoken ? 1 : 0,
        'photo_id': photoId,
        'photo_path': photoPath,
        'created_at': now,
        'updated_at': now,
      });
      for (final f in facts) {
        await tx.insert('memory_facts', {
          'memory_id': id,
          'kind': f.kind,
          'value': f.value,
          'at': f.at?.toIso8601String(),
        });
      }
      return id;
    });
  }

  /// The thread: newest first, with each memory's confirmed facts attached.
  ///
  /// Two queries rather than a join, and then stitched. A join returns one row
  /// per fact, so a memory with four facts arrives four times and has to be
  /// folded back together anyway — and the folding is where a photo path gets
  /// dropped. Two plain queries are easier to be right about.
  Future<List<Map<String, dynamic>>> memories({int limit = 200, int offset = 0}) async {
    final db = await _open;
    final rows = await db.query('memories',
        orderBy: 'said_at DESC, id DESC', limit: limit, offset: offset);
    return _withFacts(db, rows);
  }

  /// Everything matching [term], in the WORDS as well as the facts.
  ///
  /// The words matter most: somebody looking for "the blue suitcase" is
  /// remembering how they said it, not what anybody labelled it. Facts are
  /// searched too so that "Jayanagar" finds a memory that only mentions the
  /// place in a confirmed tag.
  Future<List<Map<String, dynamic>>> searchMemories(String term,
      {int limit = 100}) async {
    final q = term.trim();
    if (q.isEmpty) return const [];
    final db = await _open;
    final like = '%${q.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final rows = await db.rawQuery(
        'SELECT m.* FROM memories m '
        'WHERE m.body LIKE ? ESCAPE ? '
        'OR m.id IN (SELECT memory_id FROM memory_facts WHERE value LIKE ? ESCAPE ?) '
        'ORDER BY m.said_at DESC LIMIT ?',
        [like, r'\', like, r'\', limit]);
    return _withFacts(db, rows);
  }

  /// Confirmed facts that point at a moment still to come — what the reminders
  /// are built from. Ordered soonest first, which is the order they matter in.
  Future<List<Map<String, dynamic>>> memoryDates({DateTime? from}) async {
    final db = await _open;
    final since = (from ?? DateTime.now()).toIso8601String();
    return db.rawQuery(
        'SELECT f.*, m.body, m.photo_path FROM memory_facts f '
        'JOIN memories m ON m.id = f.memory_id '
        'WHERE f.at IS NOT NULL AND f.at >= ? '
        'ORDER BY f.at ASC',
        [since]);
  }

  /// Candidates for a question: anything mentioning ANY of [terms].
  ///
  /// OR, not AND, and that is the whole reason this is separate from
  /// [searchMemories]. Search is a person looking for one thing and an
  /// unmatched word should narrow it; a QUESTION is scored afterwards by
  /// `ask.dart`, which needs to see the near misses in order to rank them and
  /// to say "the closest I can find". Requiring every word here would hand the
  /// scorer only the rows it would have picked anyway, and the honest
  /// "I cannot answer that, but this mentions it" answer would never appear.
  ///
  /// Matching is on a five-character prefix of each term so "machine" finds
  /// "machines" — the same stem `ask.askTerms` scores with, because the two
  /// disagreeing is how a search quietly starts missing things.
  Future<List<Map<String, dynamic>>> memoriesMatchingAny(List<String> terms,
      {int limit = 200}) async {
    final db = await _open;
    final stems = <String>{
      for (final t in terms)
        if (t.trim().isNotEmpty)
          (t.length <= 5 ? t : t.substring(0, 5))
              .toLowerCase()
              .replaceAll('%', r'\%')
              .replaceAll('_', r'\_')
    }.toList();

    // No usable words — "how much have I spent in all" — so the candidates are
    // simply everything recent, and the scorer decides. Bounded, because a
    // question must not read a lifetime off the disk to answer.
    if (stems.isEmpty) {
      final rows = await db.query('memories',
          orderBy: 'said_at DESC, id DESC', limit: limit);
      return _withFacts(db, rows);
    }

    final args = <Object?>[];
    final clauses = <String>[];
    for (final stem in stems) {
      clauses.add('m.body LIKE ? ESCAPE ?');
      args.addAll(['%$stem%', r'\']);
      clauses.add(
          'm.id IN (SELECT memory_id FROM memory_facts WHERE value LIKE ? ESCAPE ?)');
      args.addAll(['%$stem%', r'\']);
    }
    args.add(limit);
    final rows = await db.rawQuery(
        'SELECT m.* FROM memories m WHERE ${clauses.join(' OR ')} '
        'ORDER BY m.said_at DESC LIMIT ?',
        args);
    return _withFacts(db, rows);
  }

  /// Memories the computer does not have yet, oldest first.
  ///
  /// Oldest first on purpose: a thread that syncs newest-first fills the
  /// computer's copy backwards, and a half-finished sync then looks like a
  /// person who said nothing for a year and then four things at once.
  Future<List<Map<String, dynamic>>> unsyncedMemories({int limit = 50}) async {
    final db = await _open;
    final rows = await db.query('memories',
        where: 'server_id IS NULL',
        orderBy: 'said_at ASC, id ASC',
        limit: limit);
    return _withFacts(db, rows);
  }

  /// The computer has it. This is the ONLY thing syncing changes about a
  /// memory — the words, the facts and the photograph were already true the
  /// moment they were said, which is why nothing else here is touched.
  Future<void> markMemorySynced(int localId, int serverId) async {
    final db = await _open;
    await db.update(
        'memories',
        {'server_id': serverId, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [localId]);
  }

  Future<int> unsyncedMemoryCount() async {
    final db = await _open;
    final r = await db.rawQuery(
        'SELECT COUNT(*) c FROM memories WHERE server_id IS NULL');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<int> memoryCount() async {
    final db = await _open;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM memories');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> deleteMemory(int id) async {
    final db = await _open;
    await db.transaction((tx) async {
      await tx.delete('memory_facts', where: 'memory_id = ?', whereArgs: [id]);
      await tx.delete('memories', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Replace the confirmed facts of one memory. Used when somebody edits the
  /// chips afterwards — the words are untouched, which is the point.
  Future<void> setMemoryFacts(
      int memoryId, List<({String kind, String value, DateTime? at})> facts) async {
    final db = await _open;
    await db.transaction((tx) async {
      await tx.delete('memory_facts',
          where: 'memory_id = ?', whereArgs: [memoryId]);
      for (final f in facts) {
        await tx.insert('memory_facts', {
          'memory_id': memoryId,
          'kind': f.kind,
          'value': f.value,
          'at': f.at?.toIso8601String(),
        });
      }
      await tx.update('memories', {'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [memoryId]);
    });
  }

  /// Attach each memory's facts, in one further query rather than one per row.
  Future<List<Map<String, dynamic>>> _withFacts(
      dynamic db, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return const [];
    final ids = [for (final r in rows) r['id'] as int];
    final marks = List.filled(ids.length, '?').join(',');
    final facts = await db.rawQuery(
        'SELECT * FROM memory_facts WHERE memory_id IN ($marks)', ids);
    final byMemory = <int, List<Map<String, Object?>>>{};
    for (final f in facts) {
      (byMemory[f['memory_id'] as int] ??= []).add(f);
    }
    return [
      for (final r in rows)
        {...r, 'facts': byMemory[r['id'] as int] ?? const []}
    ];
  }

  // ------------------------------------------------------------ track me

  /// Write down one fix.
  ///
  /// THINNED AT THE DOOR, not later. A phone that has not moved still reports a
  /// position every couple of minutes, and a year of that is a quarter of a
  /// million rows saying the same thing. A fix within [sameSpot] metres of the
  /// last one AND less than [restingGap] after it is dropped — the stay it
  /// belongs to is already established by the fixes around it, and nothing in
  /// `track/day.dart` reads any better for the extra hundred.
  ///
  /// Returns the new row id, or null when the fix was thinned away.
  Future<int?> addFix({
    required DateTime at,
    required double lat,
    required double lon,
    double accuracy = 0,
    double? speed,
    int? battery,
    double sameSpot = 60,
    Duration restingGap = const Duration(minutes: 8),
  }) async {
    final db = await _open;
    final last = await db.query('track_points',
        orderBy: 'at DESC', limit: 1);
    if (last.isNotEmpty) {
      final prevAt = DateTime.tryParse('${last.first['at']}');
      final prevLat = (last.first['lat'] as num).toDouble();
      final prevLon = (last.first['lon'] as num).toDouble();
      if (prevAt != null) {
        final moved = _metres(prevLat, prevLon, lat, lon);
        final since = at.difference(prevAt);
        if (moved < sameSpot && since < restingGap && !since.isNegative) {
          return null;
        }
      }
    }
    return db.insert('track_points', {
      // UTC. The day boundary is applied on read, against the LOCAL calendar —
      // storing a local timestamp instead makes a day abroad unreadable.
      'at': at.toUtc().toIso8601String(),
      'lat': lat,
      'lon': lon,
      'accuracy': accuracy,
      'speed': speed,
      'battery': battery,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Every fix for one LOCAL calendar day.
  ///
  /// The bounds are built from the local day and converted, so "the 3rd" means
  /// the 3rd where the person was, not the 3rd in UTC — which in India is the
  /// 2nd from half past five in the morning.
  Future<List<Map<String, dynamic>>> fixesOn(DateTime day) async {
    final db = await _open;
    final from = DateTime(day.year, day.month, day.day).toUtc();
    final to = DateTime(day.year, day.month, day.day + 1).toUtc();
    return db.query('track_points',
        where: 'at >= ? AND at < ?',
        whereArgs: [from.toIso8601String(), to.toIso8601String()],
        orderBy: 'at ASC');
  }

  /// Which local days have anything recorded, newest first.
  ///
  /// Grouped in Dart rather than SQL: the stored timestamps are UTC, and
  /// `substr(at, 1, 10)` would put an evening in India on the wrong day.
  Future<List<DateTime>> trackedDays({int limit = 400}) async {
    final db = await _open;
    final rows = await db.query('track_points',
        columns: ['at'], orderBy: 'at DESC', limit: 50000);
    final days = <String, DateTime>{};
    for (final r in rows) {
      final at = DateTime.tryParse('${r['at']}');
      if (at == null) continue;
      final local = at.toLocal();
      final key = '${local.year}-${local.month}-${local.day}';
      days.putIfAbsent(key, () => DateTime(local.year, local.month, local.day));
      if (days.length >= limit) break;
    }
    return days.values.toList();
  }

  Future<int> fixCount() async {
    final db = await _open;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM track_points');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Everything, gone. The screen offers this because a location history is the
  /// one thing in this app somebody may want rid of in a hurry, and "delete the
  /// app" should not be the only way.
  Future<void> clearTrack() async {
    final db = await _open;
    await db.delete('track_points');
  }

  /// Forget one day.
  Future<int> clearTrackDay(DateTime day) async {
    final db = await _open;
    final from = DateTime(day.year, day.month, day.day).toUtc();
    final to = DateTime(day.year, day.month, day.day + 1).toUtc();
    return db.delete('track_points',
        where: 'at >= ? AND at < ?',
        whereArgs: [from.toIso8601String(), to.toIso8601String()]);
  }

  /// Fixes the computer does not have yet, oldest first.
  Future<List<Map<String, dynamic>>> unsyncedFixes({int limit = 500}) async {
    final db = await _open;
    return db.query('track_points',
        where: 'server_id IS NULL', orderBy: 'at ASC, id ASC', limit: limit);
  }

  Future<int> unsyncedFixCount() async {
    final db = await _open;
    final r = await db.rawQuery(
        'SELECT COUNT(*) c FROM track_points WHERE server_id IS NULL');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Mark a batch as sent, in one statement rather than one per row — a day is
  /// several hundred fixes and a round of updates each is how a sync takes a
  /// minute instead of a second.
  Future<void> markFixesSynced(Map<int, int> localToServer) async {
    if (localToServer.isEmpty) return;
    final db = await _open;
    await db.transaction((tx) async {
      for (final e in localToServer.entries) {
        await tx.update('track_points', {'server_id': e.value},
            where: 'id = ?', whereArgs: [e.key]);
      }
    });
  }

  // --------------------------------------------------- places you have named

  Future<int> nameTrackPlace({
    required String name,
    required double lat,
    required double lon,
    double radius = 150,
  }) async {
    final db = await _open;
    return db.insert('track_places', {
      'name': name,
      'lat': lat,
      'lon': lon,
      'radius': radius,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> trackPlaces() async {
    final db = await _open;
    return db.query('track_places', orderBy: 'name ASC');
  }

  Future<void> forgetTrackPlace(int id) async {
    final db = await _open;
    await db.delete('track_places', where: 'id = ?', whereArgs: [id]);
  }

  /// Haversine, in metres. A copy of `track/day.dart`'s, because this file must
  /// not import a screen-layer library — and the thinning above needs it before
  /// anything has been read.
  static double _metres(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double d) => d * 3.1415926535897932 / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // ------------------------------------------------- what to stop trying

  /// Everything the person has told the backup to leave alone.
  ///
  /// Read whole rather than queried per page: a run asks once and then checks
  /// a set in memory, and this list is the handful of files somebody has
  /// actually given up on, not the twenty thousand in the ledger.
  Future<Set<String>> ignoredForBackup() async {
    final db = await _open;
    final rows = await db.query('backup_ignored', columns: ['asset_id']);
    return {for (final r in rows) '${r['asset_id']}'};
  }

  /// With the reason it was stuck on, newest first — what the list shows.
  Future<List<({String id, String reason})>> ignoredWithReasons() async {
    final db = await _open;
    final rows = await db.query('backup_ignored', orderBy: 'at DESC');
    return [
      for (final r in rows)
        (id: '${r['asset_id']}', reason: '${r['reason'] ?? ''}')
    ];
  }

  Future<void> ignoreForBackup(String assetId, {String reason = ''}) async {
    final db = await _open;
    await db.insert(
      'backup_ignored',
      {
        'asset_id': assetId,
        'reason': reason,
        'at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Start trying again. The asset is NOT put in the ledger — it was never
  /// sent — so the next run picks it up exactly as it would have before.
  Future<void> unignoreForBackup(String assetId) async {
    final db = await _open;
    await db.delete('backup_ignored',
        where: 'asset_id = ?', whereArgs: [assetId]);
  }

  Future<int> ignoredCount() async {
    final db = await _open;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM backup_ignored');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> clearIgnored() async {
    final db = await _open;
    await db.delete('backup_ignored');
  }

  /// Forget everything backed up, so the next run offers the whole library.
  ///
  /// Deliberately leaves the skipped list alone. "Back up everything again" is
  /// about what the computer has, not about reopening decisions the person
  /// made one at a time — and a file skipped because it will never upload
  /// would simply fail again, which is the state they were getting out of.
  Future<void> clearBackedUp() async {
    final db = await _open;
    await db.delete('backup_ledger');
    await db.delete('asset_hashes');
  }

  /// Carry an older installation's list of ids across.
  ///
  /// Those came from SharedPreferences and know only the id — no modified time,
  /// no size. They are stored with zeroes, which `alreadyBackedUp` treats as
  /// "matches", so upgrading does not make somebody re-hash their whole library
  /// to learn what the phone already knew.
  Future<void> importBackedUpIds(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await markBackedUp([
      for (final id in list) (id: id, modified: 0, signature: 0)
    ]);
  }

  /// Hashes already computed for these assets, where the file has not changed.
  Future<Map<String, String>> knownHashes(
      List<({String id, int modified, int signature})> assets) async {
    if (assets.isEmpty) return const {};
    final db = await _open;
    final ids = assets.map((a) => a.id).toList();
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
        'SELECT asset_id, modified, signature, hash FROM asset_hashes '
        'WHERE asset_id IN ($marks)', ids);
    final held = {for (final r in rows) '${r['asset_id']}': r};
    final out = <String, String>{};
    for (final a in assets) {
      final r = held[a.id];
      if (r == null) continue;
      // An edited file must be re-hashed. A stale digest would have the
      // computer answer about a photo that no longer exists.
      if ((r['modified'] as int?) == a.modified &&
          (r['signature'] as int?) == a.signature) {
        out[a.id] = '${r['hash']}';
      }
    }
    return out;
  }

  /// Remember what a file hashed to, so it is never hashed twice.
  Future<void> rememberHashes(
      List<({String id, int modified, int signature, String hash})> rows) async {
    if (rows.isEmpty) return;
    final db = await _open;
    await db.transaction((tx) async {
      final batch = tx.batch();
      for (final r in rows) {
        batch.insert(
          'asset_hashes',
          {'asset_id': r.id, 'modified': r.modified,
           'signature': r.signature, 'hash': r.hash},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  // ------------------------------------------------------- files waiting

  /// Queue an upload whose payload is files on disk — a scan, typically.
  ///
  /// The bytes are NOT copied into the database. They are already somewhere the
  /// app can read; what is stored is where, and what they were for.
  Future<String> enqueueFiles({
    required String module,
    required List<String> paths,
    Map<String, dynamic> fields = const {},
  }) async {
    final db = await _open;
    final uuid = _uuid.v4();
    await db.insert('pending_files', {
      'module': module,
      'client_uuid': uuid,
      'paths': paths.join('\n'),
      'fields': jsonEncode(fields),
      'state': OpState.pending.name,
      'tries': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    return uuid;
  }

  /// The stored fields, or an empty map if the row cannot be read.
  ///
  /// A queued scan whose metadata will not decode is still a scan worth
  /// uploading — the pages are the point, and a missing title is recoverable
  /// where a discarded document is not.
  static Map<String, dynamic> _decodeFields(Object? raw) {
    try {
      return Map<String, dynamic>.from(jsonDecode('$raw') as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<List<PendingFile>> pendingFiles() async {
    final db = await _open;
    final rows = await db.query('pending_files', orderBy: 'id ASC');
    return [
      for (final r in rows)
        PendingFile(
          id: r['id'] as int,
          module: '${r['module']}',
          clientUuid: '${r['client_uuid']}',
          paths: '${r['paths']}'.split('\n').where((x) => x.isNotEmpty).toList(),
          fields: _decodeFields(r['fields']),
          state: OpState.values.firstWhere((s) => s.name == '${r['state']}',
              orElse: () => OpState.pending),
          tries: (r['tries'] as int?) ?? 0,
          lastError: r['last_error'] as String?,
          createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
        )
    ];
  }

  Future<int> pendingFileCount() async {
    final db = await _open;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM pending_files');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Forget one upload because the computer confirmed THAT one.
  ///
  /// Deletes the queue row; the caller removes the files, because only it knows
  /// whether they were copies this app made or originals somebody else owns.
  Future<void> fileConfirmed(int id) async {
    final db = await _open;
    await db.delete('pending_files', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> fileFailed(int id, String reason) async {
    final db = await _open;
    await db.rawUpdate(
        'UPDATE pending_files SET state = ?, tries = tries + 1, '
        'last_error = ? WHERE id = ?',
        [OpState.failed.name, reason, id]);
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

  /// Put an operation back exactly as it was — same uuid, same payload.
  ///
  /// Only a test needs this, and only to reproduce the single case the whole
  /// uuid scheme exists for: the server committed the record and the reply
  /// never arrived, so the phone still believes the work is outstanding and
  /// sends it again. Nothing in the app re-queues a confirmed operation.
  @visibleForTesting
  Future<void> requeue(PendingOp op) async {
    final db = await _open;
    await db.insert('pending', {
      'module': op.module,
      'op': opName(op.op),
      'client_uuid': op.clientUuid,
      'local_id': op.localId,
      'server_id': op.serverId,
      'body': await _seal(op.payload),
      'base_updated_at': op.baseUpdatedAt,
      'action': op.action,
      'state': OpState.pending.name,
      'tries': op.tries,
      'created_at': op.createdAt.toIso8601String(),
    });
  }

  @visibleForTesting
  Future<void> clearEverything() async {
    final db = await _open;
    await db.delete('cache');
    await db.delete('pending');
    await db.delete('pending_files');
    await db.delete('backup_ledger');
    await db.delete('asset_hashes');
    await db.delete('local_ids');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
