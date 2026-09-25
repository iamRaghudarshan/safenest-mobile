/// The photographs going up right now, as photographs.
///
/// WHY THIS EXISTS. The screen said "IMG_4102.HEIC — 43%". A filename off a
/// camera roll tells nobody which picture is being sent, and photos go up
/// FOUR at a time, so a single label flickered between four uploads and
/// settled on whichever finished last. It read as one photo taking an age
/// rather than four going at once.
///
/// So: the real thumbnails, one per upload in flight, each with its own
/// progress. The thumbnail is the whole point — it is the only thing on the
/// screen that answers "which of my photos is this".
///
/// TWO DIFFERENT WAITS, shown differently. A photo living in iCloud has to
/// come DOWN from Apple before it can go UP to the computer, and that leg can
/// be the slow one. Showing an upload bar at zero while a 200 MB video is
/// being fetched looks exactly like a stall, which is the thing this screen
/// exists to rule out.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../backup.dart';

/// Decodes and keeps the thumbnails, so a rebuild per progress tick does not
/// re-read them off the photo library.
///
/// Keyed by asset id and bounded: a long backup passes thousands of photos
/// through here, and holding every one would be a leak that only shows on the
/// libraries this app is FOR.
class ThumbCache extends ChangeNotifier {
  ThumbCache({this.limit = 24});

  final int limit;
  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  bool _disposed = false;

  ui.Image? operator [](String id) => _images[id];

  /// Ask for one. Returns immediately; listeners are told when it arrives.
  void want(String id) {
    if (_disposed || _images.containsKey(id) || _loading.contains(id)) return;
    _loading.add(id);
    unawaited(_load(id));
  }

  Future<void> _load(String id) async {
    try {
      final asset = await AssetEntity.fromId(id);
      if (asset == null) return;
      // A SMALL thumbnail on purpose. These are drawn at 64pt in a strip and
      // at 22pt in the animation; asking the phone for a full-size decode of
      // each of four photos, several times a second, is how a progress screen
      // becomes the reason the upload is slow.
      final Uint8List? bytes =
          await asset.thumbnailDataWithSize(const ThumbnailSize.square(320));
      if (bytes == null || _disposed) return;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      if (_images.length >= limit) {
        // Oldest out. Dispose it rather than dropping the reference: a
        // ui.Image holds native memory the garbage collector does not hurry
        // over.
        final oldest = _images.keys.first;
        _images.remove(oldest)?.dispose();
      }
      _images[id] = frame.image;
      notifyListeners();
    } catch (_) {
      // A thumbnail is a nicety. The upload does not depend on it and a photo
      // that cannot produce one still shows its progress.
    } finally {
      _loading.remove(id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final im in _images.values) {
      im.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

/// A row of the photos currently going up.
class UploadingNow extends StatelessWidget {
  const UploadingNow({
    super.key,
    required this.items,
    required this.cache,
  });

  final List<BackupItem> items;
  final ThumbCache cache;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    for (final it in items) {
      cache.want(it.id);
    }

    // The caption says how many, because four thumbnails with four separate
    // percentages is a lot to read at a glance and the count is the answer to
    // "is it doing anything".
    final fetching = items.where((i) => i.fetching).length;
    final caption = fetching == items.length
        ? (fetching == 1
            ? 'Getting 1 photo from iCloud'
            : 'Getting $fetching photos from iCloud')
        : (items.length == 1
            ? 'Sending 1 ${items.first.isVideo ? 'video' : 'photo'}'
            : 'Sending ${items.length} at once');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) => _Tile(item: items[i], cache: cache),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.cache});

  final BackupItem item;
  final ThumbCache cache;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = cache[item.id];
    final fetching = item.fetching;
    final value = fetching ? item.fetched : item.fraction;
    final pct = value == null ? null : (value * 100).round();

    return SizedBox(
      // Medium, not a thumbnail. The picture is the answer to "which of my
      // photos is this", and at 64 across a face in a group shot is a smudge.
      width: 88,
      child: Column(children: [
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 88,
              height: 76,
              child: image == null
                  ? Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.photo_outlined,
                          size: 26, color: theme.colorScheme.outline))
                  : RawImage(image: image, fit: BoxFit.cover),
            ),
          ),
          // A scrim under the number, so a percentage stays readable over a
          // bright photograph. Without it, white text on a white sky is
          // invisible on exactly the holiday photos people back up.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                pct == null ? '…' : '$pct%',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          if (item.isVideo)
            const Positioned(
              left: 4,
              top: 4,
              child: Icon(Icons.play_circle_fill,
                  size: 14,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
            ),
          // The cloud badge marks the photos that are still coming DOWN.
          if (fetching)
            const Positioned(
              right: 4,
              top: 4,
              child: Icon(Icons.cloud_download,
                  size: 14,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
            ),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 3,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
                fetching ? theme.colorScheme.tertiary : theme.colorScheme.primary),
          ),
        ),
      ]),
    );
  }
}
