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

import 'dart:math' as math;

import 'package:flutter/material.dart';
// BoxHitTestResult and RenderMetaData, for finding which tile a drag is over.
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../dates.dart';
import '../session.dart';
import '../sharing.dart';
import '../widgets/date_scrubber.dart';
import '../widgets/selection_bar.dart';
import '../widgets/photo_tile.dart';
import 'library_tabs.dart';
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
  // How many of the library are videos — so the header can say "N photos · M
  // videos" instead of labelling a grid full of clips "photos". Only meaningful
  // (and only fetched) on the plain library view.
  int _videoTotal = 0;
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

  /// Which face the grid is narrowed to, and their name for the chip.
  ///
  /// WHY A FACE AND NOT A NAME. The text search already matches a person's
  /// name — and the clustering names nobody. It calls them "Person 3",
  /// "Person 12", and those are most of them, so "search by person" was
  /// reachable only for faces somebody had already gone and named. Tapping a
  /// face needs no name to exist.
  int _personId = 0;
  String _personName = '';
  List<Map<String, dynamic>> _people = [];
  bool _peopleTried = false;

  /// Newest BACKED UP first rather than newest taken. A genuinely different
  /// order: a photo scanned in years later sorts by its EXIF date everywhere
  /// else, deliberately, so the default ordering cannot answer this at all.
  bool _recent = false;

  /// How many photos fit across. Changed by pinching.
  ///
  /// Three is the default because it is what a phone gallery looks like. Two
  /// is for looking at pictures, five and seven are for finding one — at seven
  /// a year of photographs is a few flicks rather than a few minutes.
  static const _colChoices = [2, 3, 5, 7];
  int _cols = 3;

  /// A one-per-row list instead of the grid — the "List" view. Pinch still works
  /// on the grid; this is the explicit alternative the view switcher offers.
  bool _listView = false;

  /// The column count when the current pinch began, so the gesture is measured
  /// from where it started rather than compounding each frame — without this a
  /// slow spread races from seven to two and back.
  int? _pinchFrom;

  /// The month a given fraction down the grid lands in.
  ///
  /// Worked out from the LOADED photos rather than from pixel offsets: the grid
  /// is many slivers of different heights with headers between them, so any
  /// arithmetic on scroll extent is approximate — but the list of photos in
  /// order is exact, and the fraction indexes straight into it.
  ///
  /// Only what has been fetched so far is in that list, which is honest: the
  /// rail cannot travel to a month the app has not loaded yet either.
  String _dateAtFraction(double f) {
    if (_photos.isEmpty) return '';
    final i = (f * (_photos.length - 1)).round().clamp(0, _photos.length - 1);
    final d = _photos[i].takenAt;
    if (d == null) return 'Undated';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    // The year is what people are aiming for over a long library, so it is
    // always there — "Aug" alone is ambiguous across ten years of photos.
    return '${months[d.month - 1]} ${d.year}';
  }

  void _pinch(ScaleUpdateDetails d) {
    final from = _pinchFrom;
    if (from == null || d.pointerCount < 2) return;
    // Spreading (scale > 1) means fewer, bigger tiles.
    final steps = (math.log(d.scale) / math.ln2 * 1.6).round();
    final i = (_colChoices.indexOf(from) - steps)
        .clamp(0, _colChoices.length - 1);
    if (_colChoices[i] != _cols) {
      setState(() => _cols = _colChoices[i]);
    }
  }

  /// List / small / medium / large — an explicit alternative to the pinch gesture.
  Widget _viewSwitcher() {
    final cs = Theme.of(context).colorScheme;
    final grid = !_listView;
    Widget btn(IconData ic, bool on, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(ic, size: 18, color: on ? Colors.white : cs.onSurfaceVariant),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        btn(Icons.view_list, _listView, () => setState(() => _listView = true)),
        btn(Icons.grid_on, grid && _cols >= 5, () => setState(() { _listView = false; _cols = 5; })),
        btn(Icons.grid_view, grid && _cols == 3, () => setState(() { _listView = false; _cols = 3; })),
        btn(Icons.crop_square, grid && _cols == 2, () => setState(() { _listView = false; _cols = 2; })),
      ]),
    );
  }

  /// Every quick filter behind ONE menu, instead of a wrapping row of chips that
  /// filled half the screen. The button shows how many filters are on; the person
  /// chip stays separate because it is a filter you remove, not one you pick.
  Widget _filterBar() {
    final cs = Theme.of(context).colorScheme;
    final active = (_favesOnly ? 1 : 0) +
        (_mediaKind.isNotEmpty ? 1 : 0) +
        (_recent ? 1 : 0);
    return Row(children: [
      if (_personId != 0) ...[
        InputChip(
          avatar: const Icon(Icons.person, size: 18),
          label: Text(_personName.isEmpty ? 'This person' : _personName),
          onDeleted: () {
            setState(() {
              _personId = 0;
              _personName = '';
            });
            _load(reset: true);
          },
        ),
        const SizedBox(width: 8),
      ],
      PopupMenuButton<String>(
        tooltip: 'Filter photos',
        onSelected: (v) {
          setState(() {
            switch (v) {
              case 'fav':
                _favesOnly = !_favesOnly;
              case 'photos':
                _mediaKind = _mediaKind == 'photos' ? '' : 'photos';
              case 'videos':
                _mediaKind = _mediaKind == 'videos' ? '' : 'videos';
              case 'screenshots':
                _mediaKind = _mediaKind == 'screenshots' ? '' : 'screenshots';
              case 'recent':
                _recent = !_recent;
              case 'clear':
                _favesOnly = false;
                _mediaKind = '';
                _recent = false;
            }
          });
          _load(reset: true);
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(value: 'fav', checked: _favesOnly, child: const Text('Favourites')),
          CheckedPopupMenuItem(value: 'photos', checked: _mediaKind == 'photos', child: const Text('Photos only')),
          CheckedPopupMenuItem(value: 'videos', checked: _mediaKind == 'videos', child: const Text('Videos only')),
          CheckedPopupMenuItem(value: 'screenshots', checked: _mediaKind == 'screenshots', child: const Text('Screenshots')),
          CheckedPopupMenuItem(value: 'recent', checked: _recent, child: const Text('Recently added')),
          if (active > 0) const PopupMenuDivider(),
          if (active > 0) const PopupMenuItem(value: 'clear', child: Text('Clear filters')),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: active > 0 ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tune, size: 18, color: active > 0 ? Colors.white : cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(active > 0 ? 'Filter · $active' : 'Filter',
                style: TextStyle(fontWeight: FontWeight.w600, color: active > 0 ? Colors.white : cs.onSurface)),
          ]),
        ),
      ),
      const Spacer(),
      FilterChip(
        label: const Text('✨ Smart'),
        selected: _smart,
        onSelected: (v) {
          setState(() => _smart = v);
          if (_query.isNotEmpty) _load(reset: true);
        },
      ),
    ]);
  }

  /// One day's photos as a list of rows (used when _listView is on).
  Widget _daySliverList(List<Photo> photos) {
    // Same URL rule PhotoTile uses: an absolute thumb URL as-is, a relative one
    // prefixed with the server address. The signed token rides in the query
    // string, so no auth header is needed.
    final base = context.read<Session>().baseUrl ?? '';
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final p = photos[i];
          final url = p.thumbUrl.startsWith('http') ? p.thumbUrl : '$base${p.thumbUrl}';
          final sub = [
            if (p.takenAt != null) fmtDate(p.takenAt),
            if (p.isVideo && p.durationLabel.isNotEmpty) p.durationLabel,
          ].join(' · ');
          return InkWell(
            onTap: () {
              if (_selecting) {
                _toggle(p);
                return;
              }
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PhotoViewer(
                  photos: _photos,
                  initialIndex: _photos.indexOf(p),
                  onChanged: () => _load(reset: true),
                ),
              ));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(alignment: Alignment.bottomRight, children: [
                    Image.network(url,
                        width: 56, height: 56, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                            width: 56,
                            height: 56,
                            color: Colors.black26,
                            child: Icon(p.isVideo ? Icons.videocam : Icons.image,
                                color: Colors.white38))),
                    if (p.isVideo)
                      const Padding(
                          padding: EdgeInsets.all(3),
                          child: Icon(Icons.play_circle_fill, size: 16, color: Colors.white)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.isVideo ? 'Video' : 'Photo',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ]),
                ),
                if (_selected.contains(p.id))
                  Icon(Icons.check_circle, size: 20, color: Theme.of(ctx).colorScheme.primary)
                else if (p.isFavourite)
                  const Icon(Icons.star, size: 16, color: Color(0xFFFFCF4D)),
              ]),
            ),
          );
        },
        childCount: photos.length,
      ),
    );
  }

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
    _loadPeople();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Which request is the current one.
  ///
  /// Bumped on every load. A response whose number is no longer current is
  /// thrown away — without it, changing a filter while a page is in flight lets
  /// the OLD page arrive after the list has been cleared and append photos the
  /// new filter excludes.
  int _loadSeq = 0;

  /// The plain library view — no filter, search, favourites, person or "recently
  /// added". Only here does the "photos · videos" split make sense; a filtered
  /// view shows a single count for what it is showing.
  bool get _plainView =>
      _mediaKind.isEmpty && _query.isEmpty && !_favesOnly && _personId == 0 && !_recent;

  String _plural(int n, String w) => '$n $w${n == 1 ? '' : 's'}';

  /// The header count. A grid full of clips must not be called "photos".
  String _countLabel() {
    if (_mediaKind == 'videos') return _plural(_total, 'video');
    if (_mediaKind == 'photos') return _plural(_total, 'photo');
    if (_mediaKind == 'screenshots') return _plural(_total, 'screenshot');
    if (_plainView && _videoTotal > 0) {
      final photos = (_total - _videoTotal).clamp(0, _total);
      return '${_plural(photos, 'photo')} · ${_plural(_videoTotal, 'video')}';
    }
    return _plural(_total, _plainView ? 'photo' : 'item');
  }

  Future<void> _load({bool reset = false}) async {
    // A RESET IS NEVER DROPPED. This read `if (_more || ...)`, so a filter tap
    // that landed while a page was being fetched returned immediately and did
    // nothing at all — no request, no error, the chip simply lit up and the
    // grid stayed as it was.
    //
    // With eight hundred photos the grid is fetching almost constantly, so that
    // was most taps. It looked exactly like the filter not being implemented.
    if (!reset && (_more || _done)) return;
    final seq = ++_loadSeq;
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
        if (_personId != 0) 'person': '$_personId',
        if (_recent) 'sort': 'added',
      });
      final items = ((d as Map)['items'] as List)
          .map((e) => Photo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      // A response from a filter the person has already moved on from must not
      // be shown. Checked after the await, which is the only place it can be.
      if (seq != _loadSeq) return;
      setState(() {
        if (reset) _photos.clear();
        _photos.addAll(items);
        _total = (d['total'] ?? 0) as int;
        _offset = off + items.length;
        _done = items.length < _page;
        _loading = false;
        _more = false;
      });
      // On the plain library view, also count the videos so the header can split
      // "photos · videos". Cosmetic and best-effort — a failure just leaves the
      // header on the combined count.
      if (reset && _plainView) {
        try {
          final vd = await api.get('/api/gallery', {'limit': '1', 'kind': 'videos'});
          if (seq == _loadSeq && mounted) {
            setState(() => _videoTotal = ((vd as Map)['total'] ?? 0) as int);
          }
        } catch (_) {/* header count is cosmetic */}
      } else if (reset) {
        _videoTotal = 0;
      }
    } on ApiError catch (e) {
      if (seq != _loadSeq) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _more = false;
      });
    }
  }

  /// The faces to offer along the top, most-photographed first.
  ///
  /// Loaded once and separately from the grid: it is a different endpoint and
  /// a slow or empty answer must not hold up the photos. A library that has
  /// not been indexed yet has no people at all, and the strip simply does not
  /// appear — an empty row of circles reads as broken.
  Future<void> _loadPeople() async {
    if (_peopleTried) return;
    _peopleTried = true;
    try {
      final r = await context.read<Session>().api.get('/api/people?limit=40');
      final list = (r is Map ? r['people'] as List? : null) ?? const [];
      if (!mounted) return;
      setState(() => _people = [
            for (final e in list)
              if (e is Map) Map<String, dynamic>.from(e)
          ]);
    } catch (_) {
      // Faces are an extra. The gallery works without them.
    }
  }

  /// Photos into days. Anything without a date goes under "Undated" rather than
  /// being dropped — a photo you cannot see is worse than one filed oddly.
  /// Zoomed out, the grouping widens to the MONTH.
  ///
  /// Day headers are right at two or three across, where a day is a row or
  /// two. At seven across a day is often a single half-empty row, so the
  /// screen becomes more header than photograph and scrolling a year takes
  /// hundreds of them. Pinching out is a request to see more at once, and
  /// keeping day headers is the one thing that stops it delivering that.
  bool get _byMonth => _cols >= 5;

  // Memoised, because build() reads it every frame. Grouping thousands of photos
  // into days and sorting the keys on each rebuild — and a rebuild fires on every
  // drag-select move, pinch and page-append — was the scroll stutter. The result
  // only changes when the photo list or the day/month split changes, so it is
  // recomputed only then. Identity of the first and last photo catches a filter
  // reset that happens to return the same COUNT (different photos, same length).
  List<DayGroup>? _groupCache;
  int _groupKeyLen = -1;
  bool _groupKeyByMonth = false;
  Photo? _groupKeyFirst;
  Photo? _groupKeyLast;

  List<DayGroup> get _grouped {
    final n = _photos.length;
    final first = n > 0 ? _photos.first : null;
    final last = n > 0 ? _photos.last : null;
    if (_groupCache != null &&
        _groupKeyLen == n &&
        _groupKeyByMonth == _byMonth &&
        identical(_groupKeyFirst, first) &&
        identical(_groupKeyLast, last)) {
      return _groupCache!;
    }
    final map = <DateTime, List<Photo>>{};
    for (final p in _photos) {
      final t = p.takenAt;
      final d = t == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : _byMonth
              ? DateTime(t.year, t.month)
              : DateTime(t.year, t.month, t.day);
      map.putIfAbsent(d, () => []).add(p);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    final result = [for (final k in keys) DayGroup(k, map[k]!)];
    _groupCache = result;
    _groupKeyLen = n;
    _groupKeyByMonth = _byMonth;
    _groupKeyFirst = first;
    _groupKeyLast = last;
    return result;
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
      // The scrubber floats OVER the grid rather than beside it, so the photos
      // keep the full width. It hides itself when there is not enough to
      // scroll through — a rail next to forty photos is clutter over a problem
      // nobody has.
      body: Stack(children: [
        GestureDetector(
        onLongPressStart: (d) => _dragSelectStart(d.globalPosition),
        onLongPressMoveUpdate: (d) => _dragSelectMove(d.globalPosition),
        onLongPressEnd: (_) => _dragMode = null,
        onLongPressCancel: () => _dragMode = null,
        // PINCH TO CHANGE HOW MANY FIT ACROSS, the way every phone gallery
        // does. Spreading two fingers makes the photos bigger, pinching them
        // together fits more on screen — which is how you find one picture in
        // four thousand without scrolling past all of them.
        //
        // Guarded on pointerCount >= 2: a single-finger drag is the scroll, and
        // a scale recogniser that accepts one pointer eats it.
        onScaleStart: (d) => _pinchFrom = d.pointerCount >= 2 ? _cols : null,
        onScaleUpdate: _pinch,
        onScaleEnd: (_) => _pinchFrom = null,
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
                    // Only when there is something to view — no point offering
                    // list/grid on an empty gallery, and keeping it out of the
                    // empty layout is what lets the header fit an iPhone SE.
                    if (_photos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _viewSwitcher(),
                    ],
                    // WHO IS IN THIS LIBRARY — the answer the search box
                    // could not give. Tap a face to narrow the grid to them.
                    if (_people.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      // A named row with a way through to the full People screen,
                      // where faces are named and managed. That screen used to be
                      // two levels down (Collections → See all); here it is one tap.
                      Row(children: [
                        Text('People',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text('People')),
                                  body: const PeopleTab(),
                                ),
                              ))
                              .then((_) => _loadPeople()),
                          style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 32)),
                          child: const Text('See all'),
                        ),
                      ]),
                      SizedBox(
                        height: 78,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _people.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (ctx, i) {
                            final person = _people[i];
                            final id = (person['id'] as num?)?.toInt() ?? 0;
                            return _FaceChip(
                              person: person,
                              selected: _personId == id,
                              onTap: () {
                                setState(() {
                                  // Tapping the selected face clears it, so the
                                  // way out is the same control as the way in.
                                  if (_personId == id) {
                                    _personId = 0;
                                    _personName = '';
                                  } else {
                                    _personId = id;
                                    _personName = '${person['name'] ?? ''}'.trim();
                                  }
                                });
                                _load(reset: true);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                    // One tidy filter row — and only when there is something to
                    // filter (or a filter is already on), so an empty gallery is
                    // not buried under chips.
                    if (_photos.isNotEmpty ||
                        _favesOnly ||
                        _mediaKind.isNotEmpty ||
                        _recent ||
                        _personId != 0) ...[
                      const SizedBox(height: 8),
                      _filterBar(),
                    ],
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
                  child: Text(_countLabel(),
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              // Each date section is its own SliverMainAxisGroup so its header
              // pins to the top like Google Photos — sticking while that month
              // is on screen and being pushed up by the next, rather than
              // scrolling away (which is what a plain adapter header did, despite
              // this file long claiming otherwise).
              for (final g in groups)
                SliverMainAxisGroup(slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyHeaderDelegate(
                        day: g.day, monthOnly: _byMonth),
                  ),
                  SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  sliver: _listView
                      ? _daySliverList(g.photos)
                      : SliverGrid(
                    // Not const — the column count is a pinch away from
                    // changing, which is the whole point.
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _cols,
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
              ]),
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
        DateScrubber(controller: _scroll, labelAt: _dateAtFraction),
      ]),
    );
  }
}

