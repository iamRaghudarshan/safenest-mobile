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
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.40),
                    blurRadius: 32,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Icon(
                failed
                    ? Icons.error_outline
                    : done
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_upload_outlined,
                size: 44,
                color: Colors.white,
              ),
            ),
          ),
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
          ListenableBuilder(
            listenable: _thumbs,
            builder: (_, _) => BackupFlight(
              running: running,
              photos: [
                for (final it in p.inFlight)
                  if (_thumbs[it.id] != null) _thumbs[it.id]!,
              ],
            ),
          ),

          const SizedBox(height: 10),

          if (running) ...[
            _card(
              theme,
              dark,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // THE FIGURE FIRST, THEN ITS BAR.
                //
                // It was the other way round, which reads as a loading
                // indicator with a caption under it rather than a number with
                // its progress. The number is the answer; the bar qualifies
                // it.
                //
                // Left-aligned, not centred: centred text in a card reads as a
                // poster. A figure you check repeatedly wants to be where the
                // eye already is, and the percentage sits opposite it on the
                // same line so both are read in one movement.
                // THE HEADLINE IS WHAT IS BEING UPLOADED, not the size of the
                // library.
                //
                // It used to read "68 of 1048", which is arithmetically exact
                // and says the wrong thing. 1048 is every photo on the phone —
                // the number this run has to LOOK at — and almost all of them
                // are usually skipped without a byte being sent. But it is also
                // exactly the number somebody recognises as their whole
                // library, so the screen read as "uploading all 1048 again",
                // twice reported as a bug that was not there.
                //
                // Now the big number is the photos actually sent, and the
                // library figure is demoted to the line that explains it. A
                // repeat backup reads "0 uploaded / 900 of 1048 checked, 900
                // already there", which is the truth and is reassuring instead
                // of alarming.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        p.state == BackupState.scanning
                            ? p.message
                            : '${p.done} uploaded',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                    if (p.total > 0 && p.state != BackupState.scanning)
                      Text('${(p.fraction * 100).round()}%',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: accent,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                  ],
                ),
                if (p.total > 0 && p.state != BackupState.scanning) ...[
                  const SizedBox(height: 4),
                  Text(
                      '${p.handled} of ${p.total} checked'
                      '${p.skipped > 0 ? ' · ${p.skipped} already there' : ''}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: p.total == 0 ? null : p.fraction,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
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
            // The outcome of the last run, before the button — it is what
            // somebody opening this screen wants to know first.
            if (p.message.isNotEmpty)
              _card(
                theme,
                dark,
                border: failed ? kDanger : (done ? kOk : null),
                child: Column(children: [
                  Row(children: [
                    Icon(
                        failed
                            ? Icons.error_outline
                            : p.state == BackupState.paused
                                ? Icons.pause_circle_outline
                                : Icons.check_circle_outline,
                        size: 20,
                        color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          failed
                              ? 'That did not work'
                              : p.state == BackupState.paused
                                  ? 'Stopped'
                                  : 'Backed up',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(p.message,
                        style: TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  if (p.total > 0) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 6, runSpacing: 6, children: _counts(p)),
                  ],
                ]),
              ),
            if (p.message.isNotEmpty) const SizedBox(height: 16),

            // WHY, per cause, not one sentence from whichever failure happened
            // last. Forty photos stuck in iCloud and three hitting an expired
            // session are two different jobs, and reporting only the second
            // leaves the first invisible. Every line here is something a person
            // can act on in under a minute.
            if (p.reasons.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: kWarn.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(kRadiusSm),
                  border: Border.all(color: kWarn.withValues(alpha: 0.35)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Why they did not go',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13.5)),
                      const SizedBox(height: 7),
                      for (final line in _reasonLines(p.reasons))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                // Expanded, or a full sentence overflows the
                                // row on a narrow phone.
                                Expanded(
                                  child: Text(line,
                                      style: const TextStyle(
                                          fontSize: 12.5, height: 1.4)),
                                ),
                              ]),
                        ),
                    ]),
              ),
              const SizedBox(height: 12),
            ],

            // WHICH files, not just how many. "2 not sent" is a number to worry
            // about; two thumbnails you recognise — "oh, those two clips still
            // in iCloud" — is a thing you can act on. Tapping one says why it
            // stuck. Only where there is a real service behind it: the test
            // path renders a state with no photo library to draw from.
            if (_service != null && _service!.failedAssets.isNotEmpty) ...[
              _notSentGrid(theme),
              const SizedBox(height: 12),
            ],

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
          // Pushes the actions to the bottom of the viewport when there is
          // room to spare, so the page reads as one composed screen rather
          // than a stack of things that stopped.
          const Spacer(),
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

  /// Largest cause first — the one worth fixing is the one blocking the most.
  List<String> _reasonLines(Map<String, int> reasons) {
    final e = reasons.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final x in e)
        '${x.value} photo${x.value == 1 ? '' : 's'}: ${x.key}',
    ];
  }

  bool _looksLikePermission(String m) =>
      m.contains('allowed to see') || m.contains('All Photos');

  /// The actual files that did not go, as thumbnails read straight from the
  /// phone's library — these never reached the computer, so there is nowhere
  /// else a picture of them could come from. Capped: a backup that failed
  /// wholesale (offline, expired session) can have thousands, and a Wrap of
  /// thousands of image futures would jank the screen it is meant to explain.
  Widget _notSentGrid(ThemeData theme) {
    final assets = _service!.failedAssets;
    const cap = 48;
    final shown = assets.take(cap).toList();
    final extra = assets.length - shown.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(color: kDanger.withValues(alpha: 0.30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('The ${assets.length} not sent',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
        const SizedBox(height: 3),
        Text(
            'Tap one to see why. They are still on this phone — they just have '
            'not reached your computer yet.',
            style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        Wrap(spacing: 7, runSpacing: 7, children: [
          for (final a in shown)
            _FailedThumb(a, reason: _service!.reasonFor(a.id)),
          if (extra > 0)
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('+$extra',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
        ]),
      ]),
    );
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
          {required Widget child, Color? border}) =>
      Container(
        padding: const EdgeInsets.all(18),
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

/// One not-sent file as a small square, tapped for the reason it stuck.
///
/// The picture comes from `photo_manager`, not the server: the whole point is
/// that these files never reached the computer, so the library is the only
/// place a thumbnail of them exists. A video carries a small marker so a stuck
/// clip is not mistaken for a photo.
class _FailedThumb extends StatelessWidget {
  const _FailedThumb(this.asset, {required this.reason});

  final AssetEntity asset;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
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
                child: Text(asset.title?.isNotEmpty == true
                    ? asset.title!
                    : 'This ${asset.type == AssetType.video ? 'video' : 'photo'}',
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Stack(fit: StackFit.expand, children: [
            FutureBuilder<Uint8List?>(
              future:
                  asset.thumbnailDataWithSize(const ThumbnailSize.square(200)),
              builder: (ctx, snap) => snap.data == null
                  ? Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.photo_outlined,
                          color: theme.colorScheme.outline, size: 20))
                  : Image.memory(snap.data!,
                      fit: BoxFit.cover, gaplessPlayback: true),
            ),
            // A red corner so a stuck file reads as stuck at a glance, not just
            // as another thumbnail in a grid.
            Positioned(
              right: 3,
              top: 3,
              child: Icon(Icons.cloud_off,
                  size: 14, color: kDanger, shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 3)
                  ]),
            ),
            if (asset.type == AssetType.video)
              const Positioned(
                left: 3,
                bottom: 3,
                child: Icon(Icons.play_circle_fill,
                    size: 16, color: Colors.white, shadows: [
                      Shadow(color: Colors.black54, blurRadius: 3)
                    ]),
              ),
          ]),
        ),
      ),
    );
  }
}
