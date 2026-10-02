/// Turning speech into words, on the device.
///
/// WHY THIS WRAPPER EXISTS rather than calling the plugin from the screen.
///
/// Dictation fails in a dozen different ways — permission refused, no
/// recogniser installed, the language not downloaded, the microphone taken by
/// a call, the service dying mid-sentence — and every one of them arrives as a
/// different callback or a different error string. The screen's only sensible
/// reaction to all of them is the same: stop listening, say one plain sentence,
/// and leave the keyboard working. Collapsing them here keeps that decision in
/// one place instead of spreading platform error codes through the UI.
///
/// It is also what makes the screen testable. `Dictation` is an interface with
/// a fake beside it, so the thread and the confirm step can be driven in a
/// widget test without a microphone — which is the only way they will ever be
/// checked on this machine.
///
/// NOTHING LEAVES THE PHONE. `speech_to_text` uses the platform's own
/// recogniser, and on both platforms that can be made to run on-device. That
/// is not a detail: it is what lets this module keep the promise the sign-in
/// screen makes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// What the screen needs to know, and nothing else.
@immutable
class Heard {
  const Heard({required this.words, required this.settled});

  /// Everything recognised so far in this run.
  final String words;

  /// True once the recogniser has committed to these words rather than still
  /// revising them. A partial result that is shown as final is how dictation
  /// appears to lose the end of a sentence.
  final bool settled;
}

/// Why listening stopped, in the only terms the screen cares about.
enum DictationProblem {
  /// The person said no, or has not been asked yet and refused.
  notAllowed,

  /// The phone has no recogniser, or not for this language.
  unavailable,

  /// It started and then fell over — a call, the service dying, no network for
  /// a recogniser that wanted one.
  stopped,
}

abstract class Dictation {
  /// True if this phone can do it at all. Asked once, before the button is
  /// shown: offering a microphone that cannot work is worse than not offering
  /// one, because the failure arrives after somebody has spoken a paragraph.
  Future<bool> available();

  /// Start listening. [onHeard] fires as the words arrive; [onProblem] fires
  /// once, and listening has already stopped by the time it does.
  Future<void> start({
    required void Function(Heard) onHeard,
    required void Function(DictationProblem) onProblem,
  });

  Future<void> stop();

  /// Stop and throw away what was heard.
  Future<void> cancel();

  bool get listening;
}

class PlatformDictation implements Dictation {
  PlatformDictation({stt.SpeechToText? engine})
      : _engine = engine ?? stt.SpeechToText();

  final stt.SpeechToText _engine;
  bool _ready = false;
  void Function(DictationProblem)? _onProblem;

  @override
  bool get listening => _engine.isListening;

  @override
  Future<bool> available() async {
    if (_ready) return true;
    try {
      _ready = await _engine.initialize(
        // Both of these arrive for ordinary, expected situations — a pause in
        // speech ends a session — so neither is reported on its own. Only a
        // failure while the screen believes it is listening is worth a word to
        // anybody, and that is decided in start().
        onError: (e) => _fail(e.permanent
            ? DictationProblem.unavailable
            : DictationProblem.stopped),
        onStatus: (_) {},
      );
      return _ready;
    } catch (_) {
      // A plugin missing entirely — the web build, a stripped platform. Not an
      // error state: the phone simply cannot do this, and the keyboard still
      // can.
      return false;
    }
  }

  void _fail(DictationProblem p) {
    final f = _onProblem;
    _onProblem = null;   // once, never twice for one run
    f?.call(p);
  }

  @override
  Future<void> start({
    required void Function(Heard) onHeard,
    required void Function(DictationProblem) onProblem,
  }) async {
    _onProblem = onProblem;
    if (!await available()) {
      _fail(DictationProblem.unavailable);
      return;
    }
    if (!await _engine.hasPermission) {
      _fail(DictationProblem.notAllowed);
      return;
    }
    try {
      await _engine.listen(
        onResult: (r) => onHeard(
            Heard(words: r.recognizedWords, settled: r.finalResult)),
        listenOptions: stt.SpeechListenOptions(
          // ON THE DEVICE where the phone can. The whole module is built on
          // nothing leaving the machine, and a recogniser that quietly posts
          // the audio to a server would undo that without anybody seeing it.
          onDevice: true,
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          // Long enough for somebody to think mid-sentence. The default is a
          // couple of seconds, which cuts people off while they are
          // remembering — which is the whole activity here.
          pauseFor: const Duration(seconds: 4),
          listenFor: const Duration(minutes: 5),
        ),
      );
    } catch (_) {
      _fail(DictationProblem.stopped);
    }
  }

  @override
  Future<void> stop() async {
    _onProblem = null;
    try {
      await _engine.stop();
    } catch (_) {
      // Stopping something already stopped is not worth a message.
    }
  }

  @override
  Future<void> cancel() async {
    _onProblem = null;
    try {
      await _engine.cancel();
    } catch (_) {}
  }
}

/// A microphone for tests: hand it the words and it delivers them.
///
/// It exists so the screens can be driven on a machine with no phone attached,
/// which is every machine this app is developed on.
class FakeDictation implements Dictation {
  FakeDictation({this.canListen = true, this.problem});

  final bool canListen;

  /// Set to make `start` fail that way instead of hearing anything.
  final DictationProblem? problem;

  bool _listening = false;
  void Function(Heard)? _onHeard;

  @override
  bool get listening => _listening;

  @override
  Future<bool> available() async => canListen;

  @override
  Future<void> start({
    required void Function(Heard) onHeard,
    required void Function(DictationProblem) onProblem,
  }) async {
    if (!canListen) {
      onProblem(DictationProblem.unavailable);
      return;
    }
    if (problem != null) {
      onProblem(problem!);
      return;
    }
    _listening = true;
    _onHeard = onHeard;
  }

  /// Pretend somebody spoke.
  void say(String words, {bool settled = false}) =>
      _onHeard?.call(Heard(words: words, settled: settled));

  @override
  Future<void> stop() async => _listening = false;

  @override
  Future<void> cancel() async {
    _listening = false;
    _onHeard = null;
  }
}
