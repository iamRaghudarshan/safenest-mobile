/// Life Memory — tell it something, and it keeps it.
///
/// The thread reads like a conversation because that is how it was asked for,
/// but nothing replies: the entries are CARDS rather than chat bubbles,
/// because a card can carry a photograph and a row of facts and a bubble
/// cannot.
///
/// Three things shape this screen:
///
///   * SPEAKING IS THE MAIN ACTION, so the microphone is the largest control
///     and the keyboard is the smaller sibling beside it — not a toolbar
///     button somebody has to find.
///   * THE FACTS ARE OFFERED, NEVER TAKEN. What the reader found appears as
///     chips you tap to keep. Nothing is filed silently, because a store that
///     quietly decides what you meant is one you stop trusting the first time
///     it is wrong, and it will be wrong.
///   * IT IS WRITTEN TO THIS PHONE AND SHOWN AT ONCE. No spinner, no round
///     trip. Most of what anybody says to this will be said with no signal.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../memory/attach.dart';
import '../memory/dictation.dart';
import '../memory/facts.dart';
import '../memory/reminders.dart';
import '../offline/store.dart';
import '../theme.dart';
import 'memory_ask_screen.dart';
import 'memory_search_screen.dart';

const kMemoryTint = Color(0xFF6B3C8C);

class LifeMemoryScreen extends StatefulWidget {
  const LifeMemoryScreen({
    super.key,
    this.dictation,
    this.photos,
    this.embedded = false,
    this.debugRows,
    this.onKept,
  });

  /// Supplied by tests. The real ones need a microphone and a camera roll, and
  /// no machine this is developed on has either.
  final Dictation? dictation;
  final PhotoSource? photos;

  /// The thread to draw instead of reading one, and a hook on what would be
  /// saved. Both exist for the same reason, and it is worth writing down.
  ///
  /// `testWidgets` runs in a zone with a fake clock where real file IO
  /// callbacks are never delivered, so a screen that opens a database in
  /// `initState` never gets past its spinner and the test hangs rather than
  /// failing. The database is covered on its own, against real SQLite, in
  /// memory_store_test.dart; what is left to check here is the FLOW — what is
  /// offered, what is pre-ticked, what a tap changes — and these two let that
  /// be checked without a disk.
  ///
  /// The same door `VividHome.debugData` and `BackupScreen.debugProgress`
  /// already use.
  final List<Map<String, dynamic>>? debugRows;
  final void Function(
          String words, bool spoken, List<Fact> kept, String? photoPath)?
      onKept;

  /// True when this IS a tab rather than a screen pushed on top of one — a tab
  /// with a back arrow is a tab that looks broken.
  final bool embedded;

  @override
  State<LifeMemoryScreen> createState() => _LifeMemoryScreenState();
}

class _LifeMemoryScreenState extends State<LifeMemoryScreen> {
  late final Dictation _mic = widget.dictation ?? PlatformDictation();
  late final PhotoSource _photos = widget.photos ?? PlatformPhotos();
  final _typed = TextEditingController();
  final _scroll = ScrollController();

  /// A photograph chosen BEFORE the words, which is the order people do it in:
  /// you find the picture, and then you say why it matters. It is already
  /// copied into the app's folder by the time it lands here — see
  /// adoptMemoryPhoto — so nothing depends on the camera roll afterwards.
  String? _pendingPhoto;

  /// And WHICH picture in the camera roll it was a copy of.
  ///
  /// Kept as well as the path, not instead of it. The path is what this phone
  /// draws and it is the only reliable one — a library reference is not a
  /// promise. The asset id is what lets the COMPUTER'S copy of this memory find
  /// the same photograph once the ordinary photo backup has sent it, since the
  /// memory itself travels as words and tags. Dropping it, as the first cut did,
  /// means the laptop can never show the picture at all.
  String? _pendingAsset;

  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  bool _canSpeak = false;
  bool _listening = false;
  String _heard = '';
  String? _trouble;

  @override
  void initState() {
    super.initState();
    if (widget.debugRows != null) {
      _rows = widget.debugRows!;
      _loading = false;
    } else {
      _load();
    }
    _mic.available().then((ok) {
      if (mounted) setState(() => _canSpeak = ok);
    });
  }

