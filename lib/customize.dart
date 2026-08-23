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
import 'package:shared_preferences/shared_preferences.dart';

class Customize {
  Customize._();

  static const _kModuleOrder = 'module_order_v1';
  static const _kNavOrder = 'nav_order_v1';
  static const _kNavBar = 'nav_bar_v1';          // explicit tabs shown in the bar
  static const _kNavStyle = 'nav_style_v1';     // 'colour' | 'plain'
  static const _kBackground = 'background_v1';   // 'nature' | 'plain'

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
  static bool _loaded = false;

  /// Safe to call repeatedly — the first read wins and the rest are no-ops.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _moduleOrder = p.getStringList(_kModuleOrder) ?? const [];
    _navOrder = p.getStringList(_kNavOrder) ?? const [];
    _navBar = p.getStringList(_kNavBar) ?? const [];
    _navStyle = p.getString(_kNavStyle) ?? navStyleColour;
    _background = p.getString(_kBackground) ?? backgroundNature;
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

  static Future<void> setNavStyle(String v) async {
    _navStyle = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNavStyle, v);
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
