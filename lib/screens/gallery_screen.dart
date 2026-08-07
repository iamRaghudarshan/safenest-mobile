/// The gallery, shaped like Google Photos.
///
/// WHAT "LIKE GOOGLE PHOTOS" ACTUALLY MEANS HERE, mechanically:
///
///   * Photos grouped by the day they were TAKEN, newest first, with a sticky
///     date header — not one flat grid. `taken_at` on the server already drives
///     this, and it is the EXIF date rather than the upload date, so a photo
///     scanned in years later still lands in the right month.
///   * A tight square grid that stays smooth over tens of thousands of items,
///     which means building a slice at a time and never the whole library.
///   * Thumbnails from the server's `/thumb` variant, never the full image. A
///     full-size 12MP photo per grid cell is how a gallery screen runs a phone
///     out of memory.
///
/// AND ONE THING GOOGLE PHOTOS DOES THAT THIS DELIBERATELY WILL NOT:
/// nothing here uploads by itself the moment you open the screen. The backup is
/// something the owner starts, or schedules. An app that quietly copies a
/// person's whole camera roll somewhere the moment it is launched is exactly
/// what people are right to be suspicious of, and this product's entire argument
/// is that it is not that.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../widgets/photo_tile.dart';
import 'photo_viewer.dart';

class Photo {
  Photo(this.id, this.url, this.thumbUrl, this.takenAt, this.isFavourite);
  final int id;
  /// Full size — for the viewer only. The grid must never load these.
  final String url;
  final String thumbUrl;
  final DateTime? takenAt;
  final bool isFavourite;

  Photo copyWith({bool? isFavourite}) =>
      Photo(id, url, thumbUrl, takenAt, isFavourite ?? this.isFavourite);

  static Photo fromJson(Map<String, dynamic> j) => Photo(
        j['id'] as int,
        (j['url'] ?? '') as String,
        (j['thumb_url'] ?? '') as String,
        DateTime.tryParse((j['taken_at'] ?? '') as String),
        (j['is_favourite'] ?? j['is_favorite'] ?? 0) == 1,
      );
}

/// One day's photos, which is the unit the grid is built from.
class DayGroup {
  DayGroup(this.day, this.photos);
  final DateTime day;
  final List<Photo> photos;
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, this.embedded = false});

  /// Inside PhotosHome's tab view the section already has an AppBar and tabs, so
  /// the grid must not draw a second one on top of them.
  final bool embedded;
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const _page = 150;

  final _scroll = ScrollController();
  final _search = TextEditingController();
  final List<Photo> _photos = [];
  int _total = 0;
  int _offset = 0;
  bool _loading = true;
  bool _more = false;
  bool _done = false;
  String? _error;

  // Typing must not become a request per keystroke; the committed term lags the
  // field by a beat, the same way the web app does it.
  String _query = '';
  bool _smart = false;
  bool _favesOnly = false;
  Timer? _debounce;

  void _typed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (v.trim() == _query) return;
      setState(() => _query = v.trim());
      _load(reset: true);
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // Fetch the next page before the person reaches the bottom, so the grid
      // never visibly stops. 1200px is roughly three rows of headroom.
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 1200) {
        _load();
      }
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_more || (_done && !reset)) return;
    setState(() {
      _more = true;
      if (reset) {
        _loading = true;
        _error = null;
      }
    });
    try {
      final api = context.read<Session>().api;
      final off = reset ? 0 : _offset;
      final d = await api.get('/api/gallery', {
        'offset': '$off',
        'limit': '$_page',
        if (_query.isNotEmpty) 'q': _query,
        // Content search, using the CLIP embeddings the server already builds.
        // Only offered once there are enough photos for the scores to mean
        // anything — see CLIP_MIN_LIBRARY on the server.
        if (_query.isNotEmpty && _smart) 'smart': '1',
        if (_favesOnly) 'fav': '1',
      });
      final items = ((d as Map)['items'] as List)
          .map((e) => Photo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      setState(() {
        if (reset) _photos.clear();
        _photos.addAll(items);
        _total = (d['total'] ?? 0) as int;
        _offset = off + items.length;
        _done = items.length < _page;
        _loading = false;
        _more = false;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
        _more = false;
      });
    }
  }

  /// Photos into days. Anything without a date goes under "Undated" rather than
  /// being dropped — a photo you cannot see is worse than one filed oddly.
  List<DayGroup> get _grouped {
    final map = <DateTime, List<Photo>>{};
    for (final p in _photos) {
      final d = p.takenAt == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime(p.takenAt!.year, p.takenAt!.month, p.takenAt!.day);
      map.putIfAbsent(d, () => []).add(p);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in keys) DayGroup(k, map[k]!)];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);   // required by AutomaticKeepAliveClientMixin
    final groups = _grouped;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            if (!widget.embedded)
              SliverAppBar.large(
                title: const Text('Photos'),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: _typed,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: _smart
                            ? 'Describe it — beach, cake, my dog'
                            : 'Search by name, person, album or year',
                        prefixIcon: Icon(_smart ? Icons.auto_awesome : Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                  _load(reset: true);
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      FilterChip(
                        label: const Text('★ Favourites'),
                        selected: _favesOnly,
                        onSelected: (v) {
                          setState(() => _favesOnly = v);
                          _load(reset: true);
                        },
                      ),
                      // Content search is only meaningful with a search term —
                      // offering it against an empty box would return nothing
                      // and look broken.
                      FilterChip(
                        label: const Text('✨ What’s in the photo'),
                        selected: _smart,
                        onSelected: (v) {
                          setState(() => _smart = v);
                          if (_query.isNotEmpty) _load(reset: true);
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              SliverFillRemaining(child: _Message(text: _error!, onRetry: () => _load(reset: true)))
            else if (_photos.isEmpty)
              const SliverFillRemaining(
                child: _Message(
                    text: 'No photos here yet.\n\n'
                        'Tap the cloud button to back up this phone — '
                        'it takes the whole library, not a selection.'),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('$_total photos',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              for (final g in groups) ...[
                SliverToBoxAdapter(child: _DayHeader(day: g.day)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => PhotoTile(
                        photo: g.photos[i],
                        // Opened against the WHOLE loaded list, not just this
                        // day, so swiping carries on across dates the way it
                        // does in any gallery worth the name.
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PhotoViewer(
                              photos: _photos,
                              initialIndex: _photos.indexOf(g.photos[i]),
                              onChanged: () => _load(reset: true),
                            ),
                          ),
                        ),
                      ),
                      childCount: g.photos.length,
                    ),
                  ),
                ),
              ],
              if (_more)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final label = day.millisecondsSinceEpoch == 0
        ? 'Undated'
        : day == today
            ? 'Today'
            : day == today.subtract(const Duration(days: 1))
                ? 'Yesterday'
                : day.year == now.year
                    ? '${day.day} ${months[day.month - 1]}'
                    : '${day.day} ${months[day.month - 1]} ${day.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      );
}
