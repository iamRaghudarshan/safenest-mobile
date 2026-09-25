import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/backup.dart';

void main() {
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
