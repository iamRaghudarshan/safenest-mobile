/// One button. This is the screen the whole application was built for.
///
/// Everything the web app could not do is here: no picker, no selecting, no
/// fifty at a time. The app reads the library directly and sends what is not
/// already on the computer.
///
/// It does NOT start on its own. An app that copies somebody's entire camera
/// roll the moment it is opened is exactly what people are right to distrust,
/// and this product's whole argument is that it is not that. The owner presses
/// the button and can stop it at any point — stopping loses nothing, because
/// what has already been sent is remembered.
///
/// There is no scheduling. This line used to say "or schedules it", and no such
/// thing exists anywhere in the app: a photo taken today is backed up only when
/// somebody next opens this screen and taps. That is the single largest gap
/// between this and any phone backup people have used before.
///
/// WHAT THIS SCREEN OWES THE PERSON, and did not pay
/// The engine can now say WHY a run failed — an expired session, a lapsed
/// licence, a sleeping laptop, photos still in iCloud. This screen showed one
/// undifferentiated line of grey text, and a bare "N could not be read" that was
/// wrong twice over: the photos read perfectly, and the upload was what failed.
/// A backup screen that cannot distinguish "done" from "nothing worked" is
/// worse than no screen, because it is the one thing here that says your photos
/// are safe.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../backup.dart';
import '../offline/store.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/backup_blocked_banner.dart';
import '../widgets/auto_backup_card.dart';
import '../widgets/backup_flight.dart';
import '../widgets/brand_button.dart';
import '../widgets/pill.dart';
import '../widgets/uploading_now.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.debugProgress, this.service});

  /// For tests — render a given state without a photo library or a server.
  final BackupProgress? debugProgress;

  /// A shared service (owned by the gallery) so its status strip and this screen
  /// show ONE run. When null this screen owns its own service, exactly as before.
  final BackupService? service;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

/// A byte count as somebody would say it. Big files are the whole reason
/// this line exists, so MB and GB are what it deals in.
String _mb(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).round()} KB';
}

