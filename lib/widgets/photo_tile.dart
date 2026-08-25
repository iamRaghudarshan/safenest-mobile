/// One square in the grid.
///
/// Always the server's `thumb` variant, never the full image: a 12MP photo per
/// cell is how a gallery screen runs a phone out of memory, and the grid is the
/// screen most likely to be scrolled through thousands of items.
///
/// The URL from the server is HMAC-signed and time-limited — photos are never
/// served from a static mount, so a filename alone fetches nothing. That is why
/// the whole URL is used as given rather than rebuilt from the id here.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../screens/gallery_screen.dart';

/// A media URL from the server, made absolute.
///
/// The server mints signed, time-limited paths like
/// `/api/gallery/media/thumb/<name>?t=<signature>` — RELATIVE, because the web
/// app is served from the same origin. A phone is not, and `Image.network`
/// cannot resolve a relative URL: it fails outright, which surfaces as a
/// silhouette or a broken-image glyph where a photograph should be.
///
/// One function because the rule was copied into five widgets and the fifth
/// forgot it, which is what put a strip of grey circles across the top of a
/// gallery that had found every face perfectly well.
String absoluteMedia(String raw, String base) =>
    raw.startsWith('http') ? raw : '$base$raw';

class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.photo,
    this.onOpen,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });
  final Photo photo;
  final VoidCallback? onOpen;

  /// Long-press starts selection, which is how every photo app on either
  /// platform does it — there is no button to discover.
  final VoidCallback? onLongPress;

  /// True once ANY photo is selected. The whole grid switches behaviour then:
  /// a tap toggles instead of opening, which is the convention people already
  /// have, and the one thing that must not surprise them.
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final url = absoluteMedia(photo.thumbUrl, session.baseUrl ?? '');

    return GestureDetector(
      onTap: onOpen,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          // Hero tag matches the viewer's, so the tile grows into the full photo
          // instead of the screen cutting to it.
          Hero(
            tag: photo.id,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              // cacheWidth caps the DECODED size in memory. Without it, Flutter
              // decodes at full resolution regardless of how small it is drawn,
              // which is the usual reason a photo grid is killed by the OS.
              cacheWidth: 320,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) => Icon(
                Icons.broken_image_outlined,
                color: Theme.of(context).colorScheme.outline,
                size: 20,
              ),
              loadingBuilder: (ctx, child, progress) =>
                  progress == null ? child : const SizedBox.shrink(),
            ),
          ),
          // A video has to be recognisable AS a video before it is tapped.
          // Its tile is a still frame, so without a mark it is a photograph
          // that mysteriously plays.
          if (photo.isVideo)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                  if (photo.durationLabel.isNotEmpty) ...[
                    const SizedBox(width: 2),
                    Text(photo.durationLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ],
                ]),
              ),
            ),
          if (photo.isFavourite)
            const Positioned(
              right: 4,
              bottom: 4,
              child: Icon(Icons.star, size: 16, color: Colors.white),
            ),

          // A selected photo SHRINKS as well as gaining a tick. On a grid of
          // thumbnails a tick alone is easy to miss against a busy picture;
          // the gap between tiles is not.
          if (selecting)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: EdgeInsets.all(selected ? 8 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(selected ? 8 : 0),
                    border: selected
                        ? Border.all(color: kBrand, width: 2.5)
                        : null,
                    color: selected
                        ? kBrand.withValues(alpha: 0.18)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          if (selecting)
            Positioned(
              left: 5,
              top: 5,
              child: IgnorePointer(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? kBrand : Colors.black.withValues(alpha: 0.35),
                    border: Border.all(color: Colors.white, width: 1.6),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