  @override
  void dispose() {
    _typed.dispose();
    _scroll.dispose();
    // Letting a recogniser run on after the screen is gone holds the
    // microphone open, which on a phone shows as a permanent recording dot.
    unawaited(_mic.cancel());
    super.dispose();
  }

  OfflineStore get _store => context.read<OfflineStore>();

  Future<void> _load() async {
    try {
      final rows = await _store.memories();
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ----------------------------------------------------------- speaking

  Future<void> _startListening() async {
    setState(() {
      _listening = true;
      _heard = '';
      _trouble = null;
    });
    await _mic.start(
      onHeard: (h) {
        if (mounted) setState(() => _heard = h.words);
      },
      onProblem: (p) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _trouble = switch (p) {
            DictationProblem.notAllowed =>
              'SafeNest has not been allowed to use the microphone. You can '
                  'still type.',
            DictationProblem.unavailable =>
              'This phone cannot turn speech into words. You can still type.',
            DictationProblem.stopped =>
              'The microphone stopped. What you had said is kept below.',
          };
        });
      },
    );
  }

  Future<void> _stopListening() async {
    await _mic.stop();
    if (!mounted) return;
    final words = _heard.trim();
    setState(() => _listening = false);
    if (words.isEmpty) return;
    await _offerFacts(words, spoken: true);
  }

  Future<void> _sendTyped() async {
    final words = _typed.text.trim();
    if (words.isEmpty) return;
    _typed.clear();
    await _offerFacts(words, spoken: false);
  }

  /// The confirm step. Everything the reader found is shown, nothing is kept
  /// until it is tapped, and the words are saved whatever happens to the chips.
  Future<void> _offerFacts(String words, {required bool spoken}) async {
    final said = DateTime.now();
    final found = readFacts(words, said);

    final keep = <Fact>{
      // An expiry is pre-ticked and the rest are not. It is the only kind that
      // becomes a reminder, so it is the one worth a glance — and the one
      // somebody is most annoyed to have missed.
      ...found.where((f) => f.kind == FactKind.expiry),
    };

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ConfirmSheet(
        words: words,
        found: found,
        keep: keep,
        photo: _pendingPhoto,
      ),
    );
    if (saved != true || !mounted) return;

    final photo = _pendingPhoto;
    final asset = _pendingAsset;
    final watcher = widget.onKept;
    if (watcher != null) {
      watcher(words, spoken, keep.toList(), photo);
      if (widget.debugRows != null) {
        setState(() {
          _pendingPhoto = null;
          _pendingAsset = null;
        });
        return;
      }
    }

    await _store.addMemory(
      body: words,
      saidAt: said,
      spoken: spoken,
      photoId: asset,
      photoPath: photo,
      facts: [
        for (final f in keep)
          (kind: f.kind.name, value: f.value, at: f.at),
      ],
    );
    if (mounted) {
      setState(() {
        _pendingPhoto = null;
        _pendingAsset = null;
      });
    }
    await _load();
    _toBottom();

    // THE DATE BECOMES A NOTIFICATION, and this is the only moment it can. A
    // warranty confirmed and never scheduled is the whole feature missing, and
    // it would not be noticed for two years. Re-scheduling the lot rather than
    // just this one keeps the alarm queue a function of the database — ids are
    // stable, so a warning already set is moved, never duplicated.
    if (keep.any((f) => f.at != null)) {
      unawaited(scheduleMemoryReminders(_store).catchError((e) {
        debugPrint('[memory] could not schedule warnings: $e');
        return 0;
      }));
    }
  }

  // ------------------------------------------------------------ the photo

  Future<void> _attach() async {
    final allowed = await _photos.allowed();
    if (!mounted) return;
    if (!allowed) {
      setState(() => _trouble =
          'SafeNest has not been allowed to see your photographs. You can '
          'still keep this without one.');
      return;
    }
    final snaps = await _photos.recent();
    if (!mounted) return;
    if (snaps.isEmpty) {
      setState(() => _trouble = 'No photographs found on this phone.');
      return;
    }

    final chosen = await showModalBottomSheet<Snap>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PhotoSheet(snaps: snaps),
    );
    if (chosen == null || !mounted) return;

    // COPIED NOW, not at save time. A picture still in iCloud cannot be
    // produced at all, and finding that out while saving would lose the words
    // somebody had just finished speaking.
    final path = await chosen.copy();
    if (!mounted) return;
    if (path == null) {
      setState(() => _trouble =
          'That photograph could not be read — it may not be downloaded to '
          'this phone yet.');
      return;
    }
    setState(() {
      _pendingPhoto = path;
      _pendingAsset = chosen.id;
      _trouble = null;
    });
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
      }
    });
  }

  // ------------------------------------------------------------- drawing

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        backgroundColor: kMemoryTint,
        foregroundColor: Colors.white,
        title: const Text('Life Memory'),
        actions: [
          // ASK AND FIND ARE BOTH HERE, and they are not the same thing.
          // Finding returns the memories that contain a word, which is what you
          // want when you remember saying something. Asking returns a sentence
          // worked out from them, which is what you want when you have
          // forgotten. Collapsing the two would lose whichever was collapsed
          // into the other.
          IconButton(
            tooltip: 'Ask a question',
            onPressed: _rows.isEmpty ? null : _ask,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'Find something',
            onPressed: _rows.isEmpty ? null : _search,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: Column(children: [
        if (_trouble != null)
          Container(
            width: double.infinity,
            color: kWarn.withValues(alpha: 0.16),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(_trouble!,
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? _Empty(canSpeak: _canSpeak)
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) => _MemoryCard(row: _rows[i]),
                    ),
        ),
        if (_listening) _Listening(heard: _heard),
        _Composer(
          typed: _typed,
          canSpeak: _canSpeak,
          listening: _listening,
          photo: _pendingPhoto,
          onSend: _sendTyped,
          onSpeak: _startListening,
          onStop: _stopListening,
          onAttach: _attach,
          onDropPhoto: () => setState(() {
            _pendingPhoto = null;
            _pendingAsset = null;
          }),
          theme: theme,
        ),
      ]),
    );
  }

  Future<void> _ask() async {
    final store = _store;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MemoryAskScreen(
        look: (terms) => store.memoriesMatchingAny(terms),
      ),
    ));
  }

  Future<void> _search() async {
    // A SCREEN, NOT A SHEET any more. A sheet is right for something you glance
    // at and dismiss; searching is something you narrow, refine and scroll, and
    // half the height went to the keyboard. It also needs an app bar for the
    // field and a row for the filters, neither of which fits above a list in a
    // sheet.
    final store = _store;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MemorySearchScreen(
        look: (terms) => store.memoriesMatchingAny(terms),
        // Typing a question into a search box is common and the answer is one
        // tap away rather than somewhere else in the app.
        onAsk: (question) => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MemoryAskScreen(
              look: (terms) => store.memoriesMatchingAny(terms),
              debugQuestion: question,
            ),
          ),
        ),
      ),
    ));
  }
}