/// A count with its thousands grouped — `1,048`, not `1048`.
///
/// A phone library is four and five digits, and an ungrouped run of them is
/// the difference between a number somebody reads and a number they skim past.
/// Grouped by hand rather than through `intl`: the app carries no locale
/// formatting anywhere else, and one comma is not worth a dependency.
String _n(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// What to say about a phone count and a computer count that differ.
///
/// Null when there is nothing worth saying — either a number is missing, or
/// they agree. A row that appears only to announce that two numbers match is
/// noise, and noise is what makes people stop reading the rows that matter.
///
/// THE DIFFERENCE IS USUALLY CORRECT, which is the whole reason this needs a
/// sentence rather than just two figures. The phone counts ASSETS; the
/// computer stores DISTINCT CONTENT. A picture that exists twice on the
/// phone — a shared copy, a re-saved image, the same photo out of two apps —
/// is one item on the computer, for ever, by design. Shown as bare numbers
/// with no explanation, "1,948" against "1,773" reads as 175 lost
/// photographs, and that is the opposite of true.
///
/// Pure, and separated from the widget, because it is the kind of wording
/// that is easy to get subtly wrong — "missing" when it means "de-duplicated"
/// — and a test can hold it to the honest version.
String? tallyNote(int? phone, int? computer, {int failed = 0}) {
  if (phone == null || computer == null) return null;
  if (phone <= 0) return null;
  final gap = phone - computer;
  if (gap == 0) return 'Everything on this phone is on your computer.';
  if (gap < 0) {
    // The computer legitimately holds MORE: photos from the web, from another
    // phone, or ones since deleted here. Not a fault, and not this screen's
    // business to fret about.
    return 'Your computer also holds ${_plural(-gap, 'item')} from elsewhere.';
  }
  if (failed >= gap) {
    // The whole difference is accounted for by this run's failures, which are
    // listed underneath. Do not also blame duplicates.
    return 'The difference is the ${_plural(gap, 'item')} that could not be '
        'sent, listed below.';
  }
  final dupes = gap - failed;
  if (failed > 0) {
    return '${_plural(failed, 'item')} could not be sent. The other '
        '${_plural(dupes, 'is a copy', plural: 'are copies')} of something '
        'already there — the computer keeps one of each.';
  }
  return '${_plural(dupes, 'is a copy', plural: 'are copies')} of something '
      'already there — the computer keeps one of each, so this is expected.';
}

String _plural(int n, String one, {String? plural}) {
  final word = n == 1 ? one : (plural ?? '${one}s');
  return '${_n(n)} $word';
}

/// The hero's headline: the words, how big, and how many lines they may use.
///
/// A FIGURE AND A SENTENCE ARE NOT THE SAME KIND OF HEADLINE, and treating
/// them as one is what went wrong. "132 uploaded" is a number and wants to be
/// large — that is the whole design of this block. "Looking for your
/// computer…" is a sentence that happens to occupy the same slot, and at 34pt
/// on one line it rendered as "Looking for your com…": the app's most
/// reassuring moment, cut off mid-word.
///
/// So the size follows the CONTENT rather than the position. Sentences are
/// set at reading size and given room to wrap; only an actual count gets the
/// big type.
({String text, double size, int lines}) heroTitle(BackupProgress p) {
  if (p.state == BackupState.scanning) {
    // Never a figure — there is nothing counted yet, which is exactly why
    // this state exists.
    return (
      text: p.message.isEmpty ? 'Looking for your computer…' : p.message,
      size: 19,
      lines: 2,
    );
  }
  if (p.state == BackupState.failed && p.done == 0) {
    return (text: 'Nothing was sent', size: 24, lines: 2);
  }
  return (text: '${_n(p.done)} uploaded', size: 34, lines: 1);
}

/// Whether a run has ended with something worth stating in the hero.
///
/// Idle is deliberately excluded: before anybody has pressed the button there
/// is no outcome, and a block reading "0 uploaded" on a fresh install is a
/// reproach rather than a status.
bool _hasOutcome(BackupProgress p) =>
    (p.state == BackupState.done ||
        p.state == BackupState.paused ||
        p.state == BackupState.failed) &&
    (p.total > 0 || p.message.isNotEmpty);

/// The line under the big figure, or null when there is nothing to add.
///
/// Three different jobs, which is why it is a function rather than an
/// expression buried in the tree: while running it is progress, after a
/// failure it is the REASON, and after a finished run it is the breakdown
/// that used to live in pills on a separate card.
String? _heroSubtitle(BackupProgress p, {required bool running}) {
  if (running) {
    if (p.total == 0 || p.state == BackupState.scanning) return null;
    return '${_n(p.handled)} of ${_n(p.total)} checked'
        '${p.skipped > 0 ? ' · ${_n(p.skipped)} already there' : ''}';
  }
  // A failure's message is the only thing on the screen that says what to go
  // and do, so it outranks the arithmetic.
  if (p.state == BackupState.failed) {
    return p.message.isEmpty ? null : p.message;
  }
  if (p.total == 0) return p.message.isEmpty ? null : p.message;
  return '${_n(p.total)} checked'
      '${p.skipped > 0 ? ' · ${_n(p.skipped)} already there' : ''}'
      '${p.failed > 0 ? ' · ${_n(p.failed)} could not be sent' : ''}';
}

class _BackupScreenState extends State<BackupScreen> {
  BackupService? _service;
  bool _owns = false;   // only stop a service we created — a shared one keeps going

  /// Decoded thumbnails of whatever is in flight, shared by the strip and
  /// the flight animation. One cache, because both want the same pictures
  /// and decoding them twice several times a second would be the reason the
  /// backup screen made the backup slower.
  final ThumbCache _thumbs = ThumbCache();

  @override
  void initState() {
    super.initState();
    if (widget.debugProgress != null) return;
    // The ledger is what makes a repeat backup fast -- without it the
    // service falls back to hashing the whole library to ask what is
    // already there. Passing it is not optional in the real app.
    final s = widget.service ??
        BackupService(context.read<Session>().api,
            ledger: context.read<OfflineStore>());
    _owns = widget.service == null;
    s.addListener(_onChange);
    if (_owns) s.load();
    _service = s;
    // Ask both sides how many they hold, so the comparison is on screen
    // BEFORE a button is pressed — which is when somebody is standing there
    // wondering whether the backup worked, not after starting another run to
    // find out. Unawaited: it is two cheap lookups and the screen is useful
    // without them, so nothing should wait on it.
    if (s.progress.state != BackupState.running) unawaited(s.refreshCounts());
  }

  void _onChange() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    // Native image memory: a ui.Image is not something the garbage collector
    // hurries over.
    _thumbs.dispose();
    _service?.removeListener(_onChange);
    if (_owns) _service?.stop();   // a shared service must survive for the gallery
    super.dispose();
  }

  BackupProgress get _p => widget.debugProgress ?? _service!.progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final p = _p;
    final running =
        p.state == BackupState.running || p.state == BackupState.scanning;
    final failed = p.state == BackupState.failed;
    final done = p.state == BackupState.done;

    // The hero colour IS the status. Gallery pink at rest, green when a run
    // finished, red when one did not — readable across the room, which is where
    // a phone sits while it uploads twenty thousand photos.
    final accent = failed
        ? kDanger
        : done
            ? kOk
            : kModuleColours['gallery']!;

    return Scaffold(
      appBar: AppBar(title: const Text('Back up this phone')),
      // ONE PAGE. Everything about the run on screen at once, no scrolling.
      //
      // It was a ListView, so the live figures sat wherever the content above
      // them happened to end and a long day's copy pushed them under the fold.
      // A screen somebody checks at a glance should not need a gesture first.
      //
      // Not a bare Column, though. "Fits" is a claim about a device, a text
      // size and a language, and it is false on some combination of the three
      // — an iPhone SE at the largest accessibility size is not going to hold
      // this however it is arranged. So: fill the viewport and lay out to it,
      // and let it scroll only when it genuinely cannot. On a normal phone
      // there is nothing to scroll, which is what was asked for; on a small
      // one it degrades instead of clipping, which is what a fixed height
      // would have done.
      body: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            // IntrinsicHeight so the Spacer below has a height to divide.
            // Inside a scroll view the column's height is unbounded, and a
            // flex child of an unbounded column is an assertion rather than a
            // layout.
            child: IntrinsicHeight(
              child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          // Repeated here as well as on the gallery: this is the screen
          // somebody opens when they have noticed nothing is happening.
          const BackupBlockedBanner(),
          // CENTRED WHEN THERE IS LITTLE TO SAY.
          //
          // A finished run with nothing wrong is one block and one button,
          // and pinned to the top that left most of a phone screen blank
          // underneath — which reads as a page that stopped loading rather
          // than as "it worked". A second flexible gap above the content
          // splits the slack with the one below it, so the block sits in the
          // middle of the screen and the whole thing looks composed.
          //
          // Only when it IS sparse. With a failures panel or a run in flight
          // there is enough on the page to fill it, and a leading gap would
          // just push the hero away from the top for no reason.
          if (!running && !_hasFailures(p)) const Spacer(),
          // THE BADGE AND THE PITCH ARE THE IDLE STATE.
          //
          // While a run is going they are decoration above the only thing
          // anybody is looking at, and together they pushed the live numbers
          // most of the way down the screen — on a 390pt phone the bar started
          // below the fold. A screen that is DOING something leads with what
          // it is doing.
          // ...AND NOT AFTER A RUN EITHER. "Every photo on this phone,
          // copied to your own computer. No choosing, no batches..." is a
          // pitch: it belongs on the screen of somebody deciding whether to
          // start, not on the screen of somebody reading what just happened.
          // Left in, it pushed the finished state 57 pixels past the bottom
          // of an iPhone — measured, because a screenshot at a generous
          // height had made it look fine.
          if (!running && !done && !failed) ...[
          // No badge. The hero below is the coloured block now, and
          // two saturated slabs stacked in a column is a pile rather
          // than a hierarchy — the eye has nowhere to land first.
          const SizedBox(height: 20),
          Text(
            'Every photo on this phone, copied to your own computer.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.38),
          ),
          const SizedBox(height: 8),
          Text(
            'No choosing, no batches. Photos already there are skipped, so you '
            'can run this as often as you like.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: theme.colorScheme.onSurfaceVariant),
          ),

          ],

          // Two named devices with photos travelling between them. The bar says
          // how far along it is; this says where the photos are going, which is
          // the thing people actually wanted reassuring about — the whole point
          // of this app is that they go to YOUR computer and nowhere else, and
          // a progress bar cannot say that.
          //
          // Only animates while something is moving. A loop that carries on
          // after a finished run tells someone to keep waiting.
          // It flies the REAL photographs now. ListenableBuilder because the
          // thumbnails arrive one at a time, off the photo library, after the
          // upload has already started.
          //
          // THE HERO. One deep block that owns the screen.
          //
          // The parts were all correct and the screen still read as timid: a
          // drawing, then a number, then a bar, then some chips, each on the
          // same flat white, none of them claiming to be the point. A screen
          // that is protecting twenty thousand photographs should look certain
          // of itself.
          //
          // So the animation and the figures are one saturated card, white
          // type on the module's own colour, and everything else on the page
          // is quiet underneath it. The colour carries the state as well —
          // brand while working, green when it finished, red when it did not
          // — which is legible from across a room, and across a room is where
          // a phone sits during a long backup.
          Container(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(accent, Colors.white, 0.08)!,
                  Color.lerp(accent, Colors.black, 0.30)!,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: dark ? 0.30 : 0.36),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListenableBuilder(
                  listenable: _thumbs,
                  builder: (_, _) => BackupFlight(
                    running: running,
                    done: done,
                    // Lit once something has actually arrived. A failed run
                    // that sent nothing gets an empty computer, which is the
                    // truth and is also the only thing on the screen that
                    // says it without words.
                    filled: running || done || p.done > 0,
                    onDark: true,
                    photos: [
                      for (final it in p.inFlight)
                        if (_thumbs[it.id] != null) _thumbs[it.id]!,
                    ],
                  ),
                ),
                // THE OUTCOME LIVES HERE TOO, not only the progress.
                //
                // The hero used to go blank the moment a run ended: the
                // figures were inside `if (running)`, so a finished backup
                // left a big saturated block with a drawing in it and nothing
                // to read, and the actual result — how many went — sat in a
                // plain white card below, looking like a footnote. The most
                // important sentence on the screen was in the quietest place
                // on it.
                //
                // So the block states the result in both states. Green with
                // "132 uploaded" across it is the whole answer at arm's
                // length, which is how this screen is read.
                if (running || _hasOutcome(p)) ...[
                  // The state in a word, above the number. A bare "132
                  // uploaded" does not say whether the run ENDED — and
                  // "stopped after 132" and "finished with 132" are different
                  // things to walk away from.
                  if (!running) ...[
                    Text(
                      failed
                          ? 'That did not work'
                          : p.state == BackupState.paused
                              ? 'Stopped'
                              : 'Backed up',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: Colors.white70),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          heroTitle(p).text,
                          maxLines: heroTitle(p).lines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              // Set by what the words ARE, not by where they
                              // sit. See heroTitle: a count gets the big
                              // type, a sentence gets reading size and room
                              // to wrap.
                              fontSize: heroTitle(p).size,
                              height: heroTitle(p).lines > 1 ? 1.2 : 1.05,
                              fontWeight: FontWeight.w800,
                              letterSpacing:
                                  heroTitle(p).size > 30 ? -0.9 : -0.4,
                              color: Colors.white,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]),
                        ),
                      ),
                      if (running &&
                          p.total > 0 &&
                          p.state != BackupState.scanning)
                        Text('${(p.fraction * 100).round()}%',
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                  if (_heroSubtitle(p, running: running) case final sub?) ...[
                    const SizedBox(height: 4),
                    Text(sub,
                        // A failure reason is a sentence, not a tally. One
                        // line would cut "Your session has expired — sign in
                        // again" in half, and the half that survives is the
                        // half that does not say what to do.
                        maxLines: failed ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70)),
                  ],
                  // Only while it is moving. A full bar under a finished run
                  // is a second, weaker way of saying what the words above
                  // already said; under a failed one it is a lie.
                  if (running) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: p.total == 0 ? null : p.fraction,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          // WHAT EACH SIDE HOLDS. The question this answers is asked out
          // loud every time somebody looks at the two apps side by side, and
          // until now nothing in the product answered it: the phone knew both
          // figures — it fetches the library count to size the run and the
          // server count to notice a library deleted at the computer — and
          // showed neither.
          // A list rather than a collection-`if`: the condition is "not
          // running AND there is something to say", and the something is a
          // value the widget then needs. A pattern-`if` cannot be combined
          // with `&&` like that, and forcing it produces a tree that looks
          // right and does not compile.
          ...(running ? const <Widget>[] : _tallyCard(theme, dark, p)),

          const SizedBox(height: 14),

          if (running) ...[
            // ONLY IF IT HAS SOMETHING IN IT.
            //
            // Every row inside this card is conditional, and during scanning
            // none of them are true yet — so it rendered as an empty white
            // rounded box sitting under the hero, which looks like a panel
            // that failed to load. Found by rendering the scanning state,
            // which had never been rendered before today.
            if (p.state == BackupState.running &&
                (p.inFlight.isNotEmpty || p.failed > 0))
            _card(
              theme,
              dark,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // The figures moved into the hero above. What stays here
                // is the part that is about individual photographs rather
                // than the run as a whole.
                // THE PHOTOGRAPHS GOING UP RIGHT NOW.
                //
                // Photos go four at a time, so this is a row rather than one
                // line: four thumbnails with four percentages, which is the
                // only thing on the screen that answers "which of my photos
                // is this". The name-and-percentage line below still covers
                // the single-video case, where there is one thing in the air
                // and its filename is worth reading.
                if (p.state == BackupState.running &&
                    p.inFlight.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ListenableBuilder(
                    listenable: _thumbs,
                    builder: (_, _) =>
                        UploadingNow(items: p.inFlight, cache: _thumbs),
                  ),
                ],
                if (p.state == BackupState.running &&
                    p.inFlight.length == 1 &&
                    p.currentLabel.isNotEmpty &&
                    p.currentFraction != null) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: Text(p.currentLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                        '${(p.currentFraction! * 100).round()}%'
                        '${p.currentTotal > 0 ? ' · ${_mb(p.currentTotal)}' : ''}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: theme.colorScheme.onSurfaceVariant)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: p.currentFraction,
                      minHeight: 4,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                          accent.withValues(alpha: 0.7)),
                    ),
                  ),
                ],
                // Left, with everything else in this card. A centred row under
                // left-aligned figures reads as a different block that
                // happened to land here.
                if (p.failed > 0) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _counts(p, running: true),
                  ),
                ],
              ]),
            ),
            // THE SLACK GOES HERE, above the actions — not below them.
            //
            // It was one Spacer at the very end of the column, which is not
            // the same thing at all: it packed everything against the top and
            // left four hundred points of empty white under the last button.
            // A screen with its content in the top half and a void beneath it
            // looks like it failed to finish loading. Put above the buttons,
            // the same flexible gap seats them on the bottom edge where a
            // thumb already is.
            const Spacer(),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _service?.stop,
              icon: const Icon(Icons.stop_circle_outlined, size: 19),
              label: const Text('Stop'),
            ),
            const SizedBox(height: 10),
            Text(
              'Keep this screen open while it runs. Stopping loses nothing — it '
              'carries on from here next time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: theme.colorScheme.outline),
            ),
          ] else ...[
            // The state, the figure and the counts have all moved into the
            // hero above. What was here was a white card repeating them in
            // smaller type, which is not emphasis — it is the reader being
            // asked to check whether two sets of numbers a few centimetres
            // apart agree.
            //
            // Only the paused and idle messages have anything left to say,
            // and `_heroSubtitle` says those up there as well.

            // WHAT DID NOT GO, in ONE panel.
            //
            // It was two: an amber box counting causes, and a red box of
            // unlabelled thumbnails. Same subject, stacked, in two different
            // warning colours — which reads as two problems, and neither box
            // alone answered the question. "16 photos: could not be
            // downloaded from iCloud" does not say WHICH, and a grid of
            // sixteen squares does not say why. Joined, one row is a picture,
            // a name and a reason.
            if (_hasFailures(p)) ...[
              _failuresCard(theme, dark, p),
              const SizedBox(height: 12),
            ],

            // As above: the gap belongs between what happened and what to do
            // about it, so the buttons sit on the bottom edge.
            const Spacer(),

            // Retry only what failed. Nearly every cause here is one thing
            // affecting many photos and is fixed in seconds — a sleeping
            // computer, an expired session. Making someone re-walk twenty
            // thousand photos to find out whether the fix worked is what turns
            // a ten-second repair into "the backup is broken".
            if (p.retryable > 0 && p.state != BackupState.running) ...[
              BrandButton(
                label: 'Try the ${p.retryable} that failed again',
                icon: Icons.refresh,
                block: true,
                onPressed: () => _service?.retryFailed(),
              ),
              const SizedBox(height: 8),
            ],

            BrandButton(
              label: p.state == BackupState.paused
                  ? 'Carry on backing up'
                  : failed
                      ? 'Try again'
                      : 'Back up my photos',
              icon: Icons.backup_outlined,
              block: true,
              // The quiet option once there is something more precise to do.
              ghost: p.retryable > 0,
              onPressed: () => _service?.runFullBackup(),
            ),

            // Directly under the manual button on purpose. The two are the
            // same job, and someone who has just watched a backup finish is
            // exactly the person who wants it to happen without them next time.
            const AutoBackupCard(),

            // THE WAY BACK from photos removed at the computer.
            //
            // This phone keeps its own list of what it has already sent, and the
            // computer no longer having a photo does not change that list — so
            // after emptying the bin there, "Back up my photos" skips every one
            // of them and reports a clean success while they sit on the phone
            // untouched. Without this button there is no way to notice, and no
            // way to put them back.
            if (p.state != BackupState.running &&
                p.state != BackupState.scanning) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _confirmRecheck,
                icon: const Icon(Icons.restart_alt, size: 19),
                label: const Text('Photos missing on the computer?'),
              ),
            ],

            // Only for a permission refusal, which is the one failure a person
            // fixes somewhere other than in this app.
            if (failed && _looksLikePermission(p.message)) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: PhotoManager.openSetting,
                icon: const Icon(Icons.settings_outlined, size: 19),
                label: const Text('Open photo settings'),
              ),
            ],
          ],
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  /// Asked before doing, because it makes the next backup long.
  ///
  /// It deletes nothing and cannot: it clears this phone's memory of what it
  /// has sent, and every photo is then offered again. The server recognises the
  /// ones it still has by their content and stores nothing twice — so the cost
  /// is time, and the thing it recovers is a library that was deleted at the
  /// computer and could not otherwise come back.
  Future<void> _confirmRecheck() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check every photo again?'),
        content: const Text(
            'This phone remembers which photos it has already sent, so it '
            'skips them. If photos were deleted on the computer, that memory '
            'is why they do not come back.\n\n'
            'Clearing it offers every photo again. Nothing is deleted from '
            'this phone, and the computer keeps only one copy of each — but '
            'the next backup will take a while.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Check everything')),
        ],
      ),
    );
    if (ok != true) return;
    await _service?.forgetSent();
  }

  // `_reasonLines` lived here: the causes as bullet strings for the amber
  // box. The box is gone — `_failuresCard` sorts the same map itself and
  // renders each cause as a row, because a count and a cause read better in
  // two weights than glued together with a colon.

  bool _looksLikePermission(String m) =>
      m.contains('allowed to see') || m.contains('All Photos');

  /// The two figures side by side, or nothing when there is nothing to say.
  List<Widget> _tallyCard(ThemeData theme, bool dark, BackupProgress p) {
    final note = tallyNote(p.libraryCount, p.serverCount, failed: p.failed);
    if (note == null) return const <Widget>[];
    return [
      _card(
        theme,
        dark,
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _tally(theme, 'This phone', p.libraryCount!),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.arrow_forward,
                  size: 15, color: theme.colorScheme.outline),
            ),
            _tally(theme, 'Your computer', p.serverCount!),
          ]),
          const SizedBox(height: 7),
          Text(note,
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// One side's figure with its name under it.
  Widget _tally(ThemeData theme, String label, int value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_n(value),
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  fontFeatures: [FontFeature.tabularFigures()])),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      );

  /// Is there anything to explain? Named files, bare causes, or just a count.
  ///
  /// The count alone counts. A run that fell over before it could attribute
  /// anything — an expired session, a computer that never answered — still
  /// has twenty thousand photos that did not go, and dropping the panel
  /// because there is no detail is how that number disappeared off the screen
  /// entirely when the old pills were removed.
  bool _hasFailures(BackupProgress p) =>
      p.failed > 0 ||
      (_service?.failedAssets.isNotEmpty ?? false) ||
      p.reasons.isNotEmpty;

  /// How many rows fit before the page stops being one page.
  ///
  /// Three, and it is a layout number rather than a judgement about how much
  /// somebody wants to read: the whole screen has to hold on a 390x844 phone
  /// without a scroll, and a fourth row is what pushes the buttons off the
  /// bottom. The rest are counted in a line underneath, and the retry button
  /// acts on all of them regardless of how many are drawn.
  static const _failRows = 3;

  /// EVERYTHING THAT DID NOT GO, in one panel: picture, name, reason.
  ///
  /// The reason is the part that was missing and it is the only part that is
  /// actionable. "Could not be downloaded from iCloud" means go and turn off
  /// Optimise Storage; "unsupported image" means the computer needs a decoder;
  /// "the connection dropped" means press the button again. Those are three
  /// different afternoons, and until this panel they all arrived as the same
  /// red number.
  ///
  /// White rather than the old tinted-red box. The hero above is already a
  /// saturated slab, and a second coloured panel under it competes with it
  /// instead of being read after it — the red belongs on the icon and the
  /// count, where it marks the thing rather than the whole area.
  Widget _failuresCard(ThemeData theme, bool dark, BackupProgress p) {
    final assets = _service?.failedAssets ?? const <AssetEntity>[];
    final shown = assets.take(_failRows).toList();
    // Whichever number is real. `p.failed` is the run's own tally; the asset
    // list is capped by what the service still holds, and on the debug path
    // there is no service at all.
    final total = p.failed > 0
        ? p.failed
        : assets.isNotEmpty
            ? assets.length
            : p.reasons.values.fold<int>(0, (a, b) => a + b);
    // Causes, largest first — shown as rows when there are no files to name,
    // and used to fill in a reason for a file the service has no note for.
    final causes = p.reasons.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final fallbackReason = causes.isEmpty ? '' : causes.first.key;

    return _card(
      theme,
      dark,
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: kDanger),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_n(total)} could not be sent',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          ),
        ]),
        if (shown.isNotEmpty || causes.isNotEmpty) const Divider(height: 17),
        // Nothing attributable — the run fell over before it could say which
        // photo or why. The count in the header is then the whole content, so
        // this line carries the one fact worth having at that moment: they
        // are not lost, they are simply still here.
        if (shown.isEmpty && causes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
                'They are all still on this phone. Nothing was deleted — '
                'backing up only ever copies.',
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
        if (shown.isNotEmpty) ...[
          for (final a in shown)
            _FailedRow(a,
                reason: _reasonOr(a.id, fallbackReason),
                last: identical(a, shown.last)),
          if (assets.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                  'and ${assets.length - shown.length} more — the button below '
                  'tries all of them',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
        ] else
          // No file list to draw from — a run that failed before it got that
          // far, or the render path in a test. The causes are still the
          // useful half, so they are shown in the same rows.
          for (final c in causes.take(_failRows))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kDanger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.cloud_off, size: 16, color: kDanger),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c.value} photo${c.value == 1 ? '' : 's'}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 1),
                        Text(c.key,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                color: theme.colorScheme.onSurfaceVariant)),
                      ]),
                ),
              ]),
            ),
      ]),
    );
  }

  /// This file's own reason, or the run's dominant one when it has no note.
  ///
  /// Empty is the worst answer here — it is the state this whole panel exists
  /// to replace — so a plausible shared cause beats nothing at all.
  String _reasonOr(String id, String fallback) {
    final own = _service?.reasonFor(id) ?? '';
    return own.isNotEmpty ? own : fallback;
  }

  /// done / already there / could not be sent, as tinted pills.
  ///
  /// "could not be READ" was the old wording and it was wrong: the photo read
  /// perfectly and the upload failed. Naming the right half is the difference
  /// between somebody checking their laptop and somebody checking their phone.
  /// `running` drops the two counts the line under the headline already
  /// states. While a run is going the screen said "900 already there" twice,
  /// a few centimetres apart — which does not read as emphasis, it reads as
  /// two different numbers that happen to match, and invites the reader to
  /// work out whether they do. What is NOT up there is the failures, so that
  /// pill stays in both states.
  List<Widget> _counts(BackupProgress p, {bool running = false}) => [
        if (p.done > 0 && !running)
          Pill('${p.done} sent', tone: PillTone.ok, icon: Icons.check),
        if (p.skipped > 0 && !running)
          Pill('${p.skipped} already there',
              tone: PillTone.muted, icon: Icons.done_all),
        if (p.failed > 0)
          Pill('${p.failed} not sent',
              tone: PillTone.danger, icon: Icons.priority_high),
      ];

  Widget _card(ThemeData theme, bool dark,
          {required Widget child, Color? border, EdgeInsets? padding}) =>
      Container(
        padding: padding ?? const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: softShadow(dark),
          border:
              border == null ? null : Border.all(color: border.withValues(alpha: 0.45), width: 1.5),
        ),
        child: child,
      );
}

