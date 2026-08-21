/// The full-screen photo, the way Google Photos does it.
///
/// This was the most-felt absence in the grid: tapping a photo did nothing at
/// all, which reads as the app being broken rather than unfinished.
///
/// WHAT MAKES IT FEEL RIGHT, mechanically
///   * Swipe between photos without leaving the screen, because a viewer you
///     have to back out of to see the next one is not a viewer.
///   * Pinch and double-tap to zoom, with the pan bounded to the image.
///   * Tap once to hide the controls. A photo with a toolbar across it is a
///     screenshot of an app; a photo alone is a photo.
///   * Full size here, thumbnails in the grid. The opposite of both is what
///     runs a phone out of memory.
///   * Details are fetched for the ONE photo on screen, never for the page —
///     _detail on the server exists for exactly this reason.
library;

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../sharing.dart';
import '../widgets/pill.dart';
import '../widgets/video_page.dart';
import '../theme.dart';
import '../dates.dart';
import '../session.dart';
import 'gallery_screen.dart';

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.onChanged,
  });

  final List<Photo> photos;
  final int initialIndex;

  /// Called when a photo is favourited or trashed, so the grid behind can catch
  /// up rather than showing a star that is no longer true.
  final VoidCallback? onChanged;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late PageController _pages;
  late int _index;
  late List<Photo> _photos;
  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _photos = List.of(widget.photos);
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  String _full(Photo p) {
    final base = context.read<Session>().baseUrl ?? '';
    return p.url.startsWith('http') ? p.url : '$base${p.url}';
  }

  /// The video's still, shown behind the player the instant it opens so a slow
  /// load reads as "loading this clip" rather than a black rectangle.
  String _fullThumb(Photo p) {
    if (p.thumbUrl.isEmpty) return '';
    final base = context.read<Session>().baseUrl ?? '';
    return p.thumbUrl.startsWith('http') ? p.thumbUrl : '$base${p.thumbUrl}';
  }

  Future<void> _toggleFavourite() async {
    final p = _photos[_index];
    // Flipped on screen first: the server is a round trip away and a star that
    // waits for it feels broken. Put back if the call fails.
    setState(() => _photos[_index] = p.copyWith(isFavourite: !p.isFavourite));
    try {
      await context.read<Session>().api.post('/api/gallery/${p.id}/favourite');
      widget.onChanged?.call();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _photos[_index] = p);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _trash() async {
    final p = _photos[_index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to trash?'),
        content: const Text(
            'It stays in the trash on your computer until you empty it, and it '
            'is still on this phone either way.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Move to trash')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<Session>().api.delete('/api/gallery/${p.id}');
      widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        _photos.removeAt(_index);
        if (_index >= _photos.length) _index = _photos.length - 1;
      });
      if (_photos.isEmpty && mounted) Navigator.pop(context);
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Send this photo out of the app.
  ///
  /// The ORIGINAL, not the thumbnail: somebody sharing a photo means the photo.
  /// The bytes are fetched with the session token and shared as a file — never
  /// the signed URL, which would lapse before the recipient opened it and would
  /// put an address for a private machine into a chat thread.
  Future<void> _share() async {
    final p = _photos[_index];
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<Session>().api;
    messenger.showSnackBar(const SnackBar(content: Text('Preparing…')));
    final problem = await shareFromServer(api,
        items: [(path: p.url, name: 'photo.jpg')]);
    if (problem != null && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _info() async {
    final p = _photos[_index];
    Map<String, dynamic>? d;
    try {
      final r = await context.read<Session>().api.get('/api/gallery/${p.id}/info');
      if (r is Map) d = Map<String, dynamic>.from(r);
    } on ApiError {
      // A details sheet that cannot load is not worth an error over the photo.
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _InfoSheet(detail: d, photo: p),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_photos.isEmpty) return const SizedBox.shrink();
    final p = _photos[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chrome
          ? AppBar(
              backgroundColor: Colors.black38,
              foregroundColor: Colors.white,
              elevation: 0,
              title: Text(
                fmtDate(p.takenAt),
                style: const TextStyle(fontSize: 15),
              ),
            )
          : null,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _pages,
            itemCount: _photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (context, event) =>
                const Center(child: CircularProgressIndicator()),
            builder: (ctx, i) {
              // A video gets a player instead of a zoomable image, in the same
              // page of the same gallery — swiping still carries on into the
              // photos either side of it. `customChild` rather than a separate
              // screen, so a video is an item in the library rather than
              // somewhere you get sent.
              if (_photos[i].isVideo) {
                return PhotoViewGalleryPageOptions.customChild(
                  child: VideoPage(
                      url: _full(_photos[i]),
                      poster: _fullThumb(_photos[i])),
                  // Zoom off: the pinch belongs to the player's own frame, and
                  // a scaled video surface is where playback stutters.
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.contained,
                  heroAttributes: PhotoViewHeroAttributes(tag: _photos[i].id),
                );
              }
              return PhotoViewGalleryPageOptions(
                imageProvider: NetworkImage(_full(_photos[i])),
                // Bounded so a photo cannot be flung off screen and lost, and
                // covered at 4x which is enough to read a document photographed
                // on a phone.
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                heroAttributes: PhotoViewHeroAttributes(tag: _photos[i].id),
                onTapUp: (context, details, value) =>
                    setState(() => _chrome = !_chrome),
              );
            },
          ),
          if (_chrome)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black38,
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 6, top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Action(
                      icon: p.isFavourite ? Icons.star : Icons.star_border,
                      label: 'Favourite',
                      active: p.isFavourite,
                      onTap: _toggleFavourite,
                    ),
                    _Action(
                        icon: Icons.ios_share,
                        label: 'Share',
                        onTap: _share),
                    _Action(
                        icon: Icons.info_outline,
                        label: 'Details',
                        onTap: _info),
                    _Action(
                        icon: Icons.delete_outline,
                        label: 'Trash',
                        onTap: _trash),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colour = active ? Colors.amber : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: colour),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: colour, fontSize: 11)),
        ]),
      ),
    );
  }
}

