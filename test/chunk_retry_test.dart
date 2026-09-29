// Whether a failed chunk is worth sending again.
//
// This rule is what decides whether a large video can be backed up at all
// over a home connection. A two-gigabyte clip is five hundred requests at 4 MB
// each, and the old code abandoned the whole file the moment any one of them
// came back non-200 — so the chance of success was the chance of five hundred
// consecutive requests surviving domestic wifi, which is not a good bet.
//
// The distinction being pinned is between "the connection faltered" and "the
// computer said no". The first is worth waiting out. The second must be
// reported at once: repeating it spends the connection to be told the same
// thing, and buries the one sentence that says what to go and fix.
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/backup.dart';

void main() {
  group('a chunk is sent again when', () {
    test('the request never completed at all', () {
      // Status 0 is this app's own "no reply" — no network, a dropped
      // connection, a timeout. It is the commonest failure on a phone and the
      // whole reason retrying exists.
      expect(BackupService.worthRetryingStatus(0), isTrue);
    });

    test('the computer had a bad moment', () {
      expect(BackupService.worthRetryingStatus(500), isTrue);
      expect(BackupService.worthRetryingStatus(502), isTrue);
      expect(BackupService.worthRetryingStatus(503), isTrue);
      expect(BackupService.worthRetryingStatus(504), isTrue);
    });

    test('it was asked in so many words to wait', () {
      expect(BackupService.worthRetryingStatus(408), isTrue);
      expect(BackupService.worthRetryingStatus(429), isTrue);
    });
  });

  group('but not when', () {
    test('the computer refused the file', () {
      // A decision, not a hiccup. 413 too large, 400 not what it claims,
      // 415 unsupported — none of these change by asking again.
      for (final s in [400, 413, 415, 422]) {
        expect(BackupService.worthRetryingStatus(s), isFalse,
            reason: '$s is a refusal, not a hiccup');
      }
    });

    test('the session is gone', () {
      // Retrying a 401 four times with backoff delays the sign-in prompt by
      // fifteen seconds and achieves nothing else.
      expect(BackupService.worthRetryingStatus(401), isFalse);
      expect(BackupService.worthRetryingStatus(403), isFalse);
    });

    test('the disk is full', () {
      // THE ONE THAT LOOKS LIKE THE OTHERS. 507 is a 5xx, so a plain
      // "retry every 5xx" rule would sit through four backoffs waiting for a
      // full disk to empty itself — delaying the only message that tells
      // somebody what to go and do.
      expect(BackupService.worthRetryingStatus(507), isFalse);
    });

    test('a chunk simply landed out of order', () {
      // 409 is not retried here because it is not a failure: it means the
      // computer holds a different amount than the phone believed, and it is
      // reconciled by asking rather than by resending.
      expect(BackupService.worthRetryingStatus(409), isFalse);
    });
  });

  test('it gives up eventually rather than never', () {
    // Four attempts at 1s, 2s, 4s, 8s is fifteen seconds of patience. Enough
    // for a wifi handover or a computer waking; short enough that a real
    // outage is reported instead of sat through.
    expect(BackupService.chunkAttempts, 4);
  });
}
