/// User layout choices: the order of the module grid and of the bottom bar.
///
/// Non-secret and device-local, so it lives in SharedPreferences — not the
/// Keychain (that is for the token) and not the server (a person's preferred tab
/// order is not a record worth syncing, and wanting it to work offline on day
/// one rules out a round-trip). Stored as a plain list of module KEYS; anything
/// the app no longer knows about is dropped on read and any new module the order
/// has not seen yet is appended, so a saved order from an older build never hides
/// a module or crashes on one that has gone.
library;

import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class Customize {
  Customize._();

  static const _kModuleOrder = 'module_order_v1';
  static const _kNavOrder = 'nav_order_v1';
  static const _kNavBar = 'nav_bar_v1';          // explicit tabs shown in the bar
  static const _kNavStyle = 'nav_style_v1';     // 'colour' | 'plain'
  static const _kBackground = 'background_v1';   // 'nature' | 'plain' | 'photo'
  static const _kBackgroundPhoto = 'background_photo_v1';  // a file in our own dir
  static const _kBackgroundDim = 'background_dim_v1';      // 20..80
  static const _kHomeShortcuts = 'home_shortcuts_v1';
  static const _kSkin = 'skin_v1';               // 'classic' | 'vivid'

  /// How many tabs the bottom bar can hold before it gets cramped, and the fewest
  /// it may have and still be a bar. Enforced by the customise sheet.
  static const navBarMax = 6;
  static const navBarMin = 2;

  /// Defaults match what shipped before this screen existed, so a person who
  /// never opens it sees exactly the app they had.
  static const navStyleColour = 'colour';
  static const navStylePlain = 'plain';
  static const backgroundNature = 'nature';
  static const backgroundPlain = 'plain';
  static const backgroundPhoto = 'photo';

  /// HOW FAR THE PICTURE IS DIMMED, and the floor is the point.
  ///
  /// Every Classic scaffold is transparent, so the whole app is drawn straight
  /// on top of this. An undimmed holiday photograph puts white cards and grey
  /// captions over a bright sky, and nothing on the page can be read. 20% is
  /// the least that is ever applied: a background somebody cannot read over is
  /// not a setting, it is a broken app they chose for themselves.
  /// The floor is NOT a matter of taste. Classic's words are dark ink meant
  /// for a near-white page, and a photograph can be any colour at all — a
  /// black-and-white night shot included. Below this the veil no longer
  /// returns enough of the page colour for body text to reach the 4.5:1 that
  /// makes it legible, which `backdropContrast` in theme.dart computes rather
  /// than assumes. Raised from 20 after the first version shipped unreadable.
  /// The floor is NOT a matter of taste, and it is not fixed either.
  ///
  /// Classic's words are dark ink meant for a near-white page, and a
  /// photograph can be any colour at all. `readableVeil` in theme.dart
  /// computes the least veil that still reaches 4.5:1 against the worst
  /// picture somebody could choose — 50% for the light page, 63% for the dark
  /// one — and the backdrop raises whatever is stored to that. This constant
  /// is only the absolute bound on what may be SAVED.
  static const dimMin = 30;
  static const dimMax = 95;
  static const dimDefault = 70;

  /// How many shortcuts may sit on Home.
  ///
  /// Below three it is not a row; above six a 390pt screen has no width left
  /// for the labels — the same arithmetic that caps the bottom bar at six.
  static const shortcutsMin = 3;
  static const shortcutsMax = 6;

  /// What Home has always shown, and what it falls back to.
  static const defaultShortcuts = ['expenses', 'reminders', 'gallery', 'documents'];

  /// THE TWO LOOKS.
  ///
  /// `classic` is the app exactly as it has always been — the web app's own
  /// palette, transcribed, so the phone and the browser read as one product.
  /// It stays the default on purpose: an update that silently repaints
  /// somebody's app is a shock, not a feature, and this one is reached by a
  /// person choosing it.
  ///
  /// `vivid` is the redesign: photos and files lead, and colour carries
  /// meaning rather than decoration — one hue per module, everywhere it
  /// appears, so people navigate by colour without reading.
  static const skinClassic = 'classic';
  static const skinVivid = 'vivid';

  /// Bumped whenever an order changes, so screens listening rebuild. A plain
  /// ValueNotifier rather than Provider: this is read in two places and wiring a
  /// new provider through main() for a list of strings is more machinery than it
  /// earns.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<String> _moduleOrder = const [];
  static List<String> _navOrder = const [];
  static List<String> _navBar = const [];
  static String _navStyle = navStyleColour;
  static String _background = backgroundNature;
  static String _backgroundPhoto = '';
  static int _backgroundDim = dimDefault;
  static List<String> _homeShortcuts = const [];
  static String _skin = skinClassic;
  static bool _loaded = false;

  /// Read the settings again from scratch.
  ///
  /// `ensureLoaded` is a no-op after the first call, which is right for an app
  /// that loads once — but it makes the load path itself untestable, and the
  /// load path is where a photo background whose file has vanished is caught.
  @visibleForTesting
  static Future<void> reloadForTest() async {
    _loaded = false;
    await ensureLoaded();
  }

  /// Safe to call repeatedly — the first read wins and the rest are no-ops.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _moduleOrder = p.getStringList(_kModuleOrder) ?? const [];
    _navOrder = p.getStringList(_kNavOrder) ?? const [];
    _navBar = p.getStringList(_kNavBar) ?? const [];
    _navStyle = p.getString(_kNavStyle) ?? navStyleColour;
    _background = p.getString(_kBackground) ?? backgroundNature;
    _backgroundPhoto = p.getString(_kBackgroundPhoto) ?? '';
    _backgroundDim =
        (p.getInt(_kBackgroundDim) ?? dimDefault).clamp(dimMin, dimMax);
    _homeShortcuts = p.getStringList(_kHomeShortcuts) ?? const [];
    // A photo background whose FILE has gone — the phone was restored, the app
    // data cleared — must not leave the app with nothing behind it. Checked at
    // load rather than at paint: a missing file discovered while drawing is a
    // blank screen, and this is the one place it can be answered once.
    if (_background == backgroundPhoto &&
        (_backgroundPhoto.isEmpty || !File(_backgroundPhoto).existsSync())) {
      _background = backgroundNature;
      _backgroundPhoto = '';
    }
    // Anything unrecognised falls back to classic rather than to whatever was
    // written: a preference file carried forward from a build that knew a skin
    // this one does not must not leave the app with no theme at all.
    final skin = p.getString(_kSkin);
    _skin = skin == skinVivid ? skinVivid : skinClassic;
    _loaded = true;
  }

  static List<String> get moduleOrder => _moduleOrder;
  static List<String> get navOrder => _navOrder;

  /// The tabs the person has chosen for the bottom bar (keys, in order). Empty
  /// means "use the app's default set" — a fresh install behaves exactly as
  /// before this screen existed.
  static List<String> get navBar => _navBar;

  static Future<void> setNavBar(List<String> keys) async {
    _navBar = keys;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kNavBar, keys);
    revision.value++;
  }
  static String get navStyle => _navStyle;
  static String get background => _background;
  static bool get colourfulNav => _navStyle == navStyleColour;
  static bool get natureBackground => _background == backgroundNature;
  static bool get photoBackground => _background == backgroundPhoto;

  /// The chosen picture, or empty. It is a copy inside the app's own folder,
  /// never a path into the camera roll: the person is free to delete the
  /// original, and on iOS a library path is not readable again after a
  /// restart anyway.
  static String get backgroundImagePath => _backgroundPhoto;
  static int get backgroundDim => _backgroundDim;

  /// The shortcuts on Home, in order. Empty means the default four, so a
  /// phone that has never touched this behaves exactly as it always did.
  static List<String> get homeShortcuts =>
      _homeShortcuts.isEmpty ? defaultShortcuts : _homeShortcuts;

  /// True once somebody has chosen for themselves — used only to decide
  /// whether "Reset" has anything to undo.
  static bool get homeShortcutsChosen => _homeShortcuts.isNotEmpty;

  static Future<void> setHomeShortcuts(List<String> keys) async {
    _homeShortcuts = keys;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kHomeShortcuts, keys);
    revision.value++;
  }

  static Future<void> setBackgroundDim(int v) async {
    _backgroundDim = v.clamp(dimMin, dimMax);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kBackgroundDim, _backgroundDim);
    revision.value++;
  }

  /// Use [path] as the background. The caller has already copied the file into
  /// the app's own folder; this only records it.
  static Future<void> setBackgroundPhoto(String path) async {
    _backgroundPhoto = path;
    _background = backgroundPhoto;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBackgroundPhoto, path);
    await p.setString(_kBackground, backgroundPhoto);
    revision.value++;
  }

  static Future<void> setNavStyle(String v) async {
    _navStyle = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNavStyle, v);
    revision.value++;
  }

  /// Which look the app wears. `classic` unless it says otherwise.
  static String get skin => _skin;
  static bool get vividSkin => _skin == skinVivid;

  static Future<void> setSkin(String v) async {
    _skin = v == skinVivid ? skinVivid : skinClassic;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSkin, _skin);
    // The whole app is rebuilt from this, not just the screen that set it:
    // main.dart builds its MaterialApp inside a listener on `revision`, so a
    // theme change has to travel the same way a nav change does.
    revision.value++;
  }

  static Future<void> setBackground(String v) async {
    _background = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBackground, v);
    revision.value++;
  }

  /// Order [keys] by the saved preference: known-and-saved first in the saved
  /// order, then anything new (a module added since the order was saved) in its
  /// natural order, appended. Unknown saved keys are ignored. This is what makes
  /// an old saved order forward-compatible with a build that has new modules.
  static List<String> apply(List<String> saved, List<String> natural) {
    final have = natural.toSet();
    final ordered = <String>[
      for (final k in saved)
        if (have.contains(k)) k,
    ];
    final placed = ordered.toSet();
    for (final k in natural) {
      if (!placed.contains(k)) ordered.add(k);
    }
    return ordered;
  }

  static Future<void> setModuleOrder(List<String> keys) async {
    _moduleOrder = keys;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kModuleOrder, keys);
    revision.value++;
  }

  static Future<void> setNavOrder(List<String> keys) async {
    _navOrder = keys;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kNavOrder, keys);
    revision.value++;
  }

  /// Back to the app's own order and look for everything.
  static Future<void> reset() async {
    _moduleOrder = const [];
    _navOrder = const [];
    _navBar = const [];
    _navStyle = navStyleColour;
    _background = backgroundNature;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kModuleOrder);
    await p.remove(_kNavOrder);
    await p.remove(_kNavBar);
    await p.remove(_kNavStyle);
    await p.remove(_kBackground);
    revision.value++;
  }
}
