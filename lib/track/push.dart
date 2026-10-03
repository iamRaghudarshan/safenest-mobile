/// Getting the fixes to the computer.
///
/// The same shape as `memory/push.dart`, and for the same reason: this module's
/// rows are created on the phone and are not edits of anything, so there is no
/// operation sequence to replay and the journal would only get in the way. The
/// unsent set is `server_id IS NULL`, derived from the data, which survives a
/// cleared journal, a restored backup and a reinstall.
///
/// WHAT IS DIFFERENT, and it is the reason this is its own file rather than a
/// second call in that one: VOLUME. A day is hundreds of fixes and a fortnight
/// abroad is thousands, so the batches are larger, the run is capped harder,
/// and marking them sent happens in one transaction rather than a round trip
/// each — a sync that takes a minute instead of a second is one people cancel.
library;

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../offline/store.dart';

@immutable
class TrackPushResult {
  const TrackPushResult({
    required this.sent,
    required this.already,
    required this.refused,
    required this.problems,
  });

  final int sent;

  /// Replays. Counted apart from [sent] because a sync reporting "600 sent"
  /// when it re-sent the same six hundred is one nobody can use to tell whether
  /// anything is wrong.
  final int already;
  final int refused;
  final List<String> problems;

  bool get moved => sent > 0;

  @override
  String toString() =>
      'track: $sent new, $already already there, $refused refused';
}

/// Push everything the computer does not have.
///
/// [limit] caps one run. What is left goes next time, and nothing has to
/// remember where it got to.
Future<TrackPushResult> pushFixes(
  OfflineStore store,
  Api api, {
  int batch = 400,
  int limit = 4000,
}) async {
  var sent = 0, already = 0, refused = 0;
  final problems = <String>[];
  var handled = 0;

  while (handled < limit) {
    final rows = await store.unsyncedFixes(limit: batch);
    if (rows.isEmpty) break;

    final dynamic reply;
    try {
      reply = await api.post('/api/track/batch', {
        'items': [for (final r in rows) _wire(r)],
      });
    } on ApiError catch (e) {
      // NOTHING IS MARKED. Every one of these is still `server_id IS NULL` and
      // will be offered again; the fixes are on the phone either way, and the
      // phone is where they are the original.
      problems.add('Your places could not be sent: ${e.message}');
      break;
    } catch (e) {
      problems.add('Your places could not be sent: $e');
      break;
    }

    final results = (reply is Map ? reply['results'] : null);
    if (results is! List) {
      problems.add('The computer answered in a way this phone did not expect');
      break;
    }

    // Matched by device_row_id, never by position. A server that filtered or
    // reordered would otherwise mark the wrong fixes as sent, and a fix wrongly
    // marked never goes up again.
    final byRow = <int, Map>{};
    for (final r in results) {
      if (r is! Map) continue;
      final id = (r['device_row_id'] as num?)?.toInt();
      if (id != null) byRow[id] = r;
    }

    final done = <int, int>{};
    var progressed = false;
    for (final row in rows) {
      final localId = row['id'] as int;
      handled++;
      final r = byRow[localId];
      if (r == null) {
        problems.add('The computer did not say what happened to one position');
        continue;
      }
      final serverId = (r['id'] as num?)?.toInt();
      if (serverId == null) {
        // Reported and stepped past, so one fix the computer will never take
        // cannot block the thousands behind it.
        refused++;
        progressed = true;
        debugPrint('[track] refused: ${r['error']}');
        continue;
      }
      done[localId] = serverId;
      if (r['duplicate'] == true) {
        already++;
      } else {
        sent++;
      }
      progressed = true;
    }

    // ONE TRANSACTION for the whole batch. Four hundred separate updates is how
    // a sync takes a minute, and a minute is how long somebody waits before
    // deciding it has hung and killing the app.
    await store.markFixesSynced(done);

    // Without this the loop never ends when every row comes back unmatched: the
    // next query returns the same rows for ever.
    if (!progressed) break;
    if (rows.length < batch) break;
  }

  return TrackPushResult(
      sent: sent, already: already, refused: refused, problems: problems);
}

/// One fix as `/api/track/batch` wants it.
///
/// The uuid comes off the row, minted when the fix was written. Deriving one
/// here from the row id and the timestamp looked cheaper — 36 bytes a row is
/// real across a quarter of a million rows — but two phones in one household
/// both start at row id 1, and the collision would be invisible: two fixes a
/// second apart at the same spot look like a stop, and a day full of them
/// re-cuts into places that were never places.
Map<String, dynamic> _wire(Map<String, dynamic> row) => {
      'client_uuid': row['client_uuid'],
      'device_row_id': row['id'],
      'at': row['at'],
      'lat': row['lat'],
      'lon': row['lon'],
      'accuracy': row['accuracy'],
      'speed': row['speed'],
      'battery': row['battery'],
    };
