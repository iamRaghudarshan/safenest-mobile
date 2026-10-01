// The Android build file, checked as content.
//
// WHY A TEST READS A GRADLE FILE. `flutter build apk` on this machine rewrites
// `minSdk = 23` to `minSdk = flutter.minSdkVersion` every single time, and
// Flutter's own default is 24. So every local build silently raises the
// minimum Android version by one and drops the Android 6 phones the file says
// in its own comment are deliberately supported.
//
// It is silent, it is in a file nobody re-reads, and it reaches the user as
// "some people can no longer install the update" with nothing in the release
// to connect it to anything. It was committed once already and caught by
// accident.
//
// Tests gate the release workflow, so this is the one place that can stop it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gradle = File('android/app/build.gradle.kts');

  test('the build file is where it is expected', () {
    expect(gradle.existsSync(), isTrue,
        reason: 'android/app/build.gradle.kts has moved — fix this test, '
            'because what it guards still matters');
  });

  test('minSdk is pinned to 23, not left to Flutter', () {
    final src = gradle.readAsStringSync();

    expect(src, contains('minSdk = 23'),
        reason: 'minSdk is not pinned to 23. A local `flutter build` rewrites '
            'it to flutter.minSdkVersion, which is 24 — one higher — and that '
            'drops every Android 6 phone from the next update without saying '
            'so anywhere. Put it back.');

    expect(src, isNot(contains('minSdk = flutter.minSdkVersion')),
        reason: 'the rewrite has happened again: `git checkout '
            'android/app/build.gradle.kts` before tagging');
  });

  test('core library desugaring stays on', () {
    // It is what supplies java.time to the phones minSdk 23 lets in, and the
    // build fails somewhere unrelated-looking without it — at
    // checkReleaseAarMetadata, naming the setting but not where it goes. It
    // travels with the line above, so it is checked beside it.
    expect(File('android/app/build.gradle.kts').readAsStringSync(),
        contains('isCoreLibraryDesugaringEnabled = true'));
  });
}
