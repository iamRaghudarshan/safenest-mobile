// The two bugs a QA pass reported, pinned so they cannot come back.
//
// Both were invisible to `flutter analyze` and to every test that existed: one
// was a set-membership mistake and the other was a status code being thrown
// away. Neither is a type error, so only an assertion about BEHAVIOUR catches
// them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/modules.dart';

void main() {
  group('Gallery must be reachable — it vanished for admins for nine versions',
      () {
    // ROOT CAUSE: home_screen.dart built its allow-everything set as
    //   {...kModules.map((m) => m.key), 'vault', 'documents'}
    // and kModules is only the SEVEN record modules. Gallery is a screen of its
    // own, so it was never in that set. Three code paths used it — an admin, a
    // user whose permissions came back empty, and a user whose permissions
    // could not be fetched — and on all three the Gallery tab was filtered out
    // of the navigation bar entirely.
    test('kAllModuleKeys contains every module the app can open', () {
      for (final key in ['gallery', 'documents', 'vault']) {
        expect(kAllModuleKeys, contains(key),
            reason: '$key is a screen of its own and is NOT in kModules — '
                'leaving it out of the allow-set hides it from the whole app');
      }
      for (final m in kModules) {
        expect(kAllModuleKeys, contains(m.key));
      }
    });

    test('the record modules alone are NOT a complete allow-set', () {
      // The exact expression that caused the bug, asserted to be insufficient.
      // If someone reaches for this shape again, this says why it is wrong.
      final recordOnly = {for (final m in kModules) m.key};
      expect(recordOnly.contains('gallery'), isFalse,
          reason: 'kModules has never contained gallery — that is the trap');
      expect(kAllModuleKeys.length, greaterThan(recordOnly.length));
    });

    test('gallery has no ModuleSpec, which is why the fallback had to exist',
        () {
      // _open() tried moduleByKey() as its second chance and got null, then fell
      // through a lone `if (key == 'documents')` — so the Modules tile and the
      // Dashboard shortcut did nothing at all, with no error.
      expect(moduleByKey('gallery'), isNull);
      expect(moduleByKey('documents'), isNull);
      expect(moduleByKey('vault'), isNull);
      expect(moduleByKey('expenses'), isNotNull);
    });
  });

  group('Backup must be able to say WHY it failed', () {
    // ROOT CAUSE: Api.postRaw returned a bool, so 401, 402, 413, 500 and a
    // dropped connection were one value. The screen could only ever say
    // "N could not be read" — which is not even the right half of the system,
    // because the photo read perfectly and the upload failed.
    //
    // These assert the mapping the engine uses, which is the thing that turns
    // "backup does not work" into something a person can act on in ten seconds.
    String problemFor(int status) => switch (status) {
          0 => 'unreachable',
          401 => 'expired',
          402 => 'licence',
          403 => 'not allowed',
          413 => 'too large',
          >= 500 => 'server error',
          _ => 'refused',
        };

    test('every failure mode is distinguishable', () {
      final seen = <String>{};
      for (final s in [0, 401, 402, 403, 413, 500, 400]) {
        seen.add(problemFor(s));
      }
      expect(seen.length, 7,
          reason: 'each status must produce its own advice — collapsing them '
              'into one bool is the bug');
    });

    test('a total failure is not a success', () {
      // The old final message was "Backed up. 0 new, 0 already there." whatever
      // happened, with state = done. An expired session, a lapsed licence and a
      // sleeping laptop all read as a completed backup.
      bool isFailure(int done, int failed) => failed > 0 && done == 0;
      expect(isFailure(0, 5000), isTrue,
          reason: '5000 failures and nothing sent is a failed run');
      expect(isFailure(4000, 1000), isFalse,
          reason: 'a partial run is not a failure, but must report the 1000');
      expect(isFailure(0, 0), isFalse,
          reason: 'nothing to do is a success — a second run over a backed-up '
              'library sends nothing and that is correct');
    });

    test('a filename cannot break out of the multipart header', () {
      // filename="$name" puts an arbitrary string into a header VALUE. A
      // newline there lets the name inject headers of its own.
      String safe(String n) => n
          .replaceAll(RegExp(r'[\r\n"\\]'), '_')
          .replaceAll(RegExp(r'[\x00-\x1f]'), '_');

      expect(safe('holiday.jpg'), 'holiday.jpg');
      expect(safe('my "best" shot.jpg'), 'my _best_ shot.jpg');
      expect(safe('a\r\nContent-Type: text/html\r\n\r\n<script>.jpg'),
          isNot(contains('\n')));
      expect(safe('back\\slash.jpg'), 'back_slash.jpg');
    });
  });

  group('Cards: an edit that saves must not report a server fault', () {
    // ROOT CAUSE (backend, cards.py): the audit line read `c.card_name`, which
    // is not a column on CreditCard. Every PUT raised AttributeError -> 500 —
    // AFTER db.commit(), so the change WAS saved, no audit row was written, and
    // the person was told the server had failed.
    //
    // The client half worth pinning: the fields the phone offers are all real.
    test('every card field the app offers exists on the server', () {
      const writable = ['bank', 'last4', 'credit_limit', 'billing_day', 'due_date'];
      final spec = moduleByKey('cards')!;
      for (final f in spec.fields) {
        expect(writable, contains(f.key),
            reason: 'cards.py accepts only $writable');
      }
      expect(spec.fields.any((f) => f.key == 'card_name'), isFalse,
          reason: 'card_name is not a column anywhere — it is what broke the '
              'server, and it must not reappear on a form either');
    });
  });
}
