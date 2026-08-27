/// Pushing what was done offline back to the computer.
///
/// Driven by a button, never by itself. Everything else in this product refuses
/// to act behind the owner's back — the desktop updater will not download
/// unasked, reminders are scheduled locally rather than routed through anyone's
/// servers — and a sync that fired on its own would be the odd one out. What it
/// may do is *offer*: when the computer is reachable and something is waiting,
/// say so loudly and wait to be told.
///
/// WHAT THIS WILL NOT DO
///
///   * It will not sync into a server that cannot remember what it has already
///     accepted. `/api/sync/capabilities` answering 404 means an installation
///     from before this existed, and replaying into it would create a second
///     copy of every record on the first dropped reply. It stops and says which
///     computer needs updating. This is the album_id lesson written down: an
///     unknown parameter is dropped in silence, so a phone built for a newer
///     server does not fail against an older one — it succeeds incorrectly.
///   * It will not drop an operation because a batch finished. Each one is
///     forgotten only when the server names it, because until then it is the
///     only copy in the world.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api.dart';
import 'records.dart';
import 'store.dart';

/// How one operation ended, in the words the owner needs.
enum SyncOutcome {
  /// Saved on the computer.
  saved,

  /// The computer had already accepted it — a reply that went missing, not a
  /// mistake. Nothing to tell anybody about.
  already,

  /// Somebody changed the same record on the computer. Kept, not applied.
  conflict,

  /// Refused for a reason that will not change by trying again — no permission,
  /// a record that is gone, a value the computer will not accept.
  refused,

  /// Could not be delivered. Worth another go.
  failed,
}

@immutable
class SyncResult {
  const SyncResult({
    required this.sent,
    required this.saved,
    required this.already,
    required this.conflicts,
    required this.refused,
    required this.failed,
    required this.problems,
    this.blockedReason,
  });

  const SyncResult.blocked(String why)
      : sent = 0,
        saved = 0,
        already = 0,
        conflicts = 0,
        refused = 0,
        failed = 0,
        problems = const [],
        blockedReason = why;

  final int sent, saved, already, conflicts, refused, failed;

  /// Distinct reasons, so a report can say what went wrong rather than "5
  /// failed". Same reason `backup.dart` keeps its `_problems` map: a count
  /// tells nobody what to do next.
  final List<String> problems;

  /// Set when nothing was attempted at all, and why.
  final String? blockedReason;

  bool get blocked => blockedReason != null;

  /// Everything the owner still has to deal with.
  int get outstanding => conflicts + refused + failed;
}

/// Runs the sync and reports progress while it does.
class SyncService extends ChangeNotifier {
  /// `api` is a FUNCTION, not an Api. Session mints a fresh one per call with
  /// the current address and token, and holding one from construction time
  /// would keep talking to the server the phone was signed into an hour ago.
  // The lint wants `this._store` here. Dart forbids a named parameter whose
  // name starts with an underscore, so its suggestion does not compile.
  // ignore_for_file: prefer_initializing_formals
  SyncService({
    required OfflineStore store,
    required Api Function() api,
    OfflineRecords? records,
  })  : _store = store,
        _api = api,
        _records = records;

  final OfflineStore _store;
  final Api Function() _api;

  /// Optional, so the engine can be tested without one. When present, a sync
  /// also brings the computer's records DOWN — see the pull below.
  final OfflineRecords? _records;

  bool _running = false;
  int _done = 0;
  int _total = 0;
  String _step = '';
  int _pending = 0;
  SyncResult? _last;

  bool get running => _running;
  int get done => _done;
  int get total => _total;
  String get step => _step;

  /// How many operations are waiting. Shown as a badge, because unsynced work
  /// exists on this phone and nowhere else and must not be easy to forget.
  int get pending => _pending;
  SyncResult? get lastResult => _last;

  /// 0..1, and never NaN — a progress bar fed 0/0 renders as a full one.
  double get progress => _total == 0 ? 0 : (_done / _total).clamp(0.0, 1.0);

  /// Re-read how much is waiting.
  ///
  /// NEVER THROWS. This runs during startup, and a store that cannot be opened
  /// must not be the reason the app fails to launch — the owner would have no
  /// way in at all, including no way to reach the very screen that might
  /// explain it. The count is left at whatever was last known and the cause is
  /// logged.
  ///
  /// The cost of that choice, stated: an unreadable store shows "nothing
  /// waiting" when something may well be. It is the lesser of the two, because
  /// the alternative is an app that will not start.
  Future<void> refreshPending() async {
    try {
      _pending = await _store.pendingCount();
    } catch (e) {
      debugPrint('[sync] could not read the queue: $e');
    }
    notifyListeners();
  }

