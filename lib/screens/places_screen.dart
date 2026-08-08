/// Where the photos were taken.
///
/// NO MAP, and that is a decision rather than a shortcut. Every map widget
/// worth using fetches its tiles from somebody else's server, and the request
/// for a tile IS the coordinate — so drawing this library on a map would send
/// a record of everywhere its owner has been to a third party, on a screen
/// whose whole selling point is that nothing leaves the machine. The server
/// names the clusters from a table compiled into it (`backend/app/places.py`)
/// and the phone shows covers, which answers "where are my photos from"
/// without asking anyone.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import 'library_tabs.dart';

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});
  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  List<Map<String, dynamic>> _places = [];
  int _located = 0;
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
      final d = await context.read<Session>().api.get('/api/gallery/places');
      if (!mounted) return;
      setState(() {
        _places = [
          for (final p in ((d as Map)['items'] as List? ?? const []))
            Map<String, dynamic>.from(p as Map)
        ];
        _located = (d['located'] ?? 0) as int;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Places'),
        bottom: _located == 0
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(26),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('$_located photos know where they were taken',
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                ),
              ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );
    }
    if (_places.isEmpty) {
      // Naming the cause matters here. "No places" reads as a fault; it is
      // almost always that the camera had location switched off, which is the
      // owner's setting and not something this app can fix for them.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.place_outlined,
                size: 46, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 14),
            const Text('No photos with a location',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'A photo only knows where it was taken if the camera recorded it. '
              'Turn on location for your camera app and photos from then on '
              'will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: _places.length,
        itemBuilder: (ctx, i) {
          final p = _places[i];
          final label = '${p['label'] ?? 'Somewhere'}';
          final region = p['region'] as String?;
          final count = (p['count'] ?? 0) as int;
          return InkWell(
            borderRadius: BorderRadius.circular(kRadius),
            onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
              builder: (_) => CollectionScreen(
                title: label,
                // The centre and the radius the server clustered with, so the
                // screen shows exactly the photos the tile counted. Passing a
                // different radius here would make the count a lie.
                path: '/api/gallery?near=${p['lat']},${p['lon']}',
              ),
            )),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kRadius),
                  child: Stack(fit: StackFit.expand, children: [
                    if (p['cover_url'] == null)
                      Container(
                          color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.place_outlined))
                    else
                      Image.network(_abs('${p['cover_url']}'),
                          fit: BoxFit.cover,
                          cacheWidth: 420,
                          errorBuilder: (_, _, _) => Container(
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.place_outlined))),
                    // A pin over the corner, so a place card is not mistaken
                    // for an album at a glance.
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.place,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 7),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13.5)),
              Text(
                  region == null
                      ? '$count ${count == 1 ? 'photo' : 'photos'}'
                      : '$region · $count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx).textTheme.labelSmall),
            ]),
          );
        },
      ),
    );
  }
}
