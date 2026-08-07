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
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';

import '../api.dart';
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
                p.takenAt == null
                    ? ''
                    : DateFormat('d MMMM y').format(p.takenAt!),
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
            builder: (ctx, i) => PhotoViewGalleryPageOptions(
              imageProvider: NetworkImage(_full(_photos[i])),
              // Bounded so a photo cannot be flung off screen and lost, and
              // covered at 4x which is enough to read a document photographed
              // on a phone.
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
              heroAttributes: PhotoViewHeroAttributes(tag: _photos[i].id),
              onTapUp: (context, details, value) => setState(() => _chrome = !_chrome),
            ),
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

  @override
  Widget build(BuildContext context) {
    final d = detail ?? const <String, dynamic>{};
    final rows = <List<String>>[
      if (d['orig_name'] != null) ['Name', '${d['orig_name']}'],
      if (photo.takenAt != null)
        ['Taken', DateFormat('d MMMM y').format(photo.takenAt!)],
      if (d['width'] != null && d['height'] != null)
        [
          'Size',
          '${d['width']} × ${d['height']}'
              '${d['megapixels'] != null ? '  (${d['megapixels']} MP)' : ''}'
        ],
      if (_size(d['size_bytes']).isNotEmpty) ['On disk', _size(d['size_bytes'])],
      if (d['camera'] != null) ['Camera', '${d['camera']}'],
      if (d['lens'] != null) ['Lens', '${d['lens']}'],
    ];

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Text('Details', style: Theme.of(context).textTheme.titleMedium),
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
                      child: Text(r[0],
                          style: Theme.of(context).textTheme.bodySmall)),
                  Expanded(child: Text(r[1])),
                ],
              ),
            ),
        const SizedBox(height: 14),
        Text(
          'This photo is stored on your own computer.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