  /// Whether this server understands offline sync at all.
  ///
  /// Returns null when it does; a sentence to show the owner when it does not.
  Future<String?> whyNotSyncable() async {
    try {
      final r = await _api().get('/api/sync/capabilities');
      final proto = (r is Map ? r['protocol'] : null) as int?;
      if (proto == null) {
        return 'This computer\'s SafeNest is too old to sync offline changes.';
      }
      return null;
    } on ApiError catch (e) {
      if (e.status == 404) {
        return 'This computer\'s SafeNest is too old to sync offline changes — '
            'update it, then try again. Nothing has been lost; your changes are '
            'still on this phone.';
      }
      // Anything else is "cannot reach it", which is not the same thing and
      // must not be reported as an out-of-date computer.
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Push everything waiting. Returns what happened, per outcome.
  Future<SyncResult> run() async {
    if (_running) {
      return const SyncResult.blocked('A sync is already running');
    }
    _running = true;
    _done = 0;
    _step = 'Checking the computer';
    notifyListeners();

    try {
      final why = await whyNotSyncable();
      if (why != null) {
        _last = SyncResult.blocked(why);
        return _last!;
      }

      var ops = await _store.allPending();
      _total = ops.length;
      notifyListeners();
      if (ops.isEmpty) {
        // Nothing to send is NOT nothing to do. Pressing Sync with an empty
        // outbox should still bring the computer's records down — that is what
        // somebody about to go out is asking for.
        final problems = <String>[];
        if (_records != null) {
          _step = 'Getting your records';
          notifyListeners();
          final couldNot = await _records.refreshAll(_api(), onEach: (label) {
            _step = 'Getting $label';
            notifyListeners();
          });
          for (final m in couldNot) {
            problems.add('Could not refresh $m');
          }
        }
        _last = SyncResult(
            sent: 0, saved: 0, already: 0, conflicts: 0, refused: 0,
            failed: 0, problems: problems);
        return _last!;
      }

      var saved = 0, already = 0, conflicts = 0, refused = 0, failed = 0;
      final problems = <String>{};

      // In order, and in modest batches. The order is the whole correctness
      // argument — a create must reach the server before the edit that followed
      // it — so this walks the journal rather than grouping by module, which
      // would be faster and wrong.
      const chunk = 25;
      for (var i = 0; i < ops.length; i += chunk) {
        final slice = ops.sublist(i, (i + chunk).clamp(0, ops.length));
        _step = 'Sending ${i + 1} of ${ops.length}';
        notifyListeners();

        List<dynamic> results;
        try {
          final r = await _api().post('/api/sync/replay', {
            'ops': [for (final o in slice) _wire(o)],
          });
          results = (r is Map ? r['results'] as List? : null) ?? const [];
        } catch (e) {
          // The whole slice failed to be delivered. Every one of them stays
          // queued: not delivered is not the same as not accepted.
          for (final o in slice) {
            await _store.failed(o.seq, _reason(e));
            failed++;
            _done++;
          }
          problems.add(_reason(e));
          notifyListeners();
          continue;
        }

        final byUuid = {
          for (final r in results)
            if (r is Map && r['client_uuid'] != null) '${r['client_uuid']}': r
        };

        for (final o in slice) {
          final r = byUuid[o.clientUuid];
          _done++;
          if (r == null) {
            // The server did not mention it. It may or may not have landed, so
            // it stays — a duplicate is prevented by the uuid, and a lost
            // record is not recoverable at all.
            await _store.failed(o.seq, 'The computer did not answer for this');
            failed++;
            continue;
          }
          switch ('${r['status']}') {
            case 'ok':
              // A create that produced a row: every later operation on the same
              // record has to be pointed at it before anything else is sent.
              final sid = (r['server_id'] as num?)?.toInt();
              if (o.op == Op.create && o.localId != null && sid != null) {
                await _store.resolveLocalId(o.module, o.localId!, sid);
              }
              await _store.confirmed(o.seq);
              saved++;
            case 'already':
              final sid = (r['server_id'] as num?)?.toInt();
              if (o.op == Op.create && o.localId != null && sid != null) {
                await _store.resolveLocalId(o.module, o.localId!, sid);
              }
              await _store.confirmed(o.seq);
              already++;
            case 'conflict':
              // Kept, deliberately. The owner decides; nothing is discarded on
              // their behalf.
              await _store.failed(o.seq, 'Changed on the computer as well');
              conflicts++;
              problems.add('Some records were changed on the computer too');
            case 'refused':
            case 'rejected':
            case 'gone':
              final msg = '${r['message'] ?? 'The computer would not accept it'}';
              await _store.failed(o.seq, msg);
              refused++;
              problems.add(msg);
            default:
              final msg = '${r['message'] ?? 'It could not be saved'}';
              await _store.failed(o.seq, msg);
              failed++;
              problems.add(msg);
          }
        }
        notifyListeners();
      }

      // AND NOW THE OTHER DIRECTION. Sync means "make this phone and that
      // computer agree", not "empty my outbox" — so once what was typed here
      // has gone up, everything comes back down. Without it a module never
      // opened while connected stays empty exactly when it is wanted, and
      // "works offline" quietly means "works offline for whatever you happened
      // to browse".
      //
      // After the push, deliberately: the pull replaces the cache wholesale, so
      // running it first would overwrite rows with the server's older copy and
      // then push edits on top of nothing.
      if (_records != null) {
        _step = 'Getting your records';
        notifyListeners();
        final couldNot = await _records.refreshAll(_api(), onEach: (label) {
          _step = 'Getting $label';
          notifyListeners();
        });
        for (final m in couldNot) {
          problems.add('Could not refresh $m');
        }
      }

      _last = SyncResult(
        sent: ops.length, saved: saved, already: already, conflicts: conflicts,
        refused: refused, failed: failed, problems: problems.toList(),
      );
      return _last!;
    } finally {
      _running = false;
      _step = '';
      await refreshPending();
    }
  }

  Map<String, dynamic> _wire(PendingOp o) => {
        'client_uuid': o.clientUuid,
        'module': o.module,
        'op': opName(o.op),
        if (o.action != null) 'action': o.action,
        if (o.serverId != null) 'server_id': o.serverId,
        if (o.baseUpdatedAt != null) 'base_updated_at': o.baseUpdatedAt,
        'payload': o.payload,
      };

  String _reason(Object e) =>
      e is ApiError ? e.message : 'Could not reach the computer';
}
