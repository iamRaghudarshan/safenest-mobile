// "My phone says one number and the computer says another — why?"
//
// Asked out loud, and until now nothing in the product answered it. The phone
// knew BOTH figures the whole time: it fetches the library count to size a
// run, and the server count to notice a library deleted at the computer. It
// showed neither.
//
// The wording is the part that needs pinning, not the arithmetic. A gap is
// usually CORRECT — the phone counts assets, the computer stores distinct
// content, so a picture that exists twice on the phone is one item there, by
// design and for ever. Get the sentence slightly wrong and a normal,
// healthy, de-duplicated library reads as a hundred and seventy-five lost
// photographs. That is the failure this test exists to prevent, so most of
// what is asserted here is what the text must NOT say.
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/screens/backup_screen.dart';

void main() {
  group('the phone/computer tally', () {
    test('says nothing when a figure is missing', () {
      // Before either has been asked. A row that appears with a blank in it
      // is worse than no row.
      expect(tallyNote(null, 1773), isNull);
      expect(tallyNote(1948, null), isNull);
      expect(tallyNote(null, null), isNull);
    });

    test('says nothing useful for an empty phone', () {
      // A phone with no photographs has nothing to compare, and "0 against
      // 0" invites the reader to wonder what went wrong.
      expect(tallyNote(0, 0), isNull);
    });

    test('a match is stated plainly', () {
      expect(tallyNote(1773, 1773), 'Everything on this phone is on your computer.');
    });

    test('duplicates are named as duplicates, never as losses', () {
      // THE CASE THIS IS ALL FOR. 1,948 on the phone, 1,773 on the computer,
      // nothing failed: 175 of them are second copies and the computer keeps
      // one of each. Nothing is missing.
      final note = tallyNote(1948, 1773)!;
      expect(note, contains('175 are copies'));
      expect(note, contains('expected'));
      // The words that would turn a correct result into an alarm.
      for (final wrong in ['missing', 'lost', 'failed', 'not sent', 'error']) {
        expect(note.toLowerCase(), isNot(contains(wrong)),
            reason: 'a de-duplicated library must not read as $wrong');
      }
    });

    test('when failures explain the whole gap, duplicates are not blamed', () {
      // Two videos would not upload and nothing else differs. Saying "2 are
      // copies" here would be a lie, and would send somebody looking for a
      // duplicate that does not exist.
      final note = tallyNote(1775, 1773, failed: 2)!;
      expect(note, contains('2 items'));
      expect(note, contains('could not be sent'));
      expect(note, isNot(contains('copies')));
    });

    test('a mixed gap splits into the two real causes', () {
      // 1,948 phone, 1,773 computer, 2 failed → 2 failures and 173 copies.
      // The arithmetic has to hold or the sentence is just noise.
      final note = tallyNote(1948, 1773, failed: 2)!;
      expect(note, contains('2 items could not be sent'));
      expect(note, contains('173 are copies'));
    });

    test('more failures than the gap does not produce a negative', () {
      // Reachable: failures from a run are counted against a gap measured at
      // a different moment. "-3 are copies" would be gibberish on screen.
      final note = tallyNote(1775, 1773, failed: 50)!;
      expect(note, isNot(contains('-')));
      expect(note, contains('could not be sent'));
    });

    test('a computer holding MORE is not reported as a problem', () {
      // Photos uploaded from the web, from another phone, or taken before
      // some were deleted here. Nothing is wrong and the screen must not
      // imply that anything is.
      final note = tallyNote(1700, 1773)!;
      expect(note, contains('73 items'));
      expect(note, contains('elsewhere'));
      for (final wrong in ['missing', 'lost', 'failed', 'copies']) {
        expect(note.toLowerCase(), isNot(contains(wrong)));
      }
    });

    test('one of something is not "1 items"', () {
      // Small thing, and it is the tell that nobody read the output.
      expect(tallyNote(1774, 1773), contains('1 is a copy'));
      expect(tallyNote(1774, 1773, failed: 1), contains('1 item'));
      expect(tallyNote(1772, 1773), contains('1 item'));
    });

    test('thousands are grouped', () {
      // Consistent with every other figure on this screen; an ungrouped
      // five-digit number beside a grouped one looks like a different unit.
      expect(tallyNote(21948, 1773), contains('20,175'));
    });
  });
}
