/// Taking the fixes.
///
/// OFF UNTIL SOMEBODY TURNS IT ON, and that is not a default anybody should
/// change lightly. This is the most sensitive thing in the app: a continuous
/// record of where a person is. Nothing is recorded until the switch is on, the
/// switch survives a restart, a notification says so while it is running, and
/// "forget everything" is on the same screen as the switch.
///
/// BALANCED, which is a real decision rather than a shrug. A fix when you have
/// moved [movedMetres], and at most one every [atMost] while you have not. That
/// is enough to tell home from the office, to time a commute, and to answer
/// "where was I at three"; it is not enough to draw the exact pavement you
/// walked on, and it costs a few percent of a battery a day rather than a
/// quarter of one.
///
/// Behind an interface, like `Dictation` and `PhotoSource` before it, for the
/// same reason: no machine this app is developed on has a GPS, so the screen
/// and the service both have to be drivable without one.
library;

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../offline/store.dart';

/// Moved this far and it is worth a new fix.
const movedMetres = 100;

/// Standing still, no more often than this.
const atMost = Duration(minutes: 2);

/// One position, as the phone reports it.
@immutable
class Spot {
  const Spot({
    required this.at,
    required this.lat,
    required this.lon,
    this.accuracy = 0,
    this.speed,
  });

  final DateTime at;
  final double lat;
  final double lon;
  final double accuracy;
  final double? speed;
}

/// Why the phone will not give its position.
///
/// Four reasons, kept apart because the way out of each is different and a
/// single "location unavailable" leaves somebody with nothing to do about it.
enum NoLocation {
  /// The switch for the whole phone, in system settings.
  turnedOff,

  /// Asked and refused, but can be asked again.
  refused,

  /// Refused permanently — on Android, "don't ask again". Only Settings fixes
  /// it, and the app has to say so rather than asking into a void.
  refusedForGood,

  /// Granted only while the app is open. Worth naming separately because it
  /// LOOKS like it works: the timeline fills in while you are using the phone
  /// and stops the moment you put it in your pocket, which is exactly when it
  /// was supposed to be recording.
  onlyWhileOpen,
}

abstract class Positions {
  /// Ask for what is needed, and say what is missing.
  Future<NoLocation?> permission({required bool background});

  /// A fix every time the phone has moved far enough.
  Stream<Spot> watch();

  /// One fix, now.
  Future<Spot?> once();
}

class PlatformPositions implements Positions {
  @override
  Future<NoLocation?> permission({required bool background}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return NoLocation.turnedOff;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.deniedForever) return NoLocation.refusedForGood;
      if (p == LocationPermission.denied) return NoLocation.refused;
      // ALWAYS vs WHILE IN USE is the distinction that decides whether this
      // module works at all. `whileInUse` fills the timeline while you are
      // looking at the phone and records nothing the moment it goes in a
      // pocket — which is every part of the day worth recording.
      if (background && p == LocationPermission.whileInUse) {
        return NoLocation.onlyWhileOpen;
      }
      return null;
    } catch (e) {
      debugPrint('[track] could not ask for location: $e');
      return NoLocation.turnedOff;
    }
  }

  @override
  Stream<Spot> watch() => Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: movedMetres,
          timeLimit: null,
        ),
      ).map(_spot);

  @override
  Future<Spot?> once() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 30)),
      );
      return _spot(p);
    } catch (e) {
      debugPrint('[track] no fix: $e');
      return null;
    }
  }

  Spot _spot(Position p) => Spot(
        at: p.timestamp,
        lat: p.latitude,
        lon: p.longitude,
        accuracy: p.accuracy,
        speed: p.speed,
      );
}

/// A phone for tests.
class FakePositions implements Positions {
  FakePositions({this.problem, List<Spot>? spots}) : _spots = spots ?? const [];

  final NoLocation? problem;
  final List<Spot> _spots;
  final _out = StreamController<Spot>.broadcast();

  bool watching = false;

  @override
  Future<NoLocation?> permission({required bool background}) async => problem;

  @override
  Stream<Spot> watch() {
    watching = true;
    for (final s in _spots) {
      _out.add(s);
    }
    return _out.stream;
  }

  @override
  Future<Spot?> once() async => _spots.isEmpty ? null : _spots.last;

  void moveTo(Spot s) => _out.add(s);

  void close() => _out.close();
}

// ================================================================ the switch

const _onKey = 'track.recording';

/// Recording, or not, and the reason if not.
class Recorder extends ChangeNotifier {
  // The lint wants `this._store`. Dart forbids a named parameter starting with
  // an underscore, so its suggestion does not compile — the same note
  // OfflineRecords and AutoSync carry.
  // ignore_for_file: prefer_initializing_formals
  Recorder({required OfflineStore store, Positions? positions})
      : _store = store,
        _positions = positions ?? PlatformPositions();

