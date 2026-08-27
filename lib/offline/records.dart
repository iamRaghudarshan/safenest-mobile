/// Reading and writing a record module, whichever side of the connection the
/// computer happens to be on.
///
/// `ModuleListScreen` is the one screen behind Expenses, Loans, Cards,
/// Insurance, Investments, Reminders, To-dos, Notes and Habits, so this is the
/// one place any of them needs to learn about working offline.
///
/// THE RULE HERE: **never lose what the owner typed, and never pretend.** A save
/// that cannot reach the computer is queued and says so; it is not reported as
/// saved and it is not thrown away. A list that cannot be fetched falls back to
/// what was last seen, and the caller is told it is a cached copy so it can say
/// as much rather than presenting stale figures as current.
library;

import '../api.dart';
import 'mode.dart';
import 'store.dart';

/// What came back, and where it came from.
class Loaded {
  Loaded(this.rows, {required this.fromCache, this.asOf});

  final List<Map<String, dynamic>> rows;

  /// True when the computer could not be reached and this is what was last
  /// seen. The screen must say so — figures presented as current when they are
  /// a week old is worse than an error.
  final bool fromCache;
  final DateTime? asOf;
}

/// What happened to a save.
enum Saved {
  /// It reached the computer.
  server,

  /// It is on this phone, waiting. The owner has to be told.
  queued,
}

class OfflineRecords {
  // The lint wants `this._store`. Dart forbids a named parameter starting with
  // an underscore, so its suggestion does not compile.
  // ignore_for_file: prefer_initializing_formals
  OfflineRecords({required OfflineStore store, required OfflineMode mode})
      : _store = store,
        _mode = mode;

  final OfflineStore _store;
  final OfflineMode _mode;

  bool _syncable(String module) =>
      offlineModules.any((m) => m.key == module && m.works);

  /// Where a module's list comes from.
  ///
  /// The vault is the exception: `/api/vault` returns metadata only, by design,
  /// so caching it would give a phone a list of titles and no passwords — the
  /// offline vault would show every account and open none of them.
  /// `/api/vault/sync` is the one that carries the secrets, and it is rate
  /// limited and audited precisely because it does.
  String _listPath(String module) =>
      module == 'vault' ? '/api/vault/sync' : '/api/$module';

  /// Whether this phone should be holding the vault at all.
  ///
  /// Only when the owner has switched Working offline on. A phone that never
  /// leaves the house has no business carrying the passwords, and the bulk
  /// endpoint is rate limited hard, so calling it on every casual visit to the
  /// screen would spend the allowance and hand over the vault for nothing.
  bool _mayCache(String module) => module != 'vault' || _mode.on;

  /// Fetch a module's rows, falling back to the last copy held on this phone.
  Future<Loaded> list(Api api, String module) async {
    if (!_syncable(module)) {
      // Not an offline module at all: behave exactly as before, so nothing that
      // was working starts routing through a store that knows nothing about it.
      final d = await api.get('/api/$module');
      return Loaded(_rows(d), fromCache: false);
    }

    // In offline mode do not even reach for the network. The owner asked for
    // this; a screen that stalls for a timeout first has not honoured it.
    if (!_mode.on) {
      try {
        final d = await api.get(_listPath(module));
        final rows = _rows(d);
        if (_mayCache(module)) {
          await _store.putList(module, rows);
        }
        return Loaded(_mayCache(module) ? await _merged(module) : rows,
            fromCache: false);
      } on ApiError {
        // Fall through to whatever is held here. An unreachable computer is the
        // normal case for this product, not an error worth a red screen.
      } catch (_) {
        // Same again for anything the http layer throws that is not an ApiError.
      }
    }

    return Loaded(await _merged(module),
        fromCache: true, asOf: await _store.lastFetched(module));
  }

  /// The cache with anything pending applied on top, deleted rows removed.
  Future<List<Map<String, dynamic>>> _merged(String module) async {
    final merged = await _store.read(module);
    return [
      for (final r in merged)
        if (!r.deleted) {...r.data, '_pending': r.pending}
    ];
  }

