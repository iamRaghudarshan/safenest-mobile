// Playing a file that is still only on the phone.
//
// The clock is pure and is the half that a render test cannot judge: a video
// player reading "3:7" for three minutes and seven seconds is the classic tell
// that nobody looked at the output, and it looks perfectly fine in a
// screenshot until you know what you are looking at.
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/widgets/local_media_preview.dart';

void main() {
  group('the position clock', () {
    test('seconds are always two digits', () {
      expect(clockText(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(clockText(const Duration(seconds: 5)), '0:05');
    });

    test('a clip of a few seconds still reads as a time', () {
      expect(clockText(Duration.zero), '0:00');
      expect(clockText(const Duration(seconds: 59)), '0:59');
    });

    test('minutes roll over rather than accumulating', () {
      expect(clockText(const Duration(minutes: 59, seconds: 59)), '59:59');
      expect(clockText(const Duration(hours: 1)), '1:00:00');
    });

    test('past an hour the minutes are padded too', () {
      // "1:5:03" is what happens when only the seconds are padded.
      expect(clockText(const Duration(hours: 1, minutes: 5, seconds: 3)),
          '1:05:03');
      expect(clockText(const Duration(hours: 2, minutes: 30)), '2:30:00');
    });
  });
}
