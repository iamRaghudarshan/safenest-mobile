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
// BoxHitTestResult and RenderMetaData, for finding which tile a drag is over.
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../sharing.dart';
import '../widgets/selection_bar.dart';
import '../widgets/photo_tile.dart';
import 'photo_viewer.dart';

class Photo {
  Photo(this.id, this.url, this.thumbUrl, this.takenAt, this.isFavourite,
      {this.isVideo = false, this.durationMs});
  final int id;
  /// Full size — for the viewer only. The grid must never load these.
  final String url;
  final String thumbUrl;
  final DateTime? takenAt;
  final bool isFavourite;

  /// A video, whose `thumbUrl` is a still taken from it. Everything else about
  /// it — trashing, albums, favourites, the signed URLs — is identical, which
  /// is why this is a flag rather than a second kind of object.
  final bool isVideo;
  final int? durationMs;

  /// "1:04". Blank when the server could not read a duration, which happens
  /// with some containers and is not worth showing a zero for.
  String get durationLabel {
    final ms = durationMs ?? 0;
    if (ms <= 0) return '';
    final total = (ms / 1000).round();
    final m = total ~/ 60, sec = total % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  Photo copyWith({bool? isFavourite}) =>
      Photo(id, url, thumbUrl, takenAt, isFavourite ?? this.isFavourite,
          isVideo: isVideo, durationMs: durationMs);

  static Photo fromJson(Map<String, dynamic> j) => Photo(
        j['id'] as int,
        (j['url'] ?? '') as String,
        (j['thumb_url'] ?? '') as String,
        DateTime.tryParse((j['taken_at'] ?? '') as String),
        (j['is_favourite'] ?? j['is_favorite'] ?? 0) == 1,
        isVideo: '${j['kind'] ?? 'photo'}' == 'video',
        durationMs: j['duration_ms'] is int ? j['duration_ms'] as int : null,
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

  /// '' for everything, 'photos' or 'videos'. Mutually exclusive rather than
  /// two checkboxes: "neither" and "both" mean the same thing and offering
  /// four states for two answers is how a filter row becomes a puzzle.
  String _mediaKind = '';
  Timer? _debounce;

  // ------------------------------------------------------------ selection ---
  //
  // The backend has supported this all along and the phone never used it:
  // /albums/{id}/photos and /albums/{id}/remove both take a LIST of photo_ids,
  // and album creation takes one too — its own comment says "creating an album
  // straight from a selection is the common case". There was simply no way to
  // select anything, so none of it was reachable.
  //
  // Ids rather than Photo objects: the list is reloaded after every action and
  // the objects replaced, so holding them would leave a selection pointing at
  // rows that no longer exist.
  final Set<int> _selected = {};
  bool _busy = false;

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(Photo p) => setState(() {
        if (!_selected.remove(p.id)) _selected.add(p.id);
      });

  void _clearSelection() => setState(_selected.clear);

  /// Whether this drag is selecting or clearing.
  ///
  /// Decided by the FIRST photo the finger lands on: start on an unselected
  /// one and the drag selects; start on a selected one and it clears. Toggling
  /// each tile as it is crossed instead would make a drag that wobbles back
  /// over its own path undo itself, which feels broken and is easy to do.
  bool? _dragMode;

  /// The photo id under a point on screen, or null.
  ///
  /// Hit-tests for the MetaData wrapper each tile carries. The alternative —
  /// working out a row and column from the offset — cannot survive this grid:
  /// it is several slivers with date headers between them, so the arithmetic
  /// is wrong at exactly the boundaries a drag crosses.
  int? _photoIdAt(Offset globalPosition) {
    final result = BoxHitTestResult();
    WidgetsBinding.instance.renderViews.first
        .hitTest(result, position: globalPosition);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData) {
        final data = target.metaData;
        if (data is int) return data;
      }
    }
    return null;
  }