  /// Fill the cache for every module that works offline.
  ///
  /// THE OTHER HALF OF SYNC. Pushing what the phone typed is only one
  /// direction; without this, "works offline" means "works offline for whatever
  /// you happened to open recently", and a module never visited while connected
  /// is simply empty when you need it. Somebody who turns the setting on before
  /// a journey reasonably expects their records to be there.
  ///
  /// Best effort, module by module. One that fails leaves the rest alone and
  /// keeps whatever copy it already had — a partial refresh is worth far more
  /// than an all-or-nothing one that abandons nine modules because the tenth
  /// timed out.
  ///
  /// Returns the modules it could not refresh, so the caller can say so rather
  /// than implying everything is current.
  Future<List<String>> refreshAll(Api api, {void Function(String)? onEach}) async {
    final failed = <String>[];
    for (final m in worksOffline) {
      onEach?.call(m.label);
      try {
        final d = await api.get(_listPath(m.key));
        if (_mayCache(m.key)) {
          await _store.putList(m.key, _rows(d));
        }
      } catch (_) {
        failed.add(m.label);
      }
    }
    return failed;
  }

  /// Create or edit a record.
  ///
  /// Returns where it ended up, so the screen can say "saved" or "saved on this
  /// phone" — which are different promises and must not read the same.
  Future<Saved> save(Api api, String module,
      {int? id, required Map<String, dynamic> body, String? baseUpdatedAt}) async {
    if (!_syncable(module)) {
      if (id != null) {
        await api.put('/api/$module/$id', body);
      } else {
        await api.post('/api/$module', body);
      }
      return Saved.server;
    }

    if (!_mode.on) {
      try {
        if (id != null) {
          await api.put('/api/$module/$id', body);
        } else {
          await api.post('/api/$module', body);
        }
        return Saved.server;
      } on ApiError catch (e) {
        // A REFUSAL IS NOT AN OUTAGE. The computer answered and said no — an
        // amount of zero, a field it will not accept — and queueing that would
        // hide a mistake the owner can fix now behind a sync that will fail
        // later for the same reason. Only a failure to REACH it is queued.
        if (e.status > 0) rethrow;
      } catch (_) {
        // Could not reach it. Queue below.
      }
    }

    if (id != null && id > 0) {
      await _store.enqueue(
          module: module, op: Op.update, serverId: id, payload: body,
          baseUpdatedAt: baseUpdatedAt);
    } else if (id != null && id < 0) {
      // Editing something created offline that has not been sent yet: it is the
      // same local record, so the edit rides on the same local id.
      await _store.enqueue(
          module: module, op: Op.update, localId: -id, payload: body);
    } else {
      final local = await _store.nextLocalId(module);
      await _store.enqueue(
          module: module, op: Op.create, localId: local, payload: body);
    }
    return Saved.queued;
  }

  /// Tick a habit, pin a note, toggle a to-do — the things that are not an
  /// edit of fields.
  ///
  /// [optimistic] is what the screen wants the row to look like straight away.
  /// The real effect is the server's to work out (only it knows what a tick
  /// does to a streak), but without something to show, ticking a habit offline
  /// would leave the tick invisible until a sync — which is the shape of the
  /// bug that made offline saves look broken.
  Future<Saved> act(Api api, String module, int id, String action,
      {Map<String, dynamic> body = const {},
      Map<String, dynamic> optimistic = const {}}) async {
    if (!_syncable(module)) {
      await api.post('/api/$module/$id/$action', body);
      return Saved.server;
    }

    if (!_mode.on && id > 0) {
      try {
        await api.post('/api/$module/$id/$action', body);
        return Saved.server;
      } on ApiError catch (e) {
        if (e.status > 0) rethrow;
      } catch (_) {
        // unreachable — queue it
      }
    }

    await _store.enqueue(
        module: module, op: Op.action, action: action,
        serverId: id > 0 ? id : null, localId: id < 0 ? -id : null,
        payload: {...body, ...optimistic});
    return Saved.queued;
  }

  Future<Saved> remove(Api api, String module, int id) async {
    if (!_syncable(module)) {
      await api.delete('/api/$module/$id');
      return Saved.server;
    }

    if (!_mode.on && id > 0) {
      try {
        await api.delete('/api/$module/$id');
        return Saved.server;
      } on ApiError catch (e) {
        if (e.status > 0) rethrow;
      } catch (_) {
        // unreachable — queue it
      }
    }

    await _store.enqueue(
        module: module, op: Op.delete,
        serverId: id > 0 ? id : null, localId: id < 0 ? -id : null);
    return Saved.queued;
  }

  List<Map<String, dynamic>> _rows(dynamic d) {
    final list = d is List
        ? d
        : (d is Map ? (d['items'] ?? d['rows'] ?? const []) : const []);
    return [
      for (final e in (list as List)) Map<String, dynamic>.from(e as Map)
    ];
  }
}
