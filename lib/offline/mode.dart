/// Whether the app is working from this phone or from the computer, and which
/// modules can do either.
///
/// TWO DIFFERENT THINGS, and keeping them apart is the point of this file:
///
///   * **Unreachable** — the computer is asleep or out of range. Not a choice,
///     and the app copes with it whether or not anybody asked.
///   * **Offline mode** — the owner has said "work from this phone". A
///     deliberate setting, for a trip, a metered connection, or simply not
///     wanting the phone reaching for a machine at home all day.
///
/// The list below is the honest answer to "what still works?", and it is
/// derived from what is actually WIRED, not from what is planned. A module
/// named here and not wired would be the worst kind of defect this codebase
/// knows: a control that looks like it does something and does nothing.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Why a module cannot work away from the computer, in the owner's words.
@immutable
class OfflineNote {
  const OfflineNote(this.key, this.label, this.reason);
  final String key;
  final String label;

  /// Null when it works offline.
  final String? reason;

  bool get works => reason == null;
}

/// Every record module the phone shows, and where each one stands.
///
/// **Add a module to the `works` half only when its screen genuinely reads the
/// offline store and queues its writes.** `ModuleListScreen` is the single
/// screen behind all of these, so that is one switch rather than nine — but it
/// is still a switch somebody has to throw.
const offlineModules = <OfflineNote>[
  OfflineNote('expenses', 'Expenses', null),
  OfflineNote('loans', 'Loans', null),
  OfflineNote('cards', 'Cards', null),
  OfflineNote('insurance', 'Insurance', null),
  OfflineNote('investments', 'Investments', null),
  OfflineNote('reminders', 'Reminders', null),
  OfflineNote('todo', 'To-dos', null),
  OfflineNote('notes', 'Notes', null),
  OfflineNote('habits', 'Habits', null),

  // The three that will not, each for its own reason.
  OfflineNote('vault', 'Vault',
      'Passwords are unlocked on your computer and the key never leaves it. '
          'Keeping a usable copy on your phone would undo that.'),
  OfflineNote('gallery', 'Photos',
      'Your library is far too large to hold twice. Backing up photos already '
          'has its own screen.'),
  OfflineNote('documents', 'Documents',
      'Files are downloaded from your computer when you open them.'),
];

Iterable<OfflineNote> get worksOffline =>
    offlineModules.where((m) => m.works);
Iterable<OfflineNote> get needsComputer =>
    offlineModules.where((m) => !m.works);

/// The setting, and nothing more than the setting.
///
/// In plain preferences rather than the secure store: it is a preference, not a
/// credential, and it sits beside the app's other appearance and behaviour
/// choices.
class OfflineMode extends ChangeNotifier {
  static const _key = 'offline.mode';

  bool _on = false;

  /// True when the owner has asked to work from this phone.
  ///
  /// It does NOT mean the computer is unreachable, and it must never be set by
  /// noticing that it is: a network hiccup silently flipping a mode the owner
  /// chose is how a setting stops meaning anything.
  bool get on => _on;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _on = prefs.getBool(_key) ?? false;
    notifyListeners();
  }

  Future<void> set(bool value) async {
    if (_on == value) return;
    _on = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