  void _dragSelectStart(Offset at) {
    final id = _photoIdAt(at);
    if (id == null) return;
    _dragMode = !_selected.contains(id);
    setState(() {
      if (_dragMode!) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _dragSelectMove(Offset at) {
    if (_dragMode == null) return;
    final id = _photoIdAt(at);
    if (id == null) return;
    // Nothing to do if this tile is already in the state the drag is applying.
    // Without this, every pointer move rebuilds the whole grid — several times
    // a second, over thousands of tiles.
    if (_dragMode! == _selected.contains(id)) return;
    setState(() {
      if (_dragMode!) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  /// Every photo currently LOADED. Deliberately not "every photo you own": the
  /// grid pages, and an action on ten thousand rows somebody has never laid
  /// eyes on is not what they meant by "select all".
  void _selectAllLoaded() =>
      setState(() => _selected.addAll(_photos.map((p) => p.id)));

  /// Runs an action over the selection, then reloads and clears.
  ///
  /// One place, so every action reports the same way and none of them can
  /// forget to clear a selection that now points at trashed rows.
  Future<void> _run(String verb, Future<void> Function(List<int> ids) act) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await act(ids);
      _selected.clear();
      await _load(reset: true);
      messenger.showSnackBar(SnackBar(
          content: Text('$verb ${ids.length} '
              '${ids.length == 1 ? "photo" : "photos"}')));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $n ${n == 1 ? "photo" : "photos"}?'),
        // Not destructive, and saying so is the difference between somebody
        // tapping it and somebody backing out of a screen they wanted.
        content: const Text(
            'They go to Recently deleted, where you can put them back. '
            'Nothing is removed from this phone — only from your computer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = context.read<Session>().api;
    // One call per photo: DELETE /api/gallery/{id} takes a single id. Sent
    // four at a time rather than all at once — the same pacing the backup uses,
    // and for the same reason.
    await _run('Deleted', (ids) async {
      for (var i = 0; i < ids.length; i += 4) {
        await Future.wait(
            ids.skip(i).take(4).map((id) => api.delete('/api/gallery/$id')));
      }
    });
  }

  /// Send the selection out of the app.
  ///
  /// Not through _run(): sharing changes nothing on the server, so reloading
  /// the grid and clearing the selection afterwards would be undoing work the
  /// person may want to carry on with.
  Future<void> _shareSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<Session>().api;
    final chosen = _photos.where((p) => ids.contains(p.id)).toList();

    setState(() => _busy = true);
    final problem = await shareFromServer(
      api,
      items: [
        for (var i = 0; i < chosen.length; i++)
          (path: chosen[i].url, name: 'photo_${i + 1}.jpg')
      ],
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _favouriteSelected() async {
    final api = context.read<Session>().api;
    await _run('Starred', (ids) async {
      for (var i = 0; i < ids.length; i += 4) {
        await Future.wait(ids
            .skip(i)
            .take(4)
            .map((id) => api.post('/api/gallery/$id/favourite')));
      }
    });
  }

  /// Add to an existing album, or make one from the selection.
  Future<void> _addToAlbum() async {
    final session = context.read<Session>();
    final messenger = ScaffoldMessenger.of(context);

    List<Map<String, dynamic>> albums = const [];
    try {
      final d = await session.api.get('/api/gallery/albums');
      final raw = d is Map ? (d['items'] ?? d['albums'] ?? const []) : const [];
      albums = [
        for (final e in (raw as List)) Map<String, dynamic>.from(e as Map)
      ];
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;

    final choice = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AlbumPicker(albums: albums, count: _selected.length),
    );
    if (choice == null || !mounted) return;

    final api = context.read<Session>().api;
    if (choice['new'] == true) {
      await _run('Added', (ids) async {
        // Creating an album WITH the photos in one call — the endpoint takes
        // photo_ids for exactly this, so there is no window where the album
        // exists empty.
        await api.post('/api/gallery/albums',
            {'name': choice['name'], 'photo_ids': ids});
      });
    } else {
      await _run('Added', (ids) async {
        await api.post(
            '/api/gallery/albums/${choice['id']}/photos', {'photo_ids': ids});
      });
    }
  }

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
        if (_mediaKind.isNotEmpty) 'kind': _mediaKind,
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
      // The action bar only exists while something is selected, and it sits at
      // the BOTTOM — on a phone the top of the screen is out of thumb reach,
      // and these are the actions you take repeatedly.
      bottomNavigationBar: _selecting
          ? SelectionBar(
              count: _selected.length,
              busy: _busy,
              onClear: _clearSelection,
              onSelectAll: _selectAllLoaded,
              onDelete: _deleteSelected,
              onAlbum: _addToAlbum,
              onFavourite: _favouriteSelected,
              onShare: _shareSelected,
            )
          : null,
      // PRESS AND DRAG TO SELECT, the way every photo app does it.
      //
      // Selecting a holiday meant tapping forty times. The long-press already
      // started selection and then let go of the gesture, so the obvious next
      // motion — keep holding, slide across the ones you want — did nothing.
      //
      // It is a LONG-press drag, not a plain drag, so an ordinary swipe still
      // scrolls the grid. Which tile is under the finger is found by hit-testing
      // for the MetaData wrapper on each tile rather than by computing grid
      // arithmetic: the grid is several slivers with date headers between them,
      // so any sum of row heights would be wrong at exactly the boundaries
      // people drag across.
      body: GestureDetector(
        onLongPressStart: (d) => _dragSelectStart(d.globalPosition),
        onLongPressMoveUpdate: (d) => _dragSelectMove(d.globalPosition),
        onLongPressEnd: (_) => _dragMode = null,
        onLongPressCancel: () => _dragMode = null,
        child: RefreshIndicator(
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
                      // Photos and videos are one library, filtered — not two
                      // tabs. They were taken on the same day and belong next
                      // to each other; the filter is for the times you want
                      // only one of them.
                      FilterChip(
                        label: const Text('🖼 Photos'),
                        selected: _mediaKind == 'photos',
                        onSelected: (v) {
                          setState(() => _mediaKind = v ? 'photos' : '');
                          _load(reset: true);
                        },
                      ),
                      FilterChip(
                        label: const Text('🎬 Videos'),
                        selected: _mediaKind == 'videos',
                        onSelected: (v) {
                          setState(() => _mediaKind = v ? 'videos' : '');
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
                      // MetaData carries the id into the render tree so a drag
                      // can hit-test for it. `opaque` so the tile is found even
                      // where its child would not itself be hit.
                      (ctx, i) => MetaData(
                        metaData: g.photos[i].id,
                        behavior: HitTestBehavior.opaque,
                        child: PhotoTile(
                        photo: g.photos[i],
                        selecting: _selecting,
                        selected: _selected.contains(g.photos[i].id),
                        // While selecting, a tap TOGGLES rather than opening.
                        // That is the convention on both platforms and the one
                        // thing here that must not surprise anybody.
                        //
                        // Opened against the WHOLE loaded list, not just this
                        // day, so swiping carries on across dates the way it
                        // does in any gallery worth the name.
                        onOpen: () {
                          if (_selecting) {
                            _toggle(g.photos[i]);
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PhotoViewer(
                                photos: _photos,
                                initialIndex: _photos.indexOf(g.photos[i]),
                                onChanged: () => _load(reset: true),
                              ),
                            ),
                          );
                        },
                        // No onLongPress here: the grid's own long-press
                        // handles it, and two long-press recognisers competing
                        // for the same gesture means the drag never starts.
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
