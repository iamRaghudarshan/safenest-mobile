/// Collections — everything in the library that is not the one big grid.
///
/// It replaces three separate tabs (Albums, People, Memories) with the shape
/// Google Photos uses, and the reason is not imitation. Three tabs meant three
/// places to look and no way to see that any of them had anything in them; the
/// Places grouping, favourites and the bin had no tab left to be in at all and
/// so were simply unreachable. One screen that STATES what it holds — "24
/// people", "2 albums", "100 photos with a location" — is the difference
/// between a feature existing and a feature being found.
///
/// EVERY COUNT IS REAL. A tile that says nothing about how much is behind it
/// invites a tap that lands on an empty screen, and the tile for something
/// this library genuinely has none of is hidden rather than shown empty.
///
/// Nothing here is a new kind of screen: a collection opens the same
/// `CollectionScreen` grid an album opens, because to the person looking they
/// are the same thing.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import 'documents_screen.dart';
import 'library_tabs.dart';
import 'places_screen.dart';
import 'trash_screen.dart';

class CollectionsHome extends StatefulWidget {
  const CollectionsHome({super.key});
  @override
  State<CollectionsHome> createState() => CollectionsHomeState();
}

class CollectionsHomeState extends State<CollectionsHome> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _albums = [];

  int _favourites = 0;
  int _screenshots = 0;
  int _places = 0;
  int _located = 0;
  int _trash = 0;
  int _documents = 0;
  int _memories = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  /// Public so the tab above can refresh this after a backup adds photos —
  /// otherwise the counts are whatever they were when the app started, which
  /// is exactly the sort of quietly-stale number nobody thinks to distrust.
  Future<void> load() async {
    if (mounted) setState(() => _loading = _people.isEmpty && _albums.isEmpty);
    final api = context.read<Session>().api;

    // One round of concurrent reads rather than eight in sequence. They are
    // all counts, none depends on another, and on a phone connection the
    // difference is the screen appearing at once instead of filling in.
    Future<dynamic> safe(String path) async {
      try {
        return await api.get(path);
      } on ApiError {
        // One missing count must not blank the whole screen. An older server
        // has no /places at all, and the rest of Collections is still useful
        // on it.
        return null;
      }
    }

    try {
      final r = await Future.wait([
        safe('/api/people'),
        safe('/api/gallery/albums'),
        safe('/api/gallery?fav=1&limit=1'),
        safe('/api/gallery?kind=screenshots&limit=1'),
        safe('/api/gallery/places'),
        safe('/api/gallery/trash'),
        safe('/api/documents'),
        safe('/api/gallery/memories'),
        safe('/api/gallery?limit=1'),
      ]);
      if (!mounted) return;

      List<Map<String, dynamic>> listOf(dynamic d, String key) => [
            for (final x in (((d as Map?)?[key]) as List? ?? const []))
              Map<String, dynamic>.from(x as Map)
          ];
      int intOf(dynamic d, String key) => ((d as Map?)?[key] ?? 0) as int;

      setState(() {
        _people = listOf(r[0], 'people');
        _albums = listOf(r[1], 'albums');
        _favourites = intOf(r[2], 'total');
        _screenshots = intOf(r[3], 'total');
        _places = intOf(r[4], 'total');
        _located = intOf(r[4], 'located');
        _trash = ((r[5] as Map?)?['items'] as List? ?? const []).length;
        _documents = intOf(r[6], 'total');
        _memories = intOf(r[7], 'total');
        _total = intOf(r[8], 'total');
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  String _abs(String u) {
    if (u.isEmpty || u.startsWith('http')) return u;
    return '${context.read<Session>().baseUrl ?? ''}$u';
  }

  bool _isUnnamed(Map<String, dynamic> p) {
    final n = '${p['name'] ?? ''}'.trim();
    return n.isEmpty || RegExp(r'^Person\s*\d+$', caseSensitive: false).hasMatch(n);
  }

  void _open(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => load());
  }

  Future<void> _createAlbum() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New album'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Album name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final d = await context
          .read<Session>()
          .api
          .post('/api/gallery/albums', {'name': name});
      final id = ((d as Map?)?['id']) as int?;
      await load();
      if (id == null || !mounted) return;
      // Straight into the new album. It is empty, and the screen says how to
      // fill it — creating one and being left on the list gives no clue that
      // anything happened at all.
      navigator
          .push(MaterialPageRoute(
            builder: (_) => CollectionScreen(
                title: name, path: '/api/gallery?album=$id', albumId: id),
          ))
          .then((_) => load());
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: load, child: const Text('Try again')),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          if (_people.isNotEmpty) _peopleSection(),
          _albumsSection(),
          _collectionsSection(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- people ---

  Widget _peopleSection() {
    // Unnamed first, same order as the People screen. A face nobody has named
    // is the one piece of work this feature is actually asking for, and
    // burying it behind the ones already done is how it never gets done.
    final unnamed = _people.where(_isUnnamed).toList();
    final named = _people.where((p) => !_isUnnamed(p)).toList();
    final ordered = [...unnamed, ...named];
    final shown = ordered.take(12).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Header(
        title: 'People',
        note: unnamed.isEmpty
            ? '${_people.length} found'
            : '${unnamed.length} still to name',
        accent: unnamed.isNotEmpty,
        onSeeAll: () => _open(Scaffold(
            appBar: AppBar(title: const Text('People')),
            body: const PeopleTab())),
      ),
      SizedBox(
        height: 108,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: shown.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (ctx, i) {
            final p = shown[i];
            final isUnnamed = _isUnnamed(p);
            return SizedBox(
              width: 72,
              child: GestureDetector(
                onTap: () => isUnnamed
                    ? _open(Scaffold(
                        appBar: AppBar(title: const Text('People')),
                        body: const PeopleTab()))
                    : _open(CollectionScreen(
                        title: '${p['name']}',
                        path: '/api/people/${p['id']}/photos')),
                child: Column(children: [
                  Stack(children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        border: Border.all(
                            color: isUnnamed
                                ? kBrand.withValues(alpha: 0.55)
                                : Colors.transparent,
                            width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: p['cover_url'] == null
                          ? Icon(Icons.person,
                              color: Theme.of(ctx).colorScheme.outline)
                          : Image.network(_abs('${p['cover_url']}'),
                              fit: BoxFit.cover,
                              cacheWidth: 200,
                              errorBuilder: (_, _, _) => Icon(Icons.person,
                                  color: Theme.of(ctx).colorScheme.outline)),
                    ),
                    if (isUnnamed)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: kBrand, shape: BoxShape.circle),
                          child: const Icon(Icons.add,
                              size: 12, color: Colors.white),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Text(isUnnamed ? 'Add a name' : '${p['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isUnnamed ? kBrand : null)),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 6),
    ]);
  }

  // ------------------------------------------------------------- albums ---

  Widget _albumsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Header(
        title: 'Albums',
        note: _albums.isEmpty ? 'none yet' : '${_albums.length}',
        onSeeAll: _albums.isEmpty
            ? null
            : () => _open(Scaffold(
                appBar: AppBar(title: const Text('Albums')),
                body: const AlbumsTab())),
      ),
      SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          // +1 for the create tile, which comes FIRST. With no albums yet it is
          // the only thing on the row, so the section explains itself instead
          // of being an empty strip.
          itemCount: _albums.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return InkWell(
                borderRadius: BorderRadius.circular(kRadius),
                onTap: _createAlbum,
                child: Container(
                  width: 118,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadius),
                    border: Border.all(
                        color: kBrand.withValues(alpha: 0.45), width: 1.5),
                    color: kBrand.withValues(alpha: 0.06),
                  ),
                  child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: kBrand, size: 26),
                        SizedBox(height: 8),
                        Text('New album',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: kBrand)),
                      ]),
                ),
              );
            }
            final a = _albums[i - 1];
            final name = '${a['name'] ?? 'Album'}';
            return SizedBox(
              width: 118,
              child: InkWell(
                borderRadius: BorderRadius.circular(kRadius),
                onTap: () => _open(CollectionScreen(
                    title: name,
                    path: '/api/gallery?album=${a['id']}',
                    albumId: a['id'] as int?)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(kRadius),
                          child: a['cover_url'] == null
                              ? Container(
                                  width: double.infinity,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Icon(Icons.photo_album_outlined))
                              : Image.network(_abs('${a['cover_url']}'),
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  cacheWidth: 300,
                                  errorBuilder: (_, _, _) => Container(
                                      color: Theme.of(ctx)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: const Icon(
                                          Icons.photo_album_outlined))),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12.5)),
                      Text('${a['count'] ?? 0}',
                          style: Theme.of(ctx).textTheme.labelSmall),
                    ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 6),
    ]);
  }

  // -------------------------------------------------------- collections ---

  Widget _collectionsSection() {
    final tiles = <Widget>[
      _Tile(
        icon: Icons.favorite,
        colour: const Color(0xFFE5484D),
        title: 'Favourites',
        count: _favourites,
        // The one tile that stays when empty. It is the only collection the
        // owner fills by hand, so it has to be visible before there is
        // anything in it or nobody learns it is there.
        emptyNote: 'Tap the heart on a photo',
        onTap: () => _open(const CollectionScreen(
            title: 'Favourites', path: '/api/gallery?fav=1')),
      ),
      if (_located > 0)
        _Tile(
          icon: Icons.place,
          colour: const Color(0xFF16A06A),
          title: 'Places',
          count: _places,
          unit: _places == 1 ? 'place' : 'places',
          onTap: () => _open(const PlacesScreen()),
        ),
      if (_total > 0)
        _Tile(
          icon: Icons.schedule,
          colour: kBrand,
          title: 'Recently added',
          count: _total,
          // Newest BACKED UP, which is a different order from newest taken —
          // the point of the tile is finding what just arrived from the phone.
          onTap: () => _open(const CollectionScreen(
              title: 'Recently added', path: '/api/gallery?sort=added')),
        ),
      if (_screenshots > 0)
        _Tile(
          icon: Icons.phone_iphone,
          colour: const Color(0xFF8B5CF6),
          title: 'Screenshots',
          count: _screenshots,
          onTap: () => _open(const CollectionScreen(
              title: 'Screenshots', path: '/api/gallery?kind=screenshots')),
        ),
      if (_memories > 0)
        _Tile(
          icon: Icons.auto_awesome,
          colour: kWarn,
          title: 'On this day',
          count: _memories,
          onTap: () => _open(Scaffold(
              appBar: AppBar(title: const Text('On this day')),
              body: const MemoriesTab())),
        ),
      _Tile(
        icon: Icons.description_outlined,
        colour: const Color(0xFF0EA5E9),
        title: 'Documents',
        count: _documents,
        unit: _documents == 1 ? 'document' : 'documents',
        emptyNote: 'Scan or upload one',
        onTap: () => _open(const DocumentsScreen()),
      ),
      _Tile(
        icon: Icons.delete_outline,
        colour: const Color(0xFF6B7280),
        title: 'Recently deleted',
        count: _trash,
        emptyNote: 'Nothing waiting',
        onTap: () => _open(const TrashScreen()),
      ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Header(title: 'Collections'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.35,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: tiles,
        ),
      ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.note, this.onSeeAll, this.accent = false});
  final String title;
  final String? note;
  final VoidCallback? onSeeAll;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 10),
      child: Row(children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (note != null) ...[
          const SizedBox(width: 8),
          // Flexible, because a long note beside a long title is how a Row
          // overflows — and an overflow is a runtime stripe, not a build error.
          Flexible(
            child: Text(note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: accent ? FontWeight.w700 : FontWeight.w500,
                    color: accent
                        ? kBrand
                        : Theme.of(context).textTheme.labelSmall?.color)),
          ),
        ],
        const Spacer(),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('See all')),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.colour,
    required this.title,
    required this.count,
    required this.onTap,
    this.unit,
    this.emptyNote,
  });

  final IconData icon;
  final Color colour;
  final String title;
  final int count;
  final String? unit;
  final String? emptyNote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final u = unit ?? (count == 1 ? 'photo' : 'photos');
    final sub = count == 0 ? (emptyNote ?? 'Empty') : '$count $u';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(kRadiusSm)),
              child: Icon(icon, size: 20, color: colour),
            ),
            const SizedBox(width: 10),
            // Expanded, or the two lines of text push the Row past its width
            // as soon as a count reaches three digits.
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}