/// What the server knows about one photo.
///
/// THE BUG THIS REPLACES: /api/gallery/{id}/info answers
/// `{photo: {...}, albums: [...], people: [...]}`, and this read `d['width']`,
/// `d['orig_name']` and the rest straight off the TOP level — one level above
/// where they live. Every lookup returned null, so `rows` was always empty and
/// every photo in the app reported "Nothing recorded for this photo."
///
/// It also threw away the two things the endpoint returns that nothing else in
/// the app can tell you: which albums a photo is in, and who is in it.
class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.detail, required this.photo});
  final Map<String, dynamic>? detail;
  final Photo photo;

  String _size(dynamic b) {
    final n = b is num ? b.toDouble() : double.tryParse('${b ?? ''}');
    if (n == null || n == 0) return '';
    if (n < 1024 * 1024) return '${(n / 1024).round()} KB';
    return '${(n / 1048576).toStringAsFixed(1)} MB';
  }

  String _coord(dynamic lat, dynamic lon) {
    final a = lat is num ? lat.toDouble() : double.tryParse('${lat ?? ''}');
    final o = lon is num ? lon.toDouble() : double.tryParse('${lon ?? ''}');
    if (a == null || o == null) return '';
    final ns = a >= 0 ? 'N' : 'S';
    final ew = o >= 0 ? 'E' : 'W';
    return '${a.abs().toStringAsFixed(4)}° $ns, ${o.abs().toStringAsFixed(4)}° $ew';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = detail ?? const <String, dynamic>{};

    // The photo's own fields are NESTED. Falling back to the root keeps this
    // working if the endpoint is ever flattened.
    final d = root['photo'] is Map
        ? Map<String, dynamic>.from(root['photo'] as Map)
        : root;
    final albums = (root['albums'] as List?) ?? const [];
    final people = (root['people'] as List?) ?? const [];

    final where = _coord(d['lat'], d['lon']);
    final rows = <List<String>>[
      if (d['orig_name'] != null) ['Name', '${d['orig_name']}'],
      if (photo.takenAt != null) ['Taken', fmtDate(photo.takenAt)],
      if (d['width'] != null && d['height'] != null)
        [
          'Dimensions',
          '${d['width']} × ${d['height']}'
              '${d['megapixels'] != null ? '  (${d['megapixels']} MP)' : ''}'
        ],
      if (_size(d['size_bytes']).isNotEmpty) ['On disk', _size(d['size_bytes'])],
      if (d['camera'] != null) ['Camera', '${d['camera']}'],
      if (d['lens'] != null) ['Lens', '${d['lens']}'],
      if (where.isNotEmpty) ['Where', where],
      // Date AND time: "when did this reach my computer" is a question about a
      // moment, and it is usually asked right after a backup run.
      if (d['uploaded_at'] != null)
        ['Backed up', fmtDateTime(parseDate('${d['uploaded_at']}'))],
    ];

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Text('Details', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Text('Nothing recorded for this photo.')
        else
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 96,
                      child: Text(r[0], style: theme.textTheme.bodySmall)),
                  Expanded(child: Text(r[1])),
                ],
              ),
            ),

        // Which albums it is in — nothing else in the app can answer this, and
        // it is how you find out you already filed a photo somewhere.
        if (albums.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('In albums', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final a in albums)
              Pill('${(a as Map)['name'] ?? 'Album'}',
                  colour: kModuleColours['gallery'],
                  icon: Icons.photo_album_outlined),
          ]),
        ],

        if (people.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('People', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final pr in people)
              Pill('${(pr as Map)['name'] ?? 'Someone'}',
                  colour: kBrand, icon: Icons.person_outline),
          ]),
        ],

        const SizedBox(height: 16),
        Text(
          'This photo is stored on your own computer.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}