/// One not-sent file as a row: picture, name, and why it stuck.
///
/// It was a bare 72px square in a grid, and a grid of squares is a picture of
/// a problem rather than a description of one — you can see that sixteen
/// things failed and learn nothing else without tapping each. The reason is
/// the whole content, so it is on the row.
///
/// The picture comes from `photo_manager`, not the server: the whole point is
/// that these files never reached the computer, so the library is the only
/// place a thumbnail of them exists. A video carries a small marker so a stuck
/// clip is not mistaken for a photo.
class _FailedRow extends StatelessWidget {
  const _FailedRow(this.asset, {required this.reason, this.last = false});

  final AssetEntity asset;
  final String reason;

  /// No divider under the last one — a rule with nothing after it reads as a
  /// row that failed to load.
  final bool last;

  String get _name => asset.title?.isNotEmpty == true
      ? asset.title!
      : 'This ${asset.type == AssetType.video ? 'video' : 'photo'}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(asset.type == AssetType.video
                  ? Icons.videocam_outlined
                  : Icons.image_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_name,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  reason.isEmpty ? 'It could not be sent this time.' : reason,
                  style: TextStyle(
                      height: 1.5, color: theme.colorScheme.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: last ? 8 : 9),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 34,
                height: 34,
                child: Stack(fit: StackFit.expand, children: [
                  FutureBuilder<Uint8List?>(
                    future: asset
                        .thumbnailDataWithSize(const ThumbnailSize.square(200)),
                    builder: (ctx, snap) => snap.data == null
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.photo_outlined,
                                color: theme.colorScheme.outline, size: 16))
                        : Image.memory(snap.data!,
                            fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                  if (asset.type == AssetType.video)
                    const Positioned(
                      left: 1,
                      bottom: 1,
                      child: Icon(Icons.play_circle_fill,
                          size: 13, color: Colors.white, shadows: [
                            Shadow(color: Colors.black54, blurRadius: 3)
                          ]),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    Text(
                        reason.isEmpty
                            ? 'It could not be sent this time'
                            : reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ]),
            ),
          ]),
          if (!last) const Divider(height: 18),
        ]),
      ),
    );
  }
}
