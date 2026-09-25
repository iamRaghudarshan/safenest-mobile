import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/backup.dart';

void main() {
  inFlightTests();
  progressTests();
  group('shouldReoffer — re-check the whole library only on a real loss', () {
    test('server count DROPPED since last run -> re-offer (a real deletion)', () {
      expect(BackupService.shouldReoffer(90, 100), isTrue);
    });

    test('server holds fewer than the phone thinks it sent, but count is STABLE '
        '-> do NOT re-offer (this is the duplicate-photos bug that re-hashed '
        'the library every run)', () {
      // Phone sent 20000 ids; computer de-duplicated to 19000 and has held 19000
      // steady. lastCount == serverCount, so nothing dropped.
      expect(BackupService.shouldReoffer(19000, 19000), isFalse);
    });

    test('server count GREW (new photos elsewhere) -> do NOT re-offer', () {
      expect(BackupService.shouldReoffer(120, 100), isFalse);
    });

    test('first run, no baseline yet -> do NOT re-offer', () {
      expect(BackupService.shouldReoffer(100, null), isFalse);
    });

    test('offline / old server (unknown count) -> do NOT re-offer', () {
      expect(BackupService.shouldReoffer(null, 100), isFalse);
    });
  });

  group('looksLikeLan — is the configured address already a direct LAN host', () {
    test('private ranges are LAN', () {
      expect(BackupService.looksLikeLan('http://192.168.31.159:8080'), isTrue);
      expect(BackupService.looksLikeLan('http://10.0.0.5:8080'), isTrue);
      expect(BackupService.looksLikeLan('http://172.16.4.4:8080'), isTrue);
      expect(BackupService.looksLikeLan('http://172.31.9.9:8080'), isTrue);
    });

    test('a public tunnel domain is NOT LAN (so discovery should run)', () {
      expect(BackupService.looksLikeLan('https://safenest.example.com'), isFalse);
    });

    test('172.15 and 172.32 are outside the private block', () {
      expect(BackupService.looksLikeLan('http://172.15.0.1:8080'), isFalse);
      expect(BackupService.looksLikeLan('http://172.32.0.1:8080'), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Per-file progress: which photo is going up, and how far through it is.
//
// The complaint that produced this: "some photos and videos not moving showing
// error". A run where one two-gigabyte video takes nine minutes shows the same
// "12 of 400" the whole time, and a counter that does not move is
// indistinguishable from a backup that has died.

void progressTests() {
  group('per-file backup progress', () {
    test('nothing in flight reports no fraction', () {
      const p = BackupProgress(state: BackupState.running, total: 10);
      // Null, not zero: "not started" and "started, nothing sent" look the
      // same as 0.0 and mean different things to whoever is watching.
      expect(p.currentFraction, isNull);
    });

    test('a file in flight reports how far through it is', () {
      const p = BackupProgress(
        state: BackupState.running,
        currentLabel: 'IMG_4102.MOV',
        currentSent: 512,
        currentTotal: 2048,
      );
      expect(p.currentFraction, 0.25);
      expect(p.currentLabel, 'IMG_4102.MOV');
    });

    test('a finished file reads as exactly one', () {
      const p = BackupProgress(
          state: BackupState.running, currentSent: 900, currentTotal: 900);
      expect(p.currentFraction, 1.0);
    });

    test('it never leaves 0..1, whatever the counts say', () {
      // A LinearProgressIndicator asserts outside that range, so a server that
      // reports more received than promised would crash the screen rather
      // than nudge the bar.
      const over = BackupProgress(currentSent: 1500, currentTotal: 1000);
      expect(over.currentFraction, 1.0);
      const under = BackupProgress(currentSent: -5, currentTotal: 1000);
      expect(under.currentFraction, 0.0);
    });

    test('a file of unknown size reports null rather than dividing by zero',
        () {
      const p = BackupProgress(currentLabel: 'x.jpg', currentSent: 10);
      expect(p.currentFraction, isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// One item on its way up, and the two different waits it can be in.
void inFlightTests() {
  group('an item in flight', () {
    test('reports how far through the upload it is', () {
      const it = BackupItem(
          id: 'a1', label: 'IMG_1.HEIC', isVideo: false, sent: 25, total: 100);
      expect(it.fraction, 0.25);
      expect(it.fetching, isFalse);
    });

    test('an unknown size reports null rather than dividing by zero', () {
      const it = BackupItem(id: 'a1', label: 'x', isVideo: false);
      expect(it.fraction, isNull);
    });

    test('never leaves 0..1 however odd the counts', () {
      const over =
          BackupItem(id: 'a', label: 'x', isVideo: false, sent: 9, total: 4);
      expect(over.fraction, 1.0);
    });

    test('coming down from iCloud is a DIFFERENT state from going up', () {
      // Showing an upload bar at zero while Apple sends a 200MB video looks
      // exactly like a stall, which is the bug this separation exists for.
      const it = BackupItem(id: 'a1', label: 'v.MOV', isVideo: true);
      final fetching = it.withFetch(0.4);
      expect(fetching.fetching, isTrue);
      expect(fetching.fetched, 0.4);
      expect(fetching.fraction, isNull, reason: 'nothing has been sent yet');
    });

    test('a fetch progress outside 0..1 is clamped', () {
      const it = BackupItem(id: 'a1', label: 'v.MOV', isVideo: true);
      expect(it.withFetch(1.9).fetched, 1.0);
      expect(it.withFetch(-0.5).fetched, 0.0);
    });

    test('starting the upload clears the fetching state', () {
      const it = BackupItem(id: 'a1', label: 'v.MOV', isVideo: true);
      final up = it.withFetch(1.0).withProgress(10, 100);
      expect(up.fetching, isFalse);
      expect(up.fraction, 0.1);
    });
  });
}
