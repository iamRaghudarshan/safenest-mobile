/// Getting memories to the computer.
///
/// THE ONLY MODULE THAT PUSHES ITS OWN TABLE. Everything else in SafeNest goes
/// through the journal in `pending` — a create, then the edits that followed it,
/// replayed in order, because the order is the correctness argument. A memory has
/// no such sequence: it is said once, never edited, and the phone's row is the
/// original rather than a cache of the server's. So it is pushed straight from
/// `memories`, keyed by its own `client_uuid`, and the journal is left for the
/// records it was built for.
///
/// What that buys, and it is the reason to accept the asymmetry: the queue
/// cannot be lost. A journal row is an instruction that only makes sense
/// alongside the record it refers to; here the unsent set IS
/// `server_id IS NULL`, derived from the data itself, so a journal that was
/// cleared, a database restored from a backup, or an app reinstalled over its
/// own files all recover the right answer without being told.
library;

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../offline/store.dart';

/// What one push attempt did.
@immutable
class MemoryPushResult {
  const MemoryPushResult({
    required this.sent,
    required this.already,
    required this.refused,
    required this.problems,
  });

  const MemoryPushResult.nothing()
      : sent = 0,
        already = 0,
        refused = 0,
        problems = const [];

  /// Memories the computer did not have and now does.
  final int sent;

  /// Replays — ones it already had under the same uuid. Counted separately
  /// rather than added to [sent], because a sync that reports "12 sent" when it
  /// re-sent the same twelve is a sync nobody can use to tell whether anything
  /// is wrong.
  final int already;

  /// Ones the computer will never accept — malformed, too long. Marked so they
  /// stop blocking the ones behind them.
  final int refused;
  final List<String> problems;

  bool get moved => sent > 0;

  @override
  String toString() =>
      'memories: $sent new, $already already there, $refused refused';
}

/// Push everything the computer does not have yet.
///
/// Serial batches, oldest first. [limit] caps one run so a phone catching up
/// after a fortnight away does not hold the sync open for minutes — what is left
/// goes on the next one, and `server_id IS NULL` means nothing has to remember
/// where it got to.
Future<MemoryPushResult> pushMemories(
  OfflineStore store,
  Api api, {
  int batch = 50,
  int limit = 200,
}) async {
  var sent = 0, already = 0, refused = 0;
  final problems = <String>[];
  var handled = 0;

  while (handled < limit) {
    final rows = await store.unsyncedMemories(limit: batch);
    if (rows.isEmpty) break;

    final dynamic reply;
    try {
      reply = await api.post('/api/memories/batch', {
        'items': [for (final r in rows) _wire(r)],
      });
    } on ApiError catch (e) {
      // The computer could not be reached, or would not take the batch. NOTHING
      // IS MARKED, which is the important part: every one of these is still
      // `server_id IS NULL` and will be offered again. The words are on the
      // phone either way.
      problems.add('Memories could not be sent: ${e.message}');
      break;
    } catch (e) {
      problems.add('Memories could not be sent: $e');
      break;
    }

    final results = (reply is Map ? reply['results'] : null);
    if (results is! List) {
      problems.add('The computer answered in a way this phone did not expect');
      break;
    }

    // Matched back by device_row_id, not by position. A server that filters or
    // reorders would otherwise have this marking the wrong memories as sent,
    // and a memory wrongly marked is one that never goes up again.
    final byRow = <int, Map>{};
    for (final r in results) {
      if (r is! Map) continue;
      final id = (r['device_row_id'] as num?)?.toInt();
      if (id != null) byRow[id] = r;
    }

    var progressed = false;
    for (final row in rows) {
      final localId = row['id'] as int;
      handled++;
      final r = byRow[localId];
      if (r == null) {
        problems.add('The computer did not say what happened to one memory');
        continue;
      }
      final serverId = (r['id'] as num?)?.toInt();
      if (serverId == null) {
        // Reported against this item and moved past, so one memory the computer
        // will never accept cannot block the queue behind it for ever. It stays
        // unsent on the phone, which is where it is safe.
        refused++;
        progressed = true;
        debugPrint('[memory] refused: ${r['error']}');
        continue;
      }
      await store.markMemorySynced(localId, serverId);
      if (r['duplicate'] == true) {
        already++;
      } else {
        sent++;
      }
      progressed = true;
    }

    // WITHOUT THIS THE LOOP NEVER ENDS. If every row came back unmatched,
    // nothing was marked, the next query returns the same rows, and the sync
    // spins until the app is killed.
    if (!progressed) break;
    if (rows.length < batch) break;
  }

  return MemoryPushResult(
      sent: sent, already: already, refused: refused, problems: problems);
}

/// One memory as the server's `/api/memories` wants it.
Map<String, dynamic> _wire(Map<String, dynamic> row) => {
      'client_uuid': row['client_uuid'],
      // So the reply can be matched back to the phone's own row, and so a
      // support question about one memory can be answered against the device.
      'device_row_id': row['id'],
      'body': row['body'],
      'spoken': row['spoken'] == 1,
      // WHEN IT WAS SAID. Letting the server stamp its own arrival time would
      // put a week of memories spoken abroad all on the afternoon of the first
      // connection home.
      'said_at': row['said_at'],
      'facts': [
        for (final f in (row['facts'] as List? ?? const []))
          if (f is Map)
            {'kind': f['kind'], 'value': f['value'], 'at': f['at']},
      ],
      // WHICH picture, not the picture. The file itself goes up through the
      // ordinary photo backup, which already does chunked resumable uploads and
      // knows what the computer has; duplicating that for one image at a time
      // would be a second, worse uploader. What travels here is the camera-roll
      // asset id, so the computer's copy of this memory can be joined to the
      // photograph once the backup has sent it.
      //
      // SAID PLAINLY: nothing on the server resolves that join yet. The id is
      // stored so the link exists in the data rather than having to be
      // reconstructed later from nothing, and a memory whose words are on the
      // laptop while its picture is still only on the phone is a normal state,
      // not an error.
      'photo_asset_id': row['photo_id'],
    };