// =============================================================== pieces

class _Empty extends StatelessWidget {
  const _Empty({required this.canSpeak});
  final bool canSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kMemoryTint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.auto_stories_outlined,
                size: 30, color: kMemoryTint),
          ),
          const SizedBox(height: 16),
          Text('Nothing yet',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(
              canSpeak
                  ? 'Hold the microphone and say anything worth keeping — '
                      'where something was bought, what somebody told you, '
                      'why a photograph matters.'
                  : 'Type anything worth keeping — where something was '
                      'bought, what somebody told you, why a photograph '
                      'matters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _Listening extends StatelessWidget {
  const _Listening({required this.heard});
  final String heard;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: kMemoryTint.withValues(alpha: 0.08),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: Color(0xFFE05A5A), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                heard.isEmpty ? 'Listening…' : heard,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    fontStyle: heard.isEmpty ? FontStyle.italic : null,
                    color: heard.isEmpty ? Colors.black54 : Colors.black87)),
          ),
        ]),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.typed,
    required this.canSpeak,
    required this.listening,
    required this.photo,
    required this.onSend,
    required this.onSpeak,
    required this.onStop,
    required this.onAttach,
    required this.onDropPhoto,
    required this.theme,
  });

  final TextEditingController typed;
  final bool canSpeak;
  final bool listening;
  final String? photo;
  final VoidCallback onSend;
  final VoidCallback onSpeak;
  final VoidCallback onStop;
  final VoidCallback onAttach;
  final VoidCallback onDropPhoto;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // THE PICTURE WAITING FOR ITS WORDS. Shown above the box rather
            // than as an icon that has merely gone darker, because somebody
            // who attaches a photograph and then speaks for a minute needs to
            // be able to see, the whole time, that it is still going on this
            // one.
            if (photo != null) _Pending(path: photo!, onDrop: onDropPhoto),
            Row(children: [
              _Attach(onTap: onAttach, theme: theme),
              const SizedBox(width: 8),
              Expanded(
              child: TextField(
                controller: typed,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: canSpeak ? 'or type it' : 'type something to keep',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22)),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 10),
            // LISTENING TO THE CONTROLLER, not reading it once. This is a
            // StatelessWidget, so without the builder it is drawn when the
            // screen rebuilds and not when the text changes — type something
            // and the send button never appears, leaving no way at all to send
            // what you typed. Caught by a test; it would have shipped.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: typed,
              builder: (_, value, _) {
                final hasWords = value.text.trim().isNotEmpty;
                if (hasWords || !canSpeak) {
                  return _Round(
                    tooltip: 'Keep this',
                    icon: Icons.arrow_upward,
                    onTap: onSend,
                  );
                }
                // ONE BUTTON, two states. A separate stop button appearing
                // beside the microphone is a second thing to aim at while
                // talking, and the thumb is already where it started.
                return _Round(
                  tooltip: listening ? 'Done speaking' : 'Speak',
                  icon: listening ? Icons.stop : Icons.mic,
                  big: true,
                  onTap: listening ? onStop : onSpeak,
                );
              },
            ),
            ]),
          ]),
        ),
      );
}

