// The two things somebody can now change about Classic: what the app is drawn
// on, and which shortcuts sit on Home.
//
// Both are stored settings with rules attached, and the rules are the part
// worth pinning — a dim that can reach zero makes the app unreadable, and a
// shortcut row that can empty leaves Home with nothing on it.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safenest/customize.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Customize.ensureLoaded();
  });

  group('the background', () {
    test('a fresh install is unchanged — the nature scene', () {
      expect(Customize.natureBackground, isTrue);
      expect(Customize.photoBackground, isFalse);
      expect(Customize.backgroundImagePath, isEmpty);
    });

    test('the dim starts somewhere readable', () {
      expect(Customize.backgroundDim, Customize.dimDefault);
      expect(Customize.dimDefault,
          inInclusiveRange(Customize.dimMin, Customize.dimMax));
    });

    test('it cannot be turned off', () async {
      // THE RULE THIS FEATURE RESTS ON. Classic's scaffolds are transparent,
      // so an undimmed photograph puts white cards and grey captions over a
      // bright sky and nothing on the page can be read. A setting that lets
      // somebody do that to themselves is not a choice, it is a trap.
      await Customize.setBackgroundDim(0);
      expect(Customize.backgroundDim, Customize.dimMin);

      await Customize.setBackgroundDim(-40);
      expect(Customize.backgroundDim, Customize.dimMin);
    });

    test('and it cannot be turned up to a black screen', () async {
      await Customize.setBackgroundDim(100);
      expect(Customize.backgroundDim, Customize.dimMax);
    });

    test('choosing a picture selects it as well as storing it', () async {
      // Two steps that must not come apart: a phone that recorded the path
      // and left the mode on "plain" would look as though nothing happened.
      await Customize.setBackgroundPhoto('/data/app/background/bg_1.jpg');
      expect(Customize.photoBackground, isTrue);
      expect(Customize.backgroundImagePath, endsWith('bg_1.jpg'));
      expect(Customize.natureBackground, isFalse);
    });

    test('a photo background whose file has gone falls back', () async {
      // The app was reinstalled, or its data cleared. Without this the app
      // comes back to a blank screen with nothing to explain it — and the one
      // place to answer it is at load, not while painting.
      SharedPreferences.setMockInitialValues({
        'background_v1': 'photo',
        'background_photo_v1': '/nowhere/that/exists/bg.jpg',
      });
      await Customize.reloadForTest();

      expect(Customize.photoBackground, isFalse);
      expect(Customize.natureBackground, isTrue,
          reason: 'it must land on something that draws');
      expect(Customize.backgroundImagePath, isEmpty);
    });
  });

  group('the shortcuts on Home', () {
    test('a phone that has never touched this behaves as it always did', () {
      expect(Customize.homeShortcuts, Customize.defaultShortcuts);
      expect(Customize.homeShortcutsChosen, isFalse);
    });

    test('a chosen set is kept in the order it was arranged', () async {
      await Customize.setHomeShortcuts(['vault', 'gallery', 'notes']);
      expect(Customize.homeShortcuts, ['vault', 'gallery', 'notes']);
      expect(Customize.homeShortcutsChosen, isTrue);
    });

    test('resetting goes back to the four, not to nothing', () async {
      // Empty is the STORED form of "I have no opinion", and it has to read
      // back as the default four rather than as a row with nothing in it.
      await Customize.setHomeShortcuts(['vault']);
      await Customize.setHomeShortcuts(const []);
      expect(Customize.homeShortcuts, Customize.defaultShortcuts);
      expect(Customize.homeShortcutsChosen, isFalse);
    });

    test('the bounds are the bottom bar\'s, for the same reason', () {
      // Six across 390pt is where labels stop fitting — the arithmetic that
      // already caps the nav bar. Below three it is not a row.
      expect(Customize.shortcutsMin, 3);
      expect(Customize.shortcutsMax, 6);
      expect(Customize.defaultShortcuts.length,
          inInclusiveRange(Customize.shortcutsMin, Customize.shortcutsMax));
    });
  });
}
