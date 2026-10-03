/// Sending what the phone is holding, without being asked.
///
/// WHAT THIS REPLACES: nothing. There was no automatic sync at all. Anything
/// typed while the computer was away sat in the queue until somebody opened the
/// Sync screen and pressed the button, and the only hint was a badge. The owner
/// put it plainly — "if internet is available and the laptop is connected then
/// sync, else it should work offline, then when the system is available it
/// should auto sync" — and that is exactly right.
///
/// Three things set it off, and between them they cover how this actually gets
/// used:
///
///   * COMING BACK TO THE APP. You type something on the bus, you get home, you
///     open SafeNest. The resume is the signal, and it is the commonest one.
///   * SOMETHING WAS QUEUED. A save that could not reach the computer starts
///     the retry clock, so a phone left on the table catches up by itself.
///   * A RETRY THAT COMES DUE. Backed off — 20s, 40s, 80s… to five minutes —
///     because a phone out of range all evening must not spend the battery
///     asking every twenty seconds for four hours.
///
/// It never syncs when there is nothing to send, and it never runs two at once:
/// `SyncService.run` refuses a second anyway, and this does not wake up to be
/// refused.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'mode.dart';
import 'store.dart';
import 'sync.dart';

/// The first wait after something is queued, and the ceiling it backs off to.
const _firstRetry = Duration(seconds: 20);
const _slowestRetry = Duration(minutes: 5);

/// How soon after coming back to the app to try.
///
/// Not instantly: the app has a sign-in to restore and a screen to draw, and a
/// sync racing that costs the first frame. Two seconds is below noticing.
const _afterResume = Duration(seconds: 2);

class AutoSync with WidgetsBindingObserver {
  // The lint wants `this._sync`. Dart forbids a named parameter starting with
  // an underscore, so its suggestion does not compile — the same note
  // OfflineRecords carries for the same reason.
  // ignore_for_file: prefer_initializing_formals
  AutoSync({
    required SyncService sync,
    required OfflineStore store,
    required OfflineMode mode,
    bool Function()? signedIn,
  })  : _sync = sync,
        _store = store,
        _mode = mode,
        _signedIn = signedIn;

  final SyncService _sync;
  final OfflineStore _store;
  final OfflineMode _mode;

  /// Whether there is an account to sync to. Without it the first run after a
  /// cold start fires before the session is restored and fails for no reason
  /// the owner could act on.
  final bool Function()? _signedIn;

  Timer? _timer;
  Duration _wait = _firstRetry;
  bool _running = false;
  bool _started = false;

  /// Set by a test to watch what it decided without a real SyncService.
  @visibleForTesting
  int attempts = 0;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    // Something may already be waiting from the last time the app ran.
    _arm(_afterResume);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Back from wherever. The commonest case by far is that the phone is
      // home and on the wifi again, so start the clock over rather than
      // continuing a backoff earned while it was out.
      _wait = _firstRetry;
      _arm(_afterResume);
    } else if (state == AppLifecycleState.paused) {
      // No point holding a timer for an app nobody is looking at. It is re-armed
      // on the way back in.
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Call when something has just been queued.
  void somethingQueued() {
    _wait = _firstRetry;
    _arm(_firstRetry);
  }

  void _arm(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _tick);
  }

  Future<void> _tick() async {
    _timer = null;
    if (_running) return;

    // NOTHING TO SEND IS NOT A FAILURE, and it must not back anything off:
    // the next thing queued should be tried in twenty seconds, not in five
    // minutes because the phone happened to be idle beforehand.
    final waiting = await _pending();
    if (waiting == 0) {
      _wait = _firstRetry;
      return;
    }

    if (_signedIn != null && !_signedIn()) {
      _arm(_firstRetry);
      return;
    }

    // The owner asked to work from the phone. Honour it: pushing anyway would
    // be the app overruling a setting somebody deliberately chose.
    if (_mode.on) {
      _arm(_slowestRetry);
      return;
    }

    _running = true;
    attempts++;
    try {
      final result = await _sync.run();
      if (result.blockedReason == null && result.problems.isEmpty) {
        // It went. If anything is still queued — a conflict, a refusal — that is
        // not something retrying faster will fix.
        _wait = _firstRetry;
        final left = await _pending();
        if (left > 0) _arm(_slowestRetry);
        return;
      }
      _backOff();
    } catch (e) {
      debugPrint('[autosync] not this time: $e');
      _backOff();
    } finally {
      _running = false;
    }
  }

  void _backOff() {
    // Doubling, capped. A phone out of range all evening must not ask every
    // twenty seconds for four hours, and a laptop that comes back must not wait
    // an hour to be noticed — five minutes is the compromise, and a resume
    // short-circuits it anyway.
    _wait = _wait * 2;
    if (_wait > _slowestRetry) _wait = _slowestRetry;
    _arm(_wait);
  }

  Future<int> _pending() async {
    try {
      // EVERY QUEUE, not just the journal. Two modules now push their own
      // tables, and a count that looked only at `pending` would leave a spoken
      // memory or a day of positions sitting on the phone for ever with nothing
      // to send it.
      return (await _store.allPending()).length +
          await _store.unsyncedMemoryCount() +
          await _store.unsyncedFixCount();
    } catch (_) {
      return 0;
    }
  }
}
