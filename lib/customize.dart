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

  /// Bumped whenever an order changes, so screens listening rebuild. A plain
  /// ValueNotifier rather than Provider: this is read in two places and wiring a
  /// new provider through main() for a list of strings is more machinery than it
  /// earns.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<String> _moduleOrder = const [];
  static List<String> _navOrder = const [];
  static bool _loaded = false;

  /// Safe to call repeatedly — the first read wins and the rest are no-ops.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _moduleOrder = p.getStringList(_kModuleOrder) ?? const [];
    _navOrder = p.getStringList(_kNavOrder) ?? const [];
    _loaded = true;
  }

  static List<String> get moduleOrder => _moduleOrder;
  static List<String> get navOrder => _navOrder;

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

  /// Back to the app's own order for both.
  static Future<void> reset() async {
    _moduleOrder = const [];
    _navOrder = const [];
    final p = await SharedPreferences.getInstance();
    await p.remove(_kModuleOrder);
    await p.remove(_kNavOrder);
    revision.value++;
  }
}
