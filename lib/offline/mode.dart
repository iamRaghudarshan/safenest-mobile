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
  // These seven are the ones ModuleListScreen drives, and it is the screen
  // wired to the offline store. THE KEYS MUST MATCH `kModules` in modules.dart
  // exactly -- 'todos' is plural there, and writing 'todo' here silently turned
  // the whole module back into an online-only one while still promising
  // otherwise on screen. A test compares these against the real keys now,
  // because a typo repeated in the test passes happily.
  OfflineNote('expenses', 'Expenses', null),
  OfflineNote('loans', 'Loans', null),
  OfflineNote('cards', 'Cards', null),
  OfflineNote('insurance', 'Insurance', null),
  OfflineNote('investments', 'Investments', null),
  OfflineNote('reminders', 'Reminders', null),
  OfflineNote('todos', 'To-dos', null),

  // THE VAULT, at the owner's explicit request, twice asked for. It was out at
  // first because passwords decrypted on the computer should not rest on a
  // phone -- and that risk has not gone away: a lost phone now carries them,
  // and recovery is changing every password. What makes it defensible is where
  // they land (sealed under a Keychain key) and how they travel (a bulk
  // endpoint rate limited to 3 calls per 15 minutes and separately audited).
  //
  // Cached ONLY while Working offline is switched on -- see
  // OfflineRecords._mayCache. A phone that never leaves the house never holds
  // them.
  OfflineNote('vault', 'Vault', null),

  // Notes and Habits have screens of their own rather than going through
  // ModuleListScreen, so nothing about them touches the offline store yet. The
  // SERVER would accept them; the phone has no way to queue them. Listing them
  // as working would be a promise the code does not keep.
  OfflineNote('notes', 'Notes',
      'This screen still reads from your computer. It is on the list to '
          'change.'),
  OfflineNote('habits', 'Habits',
      'This screen still reads from your computer. It is on the list to '
          'change.'),

  // And these three, each for a reason that is not going to change.
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
