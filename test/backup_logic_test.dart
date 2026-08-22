import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/backup.dart';

void main() {
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
