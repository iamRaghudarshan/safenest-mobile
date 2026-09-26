// "Looking for your computer…" was being set like a number.
//
// The hero's headline slot is designed around a FIGURE — "132 uploaded" at
// 34pt, which is the whole point of the block. The scanning message happens
// to occupy the same slot, and it is a sentence. At 34pt on a single line it
// rendered as "Looking for your com…": the app's most reassuring moment,
// chopped off mid-word.
//
// The rule is that the type follows the CONTENT, not the position. These
// tests hold it there, because the next state added to this screen will land
// in the same slot and inherit the same mistake unless something objects.
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/backup.dart';
import 'package:safenest/screens/backup_screen.dart';

void main() {
  group('the hero headline', () {
    test('a count gets the big type, on one line', () {
      final t = heroTitle(const BackupProgress(
          state: BackupState.done, total: 1048, done: 132));
      expect(t.text, '132 uploaded');
      expect(t.size, 34);
      expect(t.lines, 1);
    });

    test('the scanning message is a SENTENCE, not a figure', () {
      // The actual string, and the actual bug.
      final t = heroTitle(const BackupProgress(
          state: BackupState.scanning,
          message: 'Looking for your computer…'));
      expect(t.text, 'Looking for your computer…');
      // Small enough to fit a phone's width at this length. 34 is what it
      // was, and 26 characters at 34pt is roughly 440 points of text in
      // about 354 of space.
      expect(t.size, lessThanOrEqualTo(20),
          reason: 'a sentence in the headline slot must be set at reading '
              'size, not at figure size');
      // AND ALLOWED TO WRAP. Shrinking it while leaving maxLines at 1 would
      // move the truncation rather than remove it.
      expect(t.lines, greaterThan(1),
          reason: 'a sentence must be able to wrap, or it is still cut off');
    });

    test('scanning never shows a count', () {
      // There is nothing counted yet — that is what scanning means. A "0
      // uploaded" here reads as a finished run that achieved nothing.
      final t = heroTitle(const BackupProgress(
          state: BackupState.scanning, message: 'Looking for your computer…'));
      expect(t.text, isNot(contains('uploaded')));
      expect(t.text, isNot(contains('0')));
    });

    test('scanning with no message still says something', () {
      // An empty headline in a saturated block reads as a broken screen.
      final t = heroTitle(const BackupProgress(state: BackupState.scanning));
      expect(t.text.trim(), isNotEmpty);
    });

    test('a failure sentence is also sized as a sentence', () {
      final t = heroTitle(const BackupProgress(
          state: BackupState.failed, total: 1048, message: 'Session expired'));
      expect(t.text, 'Nothing was sent');
      expect(t.size, lessThan(34));
      expect(t.lines, greaterThan(1));
    });

    test('a failure that DID send some still leads with the count', () {
      // Partly worked is not "nothing was sent", and saying so would be the
      // same class of error in the opposite direction.
      final t = heroTitle(const BackupProgress(
          state: BackupState.failed, total: 1048, done: 40));
      expect(t.text, '40 uploaded');
      expect(t.size, 34);
    });

    test('counts are grouped, like every other figure on the screen', () {
      final t = heroTitle(const BackupProgress(
          state: BackupState.done, total: 20000, done: 12345));
      expect(t.text, '12,345 uploaded');
    });
  });
}
