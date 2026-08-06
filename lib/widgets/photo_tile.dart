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
import '../screens/gallery_screen.dart';

class PhotoTile extends StatelessWidget {
  const PhotoTile({super.key, required this.photo});
  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final base = session.baseUrl ?? '';
    final url = photo.thumbUrl.startsWith('http')
        ? photo.thumbUrl
        : '$base${photo.thumbUrl}';

    return GestureDetector(
      onTap: () {
        // The lightbox lands in the next pass; opening a half-built viewer
        // would be worse than the tile doing nothing yet.
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          Image.network(
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
          if (photo.isFavourite)
            const Positioned(
              right: 4,
              bottom: 4,
              child: Icon(Icons.star, size: 16, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
