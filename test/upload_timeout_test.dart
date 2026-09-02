// How long an upload is allowed, which is what stopped a customer's videos.
//
// 1,137 photos went through and 22 videos did not, every one of them reported
// as "your computer could not be reached" — so the owner checked a machine that
// had been awake the whole time. It was a flat five-minute timeout: backup.dart
// measured 51 MB in 67 seconds over the tunnel, so a 250 MB clip needs five and
// a half minutes and was cut off at five.
import 'package:flutter_test/flutter_test.dart';
import 'package:safenest/api.dart';

void main() {
  group('an upload gets time in proportion to its size', () {
    test('a small photo still gets the five-minute floor', () {
      expect(Api.uploadTimeout(2 * 1024 * 1024).inSeconds, 300,
          reason: 'a 2 MB photo does not need longer, and a floor keeps a '
              'stalled request from hanging about');
    });

    test('THE ONE THAT BIT: a 250 MB video gets more than five minutes', () {
      final t = Api.uploadTimeout(250 * 1024 * 1024);
      expect(t.inMinutes, greaterThan(5),
          reason: 'at the measured 0.76 MB/s this needs ~5.5 minutes, and the '
              'old flat 300s cut it off just before it finished');
      expect(t.inMinutes, greaterThan(40),
          reason: 'the allowance is 100 KB/s — far below the measured rate, '
              'because a timeout is a last resort and not a speed budget');
    });

    test('a 51 MB clip comfortably clears its measured 67 seconds', () {
      expect(Api.uploadTimeout(51 * 1024 * 1024).inSeconds,
          greaterThan(67 * 4));
    });

    test('it grows with size rather than stepping', () {
      final small = Api.uploadTimeout(100 * 1024 * 1024).inSeconds;
      final big = Api.uploadTimeout(400 * 1024 * 1024).inSeconds;
      expect(big, greaterThan(small * 3));
    });

    test('an empty body does not produce a zero timeout', () {
      expect(Api.uploadTimeout(0).inSeconds, 300);
    });
  });

  test('a timeout is not the same answer as unreachable', () {
    // Collapsing both into 0 is exactly what sent somebody to check a network
    // that was fine.
    expect(kTimedOut, isNot(0));
    expect(kTimedOut, lessThan(0), reason: 'must never collide with an HTTP status');
  });
}
