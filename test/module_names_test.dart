// What the modules are CALLED, and which of them lead.
//
// The names were in eight places — the Modules grid, the navigation bar,
// Collections, three titles in the Documents screen, the gallery's album
// picker and vivid Home — and a rename done in seven of eight is the kind of
// thing nobody notices until a screenshot. They come from moduleName() now,
// and these tests are what keep them there.
//
// THE KEY IS NOT THE NAME, and that distinction is the whole reason this was
// cheap: 'documents' and 'gallery' are in user_modules on the server, in the
// storage path under PRIVATE_ROOT, and in the API route guard() protects.
// Renaming a key would be a migration. Renaming a label is a string.
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/customize.dart';
import 'package:safenest/modules.dart';
import 'package:safenest/widgets/home_shortcuts_sheet.dart';

void main() {
  group('what the modules are called', () {
    test('Documents is Drive and Gallery is Photos & videos', () {
      expect(moduleName('documents'), 'Drive');
      expect(moduleName('gallery'), 'Photos & videos');
    });

    test('but their keys are untouched', () {
      // If this ever fails, something has renamed a key — and the server's
      // permissions, the storage tree and every /api/<key> route disagree
      // with the app until somebody writes a migration.
      expect(kAllModuleKeys, contains('documents'));
      expect(kAllModuleKeys, contains('gallery'));
      expect(kAllModuleKeys, isNot(contains('drive')));
      expect(kAllModuleKeys, isNot(contains('photos')));
    });

    test('the short name fits a tab, the full one does not', () {
      // Five one-word neighbours sit beside it in the bottom bar.
      expect(moduleShortName('gallery'), 'Photos');
      expect(moduleShortName('gallery').contains(' '), isFalse);
      expect(moduleShortName('documents'), 'Drive');
      expect(moduleName('gallery').contains(' '), isTrue,
          reason: 'the full name is the one with room to say "videos"');
    });

    test('a module with no special name falls back to its spec', () {
      expect(moduleName('expenses'), 'Expenses');
      expect(moduleShortName('expenses'), 'Expenses');
    });

    test('an unknown key does not crash, it reads back tidily', () {
      expect(moduleName('some_new_thing'), 'Some new thing');
    });
  });

  group('which modules lead', () {
    test('photographs and files are the two', () {
      expect(kMainModules, ['gallery', 'documents']);
    });

    test('Home opens on them, and fills the row', () {
      // Six is shortcutsMax — above it a 390pt screen has no width left for
      // the labels. "All of them" is fourteen and will not fit, so this is as
      // near as the row allows.
      expect(Customize.defaultShortcuts.length, Customize.shortcutsMax);
      expect(Customize.defaultShortcuts.take(2), kMainModules,
          reason: 'the two the app is for come first');
      for (final k in Customize.defaultShortcuts) {
        expect(kAllModuleKeys, contains(k),
            reason: '"$k" is a default shortcut to a module that does not exist');
      }
    });

    test('every default is actually offerable as a shortcut', () {
      // A default the sheet cannot offer is one somebody can remove and never
      // put back.
      final offered = {for (final c in shortcutChoices()) c.key};
      for (final k in Customize.defaultShortcuts) {
        expect(offered, contains(k), reason: '"$k" is not in shortcutChoices');
      }
    });

    test('the sheet still offers every module, not just the defaults', () {
      // The point of the row being six is that the other eight stay reachable.
      final offered = {for (final c in shortcutChoices()) c.key};
      expect(offered.length, greaterThan(Customize.defaultShortcuts.length));
      expect(offered, containsAll(kMainModules));
    });

    test('the shortcut labels follow the rename', () {
      final byKey = {for (final c in shortcutChoices()) c.key: c.label};
      expect(byKey['gallery'], 'Photos');
      expect(byKey['documents'], 'Drive');
      // One word under an icon, which is all the width there is.
      for (final label in byKey.values) {
        expect(label.contains(' '), isFalse, reason: '"$label" is two words');
      }
    });
  });
}
