/// One button. This is the screen the whole application was built for.
///
/// Everything the web app could not do is here: no picker, no selecting, no
/// fifty at a time. The app reads the library directly and sends what is not
/// already on the computer.
///
/// It does NOT start on its own. An app that copies somebody's entire camera
/// roll the moment it is opened is exactly what people are right to distrust,
/// and this product's whole argument is that it is not that. The owner presses
/// the button, or schedules it, and can stop it at any point — stopping loses
/// nothing, because what has already been sent is remembered.
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

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../backup.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/backup_flight.dart';
import '../widgets/brand_button.dart';
import '../widgets/pill.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.debugProgress});

  /// For tests — render a given state without a photo library or a server.
  final BackupProgress? debugProgress;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupService? _service;

  @override
  void initState() {
    super.initState();
    if (widget.debugProgress != null) return;
    final s = BackupService(context.read<Session>().api);
    s.addListener(_onChange);
    s.load();
    _service = s;
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _service?.removeListener(_onChange);
    _service?.stop();
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
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

          // Two named devices with photos travelling between them. The bar says
          // how far along it is; this says where the photos are going, which is
          // the thing people actually wanted reassuring about — the whole point
          // of this app is that they go to YOUR computer and nowhere else, and
          // a progress bar cannot say that.
          //
          // Only animates while something is moving. A loop that carries on
          // after a finished run tells someone to keep waiting.
          BackupFlight(running: running),

          const SizedBox(height: 10),

          if (running) ...[
            _card(
              theme,
              dark,
              child: Column(children: [
                // A determinate bar the moment a total is known. An indefinite
                // sweep for twenty minutes tells somebody nothing except that
                // the app has not crashed.
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: p.total == 0 ? null : p.fraction,
                    minHeight: 10,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  p.state == BackupState.scanning
                      ? p.message
                      : '${p.handled} of ${p.total}',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
                if (p.total > 0) ...[
                  const SizedBox(height: 2),
                  Text('${(p.fraction * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: _counts(p),
                ),
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
    );
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

  /// done / already there / could not be sent, as tinted pills.
  ///
  /// "could not be READ" was the old wording and it was wrong: the photo read
  /// perfectly and the upload failed. Naming the right half is the difference
  /// between somebody checking their laptop and somebody checking their phone.
  List<Widget> _counts(BackupProgress p) => [
        if (p.done > 0)
          Pill('${p.done} sent', tone: PillTone.ok, icon: Icons.check),
        if (p.skipped > 0)
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