/// The photograph chosen but not yet kept.
class _Pending extends StatelessWidget {
  const _Pending({required this.path, required this.onDrop});
  final String path;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(path),
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              // A thumbnail that cannot be drawn must not take the composer
              // down with it — the words are the thing being kept.
              errorBuilder: (_, _, _) => Container(
                    width: 44,
                    height: 44,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_not_supported_outlined,
                        size: 18),
                  )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Going on this one — now say where it was taken, or why '
              'it matters.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: theme.colorScheme.onSurfaceVariant)),
        ),
        IconButton(
          tooltip: 'Not this one',
          visualDensity: VisualDensity.compact,
          onPressed: onDrop,
          icon: const Icon(Icons.close, size: 18),
        ),
      ]),
    );
  }
}

class _Attach extends StatelessWidget {
  const _Attach({required this.onTap, required this.theme});
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Attach a photograph',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kMemoryTint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.add_photo_alternate_outlined,
                size: 21, color: kMemoryTint),
          ),
        ),
      );
}

/// Recent photographs, to pick one from.
///
/// Recent and nothing else — no albums, no search. A photograph somebody is
/// attaching to something they are saying NOW is nearly always one they just
/// took, and a full picker in front of that is three taps nobody needed.
class _PhotoSheet extends StatelessWidget {
  const _PhotoSheet({required this.snaps});
  final List<Snap> snaps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Recent photographs',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 7,
                crossAxisSpacing: 7,
              ),
              itemCount: snaps.length,
              itemBuilder: (_, i) => _SnapTile(
                snap: snaps[i],
                onTap: () => Navigator.pop(context, snaps[i]),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text('A copy is kept with the memory, so deleting it from your '
              'photographs later will not empty this.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _SnapTile extends StatelessWidget {
  const _SnapTile({required this.snap, required this.onTap});
  final Snap snap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: FutureBuilder<List<int>?>(
          future: snap.thumb(),
          builder: (_, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.image_outlined, size: 20),
              );
            }
            return Image.memory(Uint8List.fromList(bytes),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                    color: theme.colorScheme.surfaceContainerHighest));
          },
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.big = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final d = big ? 54.0 : 44.0;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(d / 2),
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              color: kMemoryTint,
              borderRadius: BorderRadius.circular(d / 2),
              boxShadow: big
                  ? [
                      BoxShadow(
                          color: kMemoryTint.withValues(alpha: 0.38),
                          blurRadius: 14,
                          offset: const Offset(0, 5)),
                    ]
                  : null,
            ),
            child: Icon(icon, color: Colors.white, size: big ? 25 : 20),
          ),
        ),
      ),
    );
  }
}

