/// One backed-up video, playing.
///
/// Shown in place of the zoomable image when a gallery item is a video. It
/// deliberately keeps the viewer's shape — same page, same swipe between items,
/// same chrome — because a video in a photo library is an item in that library,
/// not a different screen you get sent to.
///
/// The URL is the same signed, expiring one the grid uses. Nothing here makes a
/// video more reachable than a photo: without a valid signature it is a 404,
/// same as everything else in the gallery.
library;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.url});
  final String url;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoPlayerController? _c;
  String? _error;

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
      // Loop: a clip that stops on its last frame looks like it froze, and the
      // last frame of a phone video is usually a blur of somebody lowering
      // their arm.
      await c.setLooping(true);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      // Named, not swallowed. A video that will not play is nearly always the
      // computer being asleep or the signature having expired, and both are
      // things the person can do something about.
      setState(() => _error = 'This video could not be played. '
          'Check the computer is awake, then open it again.');
    }
  }

  @override
  void dispose() {
    // Disposed, always. A controller left alive holds a decoder open, and the
    // viewer builds one of these per swipe — a few videos in and the phone
    // stops being able to open any of them.
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: Stack(alignment: Alignment.center, children: [
          VideoPlayer(c),
          // Tap anywhere to play or pause — the whole frame, not a small
          // button, because the frame is what a thumb lands on.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(
                () => c.value.isPlaying ? c.pause() : c.play()),
            child: AnimatedOpacity(
              opacity: c.value.isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: const Icon(Icons.play_arrow,
                    size: 44, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              colors: const VideoProgressColors(playedColor: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}