/// Pins a date header to the top while its section is on screen, the way Google
/// Photos does. Opaque, because the photos scroll underneath it and a see-through
/// bar over them reads as a rendering glitch.
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.day, required this.monthOnly});
  final DateTime day;
  final bool monthOnly;

  @override
  double get minExtent => 46;
  @override
  double get maxExtent => 46;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return ClipRect(
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        alignment: Alignment.centerLeft,
        child: _DayHeader(day: day, monthOnly: monthOnly),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate old) =>
      old.day != day || old.monthOnly != monthOnly;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, this.monthOnly = false});
  final DateTime day;
  final bool monthOnly;

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
        : monthOnly
        ? (day.year == now.year
            ? months[day.month - 1]
            : '${months[day.month - 1]} ${day.year}')
        : day == today
            ? 'Today'
            : day == today.subtract(const Duration(days: 1))
                ? 'Yesterday'
                : day.year == now.year
                    ? '${day.day} ${months[day.month - 1]}'
                    : '${day.day} ${months[day.month - 1]} ${day.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

/// One face along the top of the gallery.
///
/// The name is shown when there is one. The clustering calls unnamed faces
/// "Person 3", which is not a name and is worth nothing under a picture of
/// somebody — the count is the thing that helps you recognise which face you
/// are looking for, so that is what goes there instead.
class _FaceChip extends StatelessWidget {
  const _FaceChip({required this.person, required this.selected, required this.onTap});
  final Map<String, dynamic> person;
  final bool selected;
  final VoidCallback onTap;

  bool get _unnamed {
    final n = '${person['name'] ?? ''}'.trim();
    return n.isEmpty || RegExp(r'^Person\s*\d+$', caseSensitive: false).hasMatch(n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = person['cover_url'] as String?;
    final count = (person['count'] as num?)?.toInt() ?? 0;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? theme.colorScheme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: ClipOval(
              child: url == null
                  ? Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.person, size: 26))
                  : Image.network(url,
                      fit: BoxFit.cover,
                      // A face that will not load must not leave a broken-image
                      // glyph where somebody's photograph should be.
                      errorBuilder: (_, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, size: 26))),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _unnamed ? '$count' : '${person['name']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ]),
      ),
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