/// One memory in the thread.
class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = (row['facts'] as List?) ?? const [];
    final photo = row['photo_path'] as String?;
    final onComputer = row['server_id'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (photo != null && photo.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.file(File(photo),
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
            const SizedBox(width: 11),
          ],
          Expanded(
            child: Text('${row['body']}',
                style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ),
        ]),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in facts) _Chip(kind: '${f['kind']}', value: '${f['value']}'),
          ]),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Text(_when(row['said_at'] as String?),
              style: TextStyle(
                  fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
          if (row['spoken'] == 1) ...[
            const SizedBox(width: 7),
            Icon(Icons.mic, size: 12, color: theme.colorScheme.onSurfaceVariant),
          ],
          const Spacer(),
          // THE ONLY THING SYNC CHANGES on this card. Everything else is
          // already true the moment it is said.
          Icon(onComputer ? Icons.cloud_done_outlined : Icons.schedule,
              size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(onComputer ? 'on your computer' : 'on this phone',
              style: TextStyle(
                  fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}

/// The tint per kind. Different kinds do different things — only an expiry
/// becomes a reminder — so they are told apart by colour AND by the words in
/// them, never by colour alone.
({Color ink, Color back}) chipColours(String kind) => switch (kind) {
      'expiry' || 'date' => (ink: const Color(0xFF7A3D12), back: const Color(0xFFFBEBD9)),
      'place' || 'shop' => (ink: const Color(0xFF1F4D6B), back: const Color(0xFFDEEAF2)),
      'amount' => (ink: const Color(0xFF14543A), back: const Color(0xFFDCF0E5)),
      _ => (ink: const Color(0xFF4A3268), back: const Color(0xFFEBE3F4)),
    };

class _Chip extends StatelessWidget {
  const _Chip({required this.kind, required this.value});
  final String kind;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = chipColours(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: c.back, borderRadius: BorderRadius.circular(13)),
      child: Text(value,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: c.ink)),
    );
  }
}

String _when(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month - 1]}'
      '${d.year == now.year ? '' : ' ${d.year}'}';
}

// ======================================================== confirm sheet

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({
    required this.words,
    required this.found,
    required this.keep,
    this.photo,
  });

  final String words;
  final List<Fact> found;
  final Set<Fact> keep;
  final String? photo;

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Before it saves',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // The photograph is shown HERE as well as above the composer,
              // because this sheet is the last chance to notice it went on the
              // wrong memory — and a mis-attached picture is the one mistake
              // here that cannot be fixed by editing the words afterwards.
              if (widget.photo != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.file(File(widget.photo!),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Text(widget.words,
                    style: const TextStyle(fontSize: 14, height: 1.55)),
              ),
            ]),
          ),
          if (widget.found.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text('WHAT IT THINKS IT HEARD',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
              Text('tap to keep',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 9),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in widget.found)
                    _Offered(
                      fact: f,
                      chosen: widget.keep.contains(f),
                      onTap: () => setState(() {
                        widget.keep.contains(f)
                            ? widget.keep.remove(f)
                            : widget.keep.add(f);
                      }),
                    ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Nothing to tag in this one — it is kept as you said it, and '
                  'it will still be found by searching.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Keep this'),
            ),
          ),
          const SizedBox(height: 7),
          Text('Saved on this phone straight away.',
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _Offered extends StatelessWidget {
  const _Offered({
    required this.fact,
    required this.chosen,
    required this.onTap,
  });

  final Fact fact;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = chipColours(fact.kind.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: chosen ? c.ink : theme.colorScheme.outlineVariant,
                width: chosen ? 1.5 : 1),
          ),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: c.back, borderRadius: BorderRadius.circular(9)),
              child: Icon(_glyph(fact.kind), size: 16, color: c.ink),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fact.value,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    // THE WORDS IT CAME FROM. A suggestion somebody cannot
                    // judge is one they have to trust, and trusting it is
                    // exactly what this screen exists to avoid.
                    Text('from “${fact.because}”',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ]),
            ),
            const SizedBox(width: 8),
            Icon(chosen ? Icons.check_circle : Icons.circle_outlined,
                size: 21,
                color: chosen ? c.ink : theme.colorScheme.outlineVariant),
          ]),
        ),
      ),
    );
  }

  IconData _glyph(FactKind k) => switch (k) {
        FactKind.expiry || FactKind.date => Icons.schedule,
        FactKind.place => Icons.place_outlined,
        FactKind.shop => Icons.storefront_outlined,
        FactKind.amount => Icons.currency_rupee,
        _ => Icons.sell_outlined,
      };
}
