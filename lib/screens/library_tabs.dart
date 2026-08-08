/// Albums, People and Memories — the parts of the library that are not a grid.
///
/// None of this is new work on the server. It has been clustering faces,
/// suggesting albums and working out what happened on this day in other years
/// all along; the phone simply was not asking. On a real library here it had
/// already found people with 49 and 38 photos before anything on this screen
/// existed.
///
/// A COLLECTION IS THE SAME GRID
/// Opening an album and opening a person land on the same screen with a
/// different source, because to the person looking they are the same thing: a
/// wall of photos with a name on it. Two implementations would drift, and the
/// one that drifted would be the one nobody opens.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../widgets/brand_button.dart';
import '../widgets/photo_tile.dart';
import 'gallery_screen.dart';
import 'photo_viewer.dart';

String _abs(BuildContext c, String u) {
  if (u.isEmpty || u.startsWith('http')) return u;
  return '${c.read<Session>().baseUrl ?? ''}$u';
}

/// ---------------------------------------------------------------- albums ---

class AlbumsTab extends StatefulWidget {
  const AlbumsTab({super.key});
  @override
  State<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<AlbumsTab> {
  List<Map<String, dynamic>> _albums = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/gallery/albums');
      setState(() {
        _albums = [
          for (final a in ((d as Map)['albums'] as List? ?? const []))
            Map<String, dynamic>.from(a as Map)
        ];
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _Retry(message: _error!, onRetry: _load);
    if (_albums.isEmpty) {
      return const _Empty(
        icon: Icons.photo_album_outlined,
        title: 'No albums yet',
        note: 'Albums you make on the computer show up here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: _albums.length,
        itemBuilder: (ctx, i) {
          final a = _albums[i];
          return _Cover(
            title: '${a['name'] ?? 'Album'}',
            count: (a['count'] ?? 0) as int,
            imageUrl: a['cover_url'] == null ? null : _abs(ctx, '${a['cover_url']}'),
            square: false,
            onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
              builder: (_) => CollectionScreen(
                title: '${a['name'] ?? 'Album'}',
                // /api/gallery/albums/{id} answers {id, name, count} and NO
                // photos — so this screen fetched an album and rendered an
                // empty grid. The photos come from the main index with an
                // album filter, which is what the web app uses too.
                path: '/api/gallery?album=${a['id']}',
                albumId: a['id'] as int?,
              ),
            )).then((_) => _load()),
          );
        },
      ),
    );
  }
}

/// ---------------------------------------------------------------- people ---

class PeopleTab extends StatefulWidget {
  const PeopleTab({super.key});
  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/people');
      setState(() {
        _people = [
          for (final p in ((d as Map)['people'] as List? ?? const []))
            Map<String, dynamic>.from(p as Map)
        ];
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _Retry(message: _error!, onRetry: _load);
    if (_people.isEmpty) {
      return const _Empty(
        icon: Icons.people_outline,
        title: 'No people found yet',
        note: 'Your computer groups faces in the background as photos arrive. '
            'It runs when nothing else needs the machine, so give it time '
            'after a big backup.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: _people.length,
        itemBuilder: (ctx, i) {
          final p = _people[i];
          return _Cover(
            title: '${p['name'] ?? 'Someone'}',
            count: (p['count'] ?? 0) as int,
            imageUrl: p['cover_url'] == null ? null : _abs(ctx, '${p['cover_url']}'),
            square: true,
            onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
              builder: (_) => CollectionScreen(
                title: '${p['name'] ?? 'Someone'}',
                path: '/api/people/${p['id']}/photos',
              ),
            )),
          );
        },
      ),
    );
  }
}

/// -------------------------------------------------------------- memories ---

class MemoriesTab extends StatefulWidget {
  const MemoriesTab({super.key});
  @override
  State<MemoriesTab> createState() => _MemoriesTabState();
}

