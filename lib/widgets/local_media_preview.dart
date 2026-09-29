/// Look at — and play — a file that is still only on this phone.
///
/// WHY THIS EXISTS. The gallery plays videos perfectly well, but everything it
/// shows has already reached the computer. The files this is for are the ones
/// that have NOT: the backup's failures card can say "this one is stuck and
/// here is why", and until now the only thing identifying it was a 34-pixel
/// thumbnail. Two stuck videos look identical at that size, and deciding
/// whether to skip something you cannot watch is not a decision anybody should
/// be asked to make.
///
/// It reads from `photo_manager`, never from the server — the whole premise is
/// that the server does not have this file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

/// Open [asset] full-screen, playing it if it is a video.
Future<void> showLocalMedia(BuildContext context, AssetEntity asset) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => LocalMediaPreview(asset: asset),
    ));

class LocalMediaPreview extends StatefulWidget {
  const LocalMediaPreview({super.key, required this.asset});

  final AssetEntity asset;

  @override
  State<LocalMediaPreview> createState() => _LocalMediaPreviewState();
}

class _LocalMediaPreviewState extends State<LocalMediaPreview> {
  VideoPlayerController? _video;
  Uint8List? _still;
  String? _error;
  bool _loading = true;

  bool get _isVideo => widget.asset.type == AssetType.video;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    // The thumbnail first, always. It is already decoded for the row that got
    // us here, it arrives immediately, and it means the screen is never blank
    // while the real file is fetched — which for a video still in iCloud can
    // take a long time.
    try {
      _still = await widget.asset
          .thumbnailDataWithSize(const ThumbnailSize(1200, 1200));
      if (mounted) setState(() {});
    } catch (_) {
      // No still is not a failure; the file below is the point.
    }

    try {
      // `file` rather than `originFile`: for a video still in iCloud this is
      // what triggers the download, and for anything already local the two are
      // the same. It can legitimately return null — a file the phone cannot
      // produce is precisely the kind that fails to back up, so that case gets
      // a sentence rather than a spinner for ever.
      final f = await widget.asset.file;
      if (f == null) {
        _fail('This phone could not produce the file. If it is in iCloud, it '
            'may still be downloading — or Optimise Storage is keeping only a '
            'small copy here.');
        return;
      }
      if (!_isVideo) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final c = VideoPlayerController.file(File(f.path));
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _video = c;
        _loading = false;
      });
    } catch (e) {
      // A clip that will not open here is a clip in a format this phone's
      // decoder refuses, which is worth SAYING: it is very often the same
      // reason the computer would not take it either.
      _fail('This video would not open on the phone either. $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  String get _title => widget.asset.title?.isNotEmpty == true
      ? widget.asset.title!
      : (_isVideo ? 'Video' : 'Photo');

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_title, style: const TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: Colors.white54, size: 34),
                  const SizedBox(height: 14),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, height: 1.5)),
                ]),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  // The still sits underneath until the player is ready, so the
                  // picture never flashes black on the way in.
                  if (_still != null && video == null)
                    Image.memory(_still!, fit: BoxFit.contain),
                  if (video != null)
                    AspectRatio(
                      aspectRatio: video.value.aspectRatio,
                      child: VideoPlayer(video),
                    ),
                  if (_loading)
                    const CircularProgressIndicator(color: Colors.white),
                ],
              ),
      ),
      bottomNavigationBar: video == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(children: [
                  IconButton(
                    color: Colors.white,
                    icon: Icon(video.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow),
                    onPressed: () async {
                      video.value.isPlaying
                          ? await video.pause()
                          : await video.play();
                      if (mounted) setState(() {});
                    },
                  ),
                  Expanded(
                    child: VideoProgressIndicator(video, allowScrubbing: true),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: video,
                    builder: (_, v, _) => Text(
                      _clock(v.position),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

/// m:ss, or h:mm:ss once there is an hour to show.
///
/// Public so it can be tested without a video: a clock that reads "3:7" for
/// three minutes and seven seconds is the classic tell that nobody looked at
/// the output, and it is the kind of thing a render test cannot see.
String clockText(Duration d) => _clock(d);

String _clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
