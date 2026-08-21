/// One backed-up video, playing — with the standard controls a phone player has.
///
/// Shown in place of the zoomable image when a gallery item is a video. It keeps
/// the viewer's shape — same page, same swipe between items — because a video in
/// a photo library is an item in that library, not a different screen.
///
/// What it owes the person, and now pays:
///   * the still frame appears INSTANTLY (the grid already has it), so a slow
///     clip reads as "loading" over its own poster, not a black rectangle;
///   * it AUTO-PLAYS — opening a video is the intent to watch it, so a second tap
///     on a play button that had not appeared yet was the "not responsive" part;
///   * a real transport: a centre play/pause, a scrubber with elapsed / total
///     time, a buffering spinner, and controls that fade while it plays and come
///     back on a tap — the shape every phone video player has.
///
/// The decode is the platform's own — AVPlayer on iOS, ExoPlayer on Android, via
/// video_player — so playback is as native and hardware-accelerated as it gets.
/// The URL is the same signed, expiring one the grid uses: no more reachable
/// than a photo.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.url, this.poster});

  final String url;

  /// The still from the video, shown behind the player until the first frame is
  /// ready. Empty when the server had no poster for it.
  final String? poster;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoPlayerController? _c;
  String? _error;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c = c;
    try {
      await c.initialize();
      if (!mounted) return;
      await c.play(); // opening it IS the intent to watch — don't wait for a tap
      setState(() {});
      _armHide();
    } catch (_) {
      if (!mounted) return;
      // Named, not swallowed: a video that will not play is nearly always the
      // computer asleep or the signature expired, both of which a person can act
      // on.
      setState(() => _error = 'This video could not be played.\nCheck the '
          'computer is awake, then open it again.');
    }
  }

  /// Fade the controls out after a few seconds — but only while it is playing, so
  /// a paused video keeps its controls up.
  void _armHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) {
        setState(() => _controls = false);
      }
    });
  }

  void _tapSurface() {
    setState(() => _controls = !_controls);
    if (_controls) _armHide();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _hide?.cancel();
        _controls = true;
      } else {
        // Replay from the start if it had run to the end.
        if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
        c.play();
        _armHide();
      }
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c?.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.5)),
        ),
      );
    }

    final c = _c;
    final ready = c != null && c.value.isInitialized;

    return GestureDetector(
      onTap: ready ? _tapSurface : null,
      child: Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
        const ColoredBox(color: Colors.black),
        // The poster, until the first frame is up.
        if (!ready && (widget.poster?.isNotEmpty ?? false))
          Center(
            child: Image.network(widget.poster!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
        if (ready)
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
        // Everything that reacts to playback — spinner, controls, scrubber —
        // rebuilds off the controller alone, so the VideoPlayer surface above is
        // never rebuilt on a frame tick.
        if (c != null)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, v, _) {
              if (!v.isInitialized || v.isBuffering) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.white));
              }
              if (!_controls) return const SizedBox.expand();
              return _transport(c, v);
            },
          )
        else
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      ]),
    );
  }

  Widget _transport(VideoPlayerController c, VideoPlayerValue v) {
    final ended = v.position >= v.duration && v.duration > Duration.zero;
    return Stack(fit: StackFit.expand, children: [
      // A scrim so white controls read over any frame.
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black45, Colors.transparent, Colors.black54],
            stops: [0, 0.35, 1],
          ),
        ),
      ),
      // Centre play / pause / replay.
      Center(
        child: GestureDetector(
          onTap: _togglePlay,
          child: Container(
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle),
            padding: const EdgeInsets.all(14),
            child: Icon(
              ended
                  ? Icons.replay
                  : v.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
              size: 44,
              color: Colors.white,
            ),
          ),
        ),
      ),
      // Scrubber with elapsed / total time.
      Positioned(
        left: 14,
        right: 14,
        bottom: 12,
        child: Row(children: [
          Text(_fmt(v.position),
              style: const TextStyle(color: Colors.white, fontSize: 12)),
          const SizedBox(width: 10),
          Expanded(
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white38,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(_fmt(v.duration),
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
    ]);
  }
}