class _MemoriesTabState extends State<MemoriesTab> {
  List<Map<String, dynamic>> _groups = [];
  String _date = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/gallery/memories');
      final m = d as Map;
      setState(() {
        _groups = [
          for (final g in (m['groups'] as List? ?? const []))
            Map<String, dynamic>.from(g as Map)
        ];
        _date = '${m['date'] ?? ''}';
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _Retry(message: _error!, onRetry: _load);
    if (_groups.isEmpty) {
      return _Empty(
        icon: Icons.auto_awesome_outlined,
        title: 'Nothing from $_date in other years',
        note: 'Once you have photos from previous years, this shows what you '
            'were doing on this day.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final g in _groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Text('${g['label']}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            SizedBox(
              height: 132,
              child: Builder(builder: (ctx) {
                final items = [
                  for (final e in (g['items'] as List? ?? const []))
                    Photo.fromJson(Map<String, dynamic>.from(e as Map))
                ];
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: items.length,
                  separatorBuilder: (_, i) => const SizedBox(width: 8),
                  itemBuilder: (c2, i) => GestureDetector(
                    onTap: () => Navigator.of(c2).push(MaterialPageRoute(
                      builder: (_) =>
                          PhotoViewer(photos: items, initialIndex: i),
                    )),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _abs(c2, items[i].thumbUrl),
                        width: 118,
                        height: 132,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (a, b, c) => Container(
                            width: 118,
                            color: Theme.of(c2).colorScheme.surfaceContainerHighest),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------ collection ---

/// The photos of one album or one person. Same grid, different source.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen(
      {super.key,
      required this.title,
      required this.path,
      this.albumId,
      this.initialPhotos});
  final String title;
  final String path;

  /// Set when this IS an album, which unlocks managing it: rename, delete, and
  /// taking photos back out. A person's photos are a computed collection and
  /// have none of those — you cannot rename a face.
  final int? albumId;

  /// For tests — lay the screen out without a server.
  final List<Photo>? initialPhotos;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  List<Photo> _photos = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  /// Selecting inside an album, so photos can be taken back OUT of it. The
  /// endpoint (/albums/{id}/remove) has always taken a batch and nothing here
  /// could send one.
  final Set<int> _selected = {};
  bool get _selecting => _selected.isNotEmpty;
  bool get _isAlbum => widget.albumId != null;

  late String _title = widget.title;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhotos != null) {
      _photos = widget.initialPhotos!;
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename album'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<Session>()
          .api
          .put('/api/gallery/albums/${widget.albumId}', {'name': name});
      setState(() => _title = name);
    } on ApiError catch (e) {
      // 409 is the useful one: the server refuses a duplicate name, and saying
      // so is better than the rename silently not happening.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteAlbum() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$_title"?'),
        // Verified against the server: deleting an album leaves every photo
        // exactly where it was. Saying so is what stops this reading as
        // "delete these 214 photos".
        content: const Text(
            'The album goes; the photos stay in your gallery. Nothing is '
            'deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete album')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context
          .read<Session>()
          .api
          .delete('/api/gallery/albums/${widget.albumId}');
      navigator.pop(true);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _removeSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await context.read<Session>().api.post(
          '/api/gallery/albums/${widget.albumId}/remove', {'photo_ids': ids});
      _selected.clear();
      await _load();
      messenger.showSnackBar(SnackBar(
          content: Text('Removed ${ids.length} from this album — '
              'still in your gallery')));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get(widget.path);
      // Albums answer {album:…, items:[…]}, people answer {items:[…]}, and a
      // bare list is possible too. Accepting all three beats guessing one.
      final list = d is List
          ? d
          : (d is Map ? (d['items'] ?? d['photos'] ?? const []) : const []);
      setState(() {
        _photos = [
          for (final e in (list as List))
            Photo.fromJson(Map<String, dynamic>.from(e as Map))
        ];
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          // Only for an album. A person's photos are a computed collection —
          // there is nothing to rename and nothing to take a photo out of.
          if (_isAlbum && !_selecting)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'rename' ? _rename() : _deleteAlbum(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename album')),
                PopupMenuItem(
                    value: 'delete', child: Text('Delete album')),
              ],
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${_photos.length} photos',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                      top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant)),
                ),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    IconButton(
                      tooltip: 'Cancel',
                      onPressed: _busy ? null : () => setState(_selected.clear),
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text('${_selected.length} selected',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 4),
                  // "Remove from album", never "Delete". Taking a photo out of
                  // an album does not touch the photo, and the wording has to
                  // make that obvious before the tap, not after it.
                  BrandButton(
                    label: 'Remove from this album',
                    icon: Icons.playlist_remove,
                    block: true,
                    onPressed: _busy ? null : _removeSelected,
                  ),
                ]),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Retry(message: _error!, onRetry: _load)
              : _photos.isEmpty
                  ? const _Empty(
                      icon: Icons.photo_outlined,
                      title: 'Nothing here',
                      note: 'This collection has no photos in it.')
                  : GridView.builder(
                      padding: const EdgeInsets.all(2),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                      ),
                      itemCount: _photos.length,
                      // PhotoTile rather than a bare Image: it already knows
                      // how to be selected, caps its decode, and shows a
                      // broken-image glyph instead of a grey square. Three
                      // behaviours that were reimplemented worse here.
                      itemBuilder: (ctx, i) => PhotoTile(
                        photo: _photos[i],
                        selecting: _selecting,
                        selected: _selected.contains(_photos[i].id),
                        onOpen: () {
                          if (_selecting) {
                            setState(() {
                              if (!_selected.remove(_photos[i].id)) {
                                _selected.add(_photos[i].id);
                              }
                            });
                            return;
                          }
                          Navigator.of(ctx).push(MaterialPageRoute(
                            builder: (_) => PhotoViewer(
                              photos: _photos,
                              initialIndex: i,
                              onChanged: _load,
                            ),
                          ));
                        },
                        // Only an album can have photos taken out of it, so
                        // only an album offers the long-press that starts it.
                        onLongPress: _isAlbum
                            ? () => setState(() {
                                  if (!_selected.remove(_photos[i].id)) {
                                    _selected.add(_photos[i].id);
                                  }
                                })
                            : null,
                      ),
                    ),
    );
  }
}

/// ------------------------------------------------------------- fragments ---

class _Cover extends StatelessWidget {
  const _Cover({
    required this.title,
    required this.count,
    required this.imageUrl,
    required this.onTap,
    required this.square,
  });
  final String title;
  final int count;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(square ? Icons.person : Icons.photo_album_outlined,
          color: Theme.of(context).colorScheme.outline),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(square ? 999 : 14),
              child: AspectRatio(
                aspectRatio: 1,
                child: imageUrl == null
                    ? placeholder
                    : Image.network(imageUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                        errorBuilder: (a, b, c) => placeholder),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: square ? TextAlign.center : TextAlign.start,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text('$count',
              textAlign: square ? TextAlign.center : TextAlign.start,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.note});
  final IconData icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(note,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}