  final OfflineStore _store;
  final Positions _positions;

  final _battery = Battery();

  StreamSubscription<Spot>? _sub;
  bool _on = false;
  NoLocation? _problem;
  int _kept = 0;

  bool get recording => _on;
  NoLocation? get problem => _problem;

  /// How many fixes this run has kept. Shown on the screen so "it is recording"
  /// is a claim with a number behind it rather than a switch somebody has to
  /// take on faith.
  int get keptThisRun => _kept;

  /// Read the saved switch and start if it was on.
  ///
  /// Called from main.dart. Nothing here asks for a permission — a prompt at
  /// launch, before anybody has seen what the app does, is the one most often
  /// refused, and this app says so in three other places already.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_onKey) != true) return;
      await start(ask: false);
    } catch (e) {
      debugPrint('[track] could not restore: $e');
    }
  }

  Future<bool> start({bool ask = true}) async {
    final why = await _positions.permission(background: true);
    if (why != null) {
      // onlyWhileOpen is NOT a refusal to start. It is worth recording what can
      // be recorded — a timeline of the hours you had the phone open is still
      // better than nothing — as long as the screen says plainly that it stops
      // when the phone goes in a pocket.
      if (why != NoLocation.onlyWhileOpen) {
        _problem = why;
        _on = false;
        notifyListeners();
        return false;
      }
    }

    _problem = why;
    _on = true;
    _kept = 0;
    pausedForBattery = false;
    notifyListeners();

    await _sub?.cancel();
    _sub = _positions.watch().listen(_keep, onError: (Object e) {
      debugPrint('[track] stream stopped: $e');
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onKey, true);
    } catch (_) {/* it records either way this run */}
    return true;
  }

  /// Below this, recording stops until the phone is charged and reopened.
  ///
  /// Fifteen rather than five: at five the phone is about to die and whatever
  /// it was going to record is lost anyway, and the last fifteen per cent is
  /// what somebody needs to get home and make a call.
  static const _tooLow = 15;

  /// True when the module stopped itself rather than being switched off.
  ///
  /// The screen says which: "not recording" when somebody chose it, and a
  /// different line when the phone did — otherwise it looks like the switch
  /// failed.
  bool pausedForBattery = false;

  Future<void> _pauseForBattery() async {
    await _sub?.cancel();
    _sub = null;
    _on = false;
    pausedForBattery = true;
    notifyListeners();
    // The SAVED switch is deliberately left ON. This is a pause, not a
    // decision — the next launch on a charged phone picks it up again, and
    // somebody who turned it on should not have to remember to turn it back on
    // because their battery ran down once.
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _on = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onKey, false);
    } catch (_) {}
  }

  Future<void> _keep(Spot s) async {
    try {
      // THE CHARGE AT THE TIME, which the column has always had room for and
      // nothing ever filled. It is what answers "why is the afternoon
      // missing?" — a gap at 4% is a phone that died, a gap at 80% is
      // something else, and without the number both look identical a month
      // later.
      //
      // Best effort: a battery that will not answer must not lose the fix.
      int? charge;
      try {
        charge = await _battery.batteryLevel;
      } catch (_) {
        charge = null;
      }

      // AND IT STOPS ITSELF ON A DYING PHONE. A location stream is among the
      // most expensive things an app can hold open, and holding one at 5% to
      // record that somebody was at home is the worst trade in the app. It
      // resumes on its own: `restore()` runs at every launch and the switch is
      // still on, so plugging the phone in and opening SafeNest is all it takes.
      if (charge != null && charge <= _tooLow) {
        if (_on) {
          debugPrint('[track] paused at $charge% — the phone needs the power');
          await _pauseForBattery();
        }
        return;
      }

      final id = await _store.addFix(
        at: s.at,
        lat: s.lat,
        lon: s.lon,
        accuracy: s.accuracy,
        speed: s.speed,
        battery: charge,
      );
      if (id != null) {
        _kept++;
        notifyListeners();
      }
    } catch (e) {
      // A fix that cannot be written is a fix lost, and there is nothing useful
      // to do about it except not take the recorder down with it.
      debugPrint('[track] could not keep a fix: $e');
    }
  }

  /// Take one now, so turning the switch on puts something on the screen
  /// immediately instead of leaving a blank day until the phone next moves a
  /// hundred metres.
  Future<void> markNow() async {
    final s = await _positions.once();
    if (s != null) await _keep(s);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
