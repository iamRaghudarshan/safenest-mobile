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
import 'gallery_screen.dart' show Photo;
import 'photo_editor.dart';
import 'video_trim.dart';
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

  /// Out of the timeline, still in the library.
  ///
  /// NOT A BIN, and the wording has to carry that or nobody will use it: an
  /// archived photo keeps its albums, its faces and its search text, and the
  /// only thing it stops doing is appearing in the main grid. It is for the
  /// receipts, the screenshot of a wifi password, the twelve shots of a
  /// whiteboard — things worth keeping and not worth scrolling past daily.
  Future<void> _archive() async {
    final p = _photos[_index];
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api
          .post('/api/gallery/${p.id}/archive', const {});
      widget.onChanged?.call();
      if (!mounted) return;
      // Removed from THIS viewer as well as from the grid behind: the photo
      // is no longer in the timeline these pages came from, and leaving it
      // swipeable would let somebody archive it twice.
      setState(() {
        _photos.removeAt(_index);
        if (_index >= _photos.length) _index = _photos.length - 1;
      });
      messenger.showSnackBar(const SnackBar(
          content: Text('Archived — find it under Collections › Archive')));
      if (_photos.isEmpty && mounted) Navigator.pop(context);
    } on ApiError catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.status == 404
            ? 'Your computer needs its SafeNest updated for this.'
            : e.message),
      ));
    }
  }

  /// Crop, rotate, filter or draw on it — or, for a video, trim it.
  ///
  /// The editor returns the UPDATED item, and the viewer swaps it in rather
  /// than waiting for the grid behind to reload: the media URL keeps the same
  /// filename after an edit, so without a fresh one the browser-side cache
  /// would show the old picture and Save would appear to have done nothing.
  Future<void> _edit() async {
    final p = _photos[_index];
    final updated = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => p.isVideo
            ? VideoTrimScreen(
                api: context.read<Session>().api,
                photoId: p.id,
                videoUrl: _abs(p.url),
                durationMs: p.durationMs ?? 0,
                initial: p.edit,
              )
            : PhotoEditorScreen(
                api: context.read<Session>().api,
                photoId: p.id,
                imageUrl: _abs(p.url),
                initial: p.edit,
              ),
      ),
    );
    if (updated is! Map || !mounted) return;
    final fresh = Photo.fromJson(updated.cast<String, dynamic>());
    setState(() => _photos[_index] = fresh);
    widget.onChanged?.call();
  }

  String _abs(String u) =>
      u.startsWith('http') ? u : '${context.read<Session>().baseUrl ?? ''}$u';

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
      builder: (ctx) => _InfoSheet(
          detail: d, photo: p, api: context.read<Session>().api),
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
                        icon: p.isVideo ? Icons.content_cut : Icons.tune,
                        label: p.isVideo ? 'Trim' : 'Edit',
                        onTap: _edit),
                    _Action(
                        icon: Icons.archive_outlined,
                        label: 'Archive',
                        onTap: _archive),
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
class _InfoSheet extends StatefulWidget {
  const _InfoSheet(
      {required this.detail, required this.photo, required this.api});
  final Map<String, dynamic>? detail;
  final Photo photo;
  final Api api;

  @override
  State<_InfoSheet> createState() => _InfoSheetState();
}

class _InfoSheetState extends State<_InfoSheet> {
  Photo get photo => widget.photo;
  Map<String, dynamic>? get detail => widget.detail;

  /// Who is in the photo, as this sheet currently believes it.
  ///
  /// Held locally rather than re-read from `detail` because tagging somebody
  /// has to show on the pill row at once. Round-tripping /info after every tag
  /// would be a spinner between a tap and its result, and this is a list of
  /// names — the server's answer cannot differ from what was just sent.
  List<Map<String, dynamic>>? _people;

  List<Map<String, dynamic>> get people {
    final cached = _people;
    if (cached != null) return cached;
    final root = detail ?? const <String, dynamic>{};
    return _people = [
      for (final e in ((root['people'] as List?) ?? const []))
        Map<String, dynamic>.from(e as Map)
    ];
  }

  /// Say who this is — an existing person, or somebody new.
  ///
  /// WHY TAGGING BY HAND EXISTS AT ALL when faces are found automatically: the
  /// automatic pass only ever sees faces it can detect. A photo taken from
  /// behind, a child asleep, somebody at the far edge of a group — those are
  /// in nobody's group and never will be, and until now there was no way to
  /// say so. It is also the only way to attach a person to a photo that has
  /// no face in it at all.
  Future<void> _tag() async {
    final messenger = ScaffoldMessenger.of(context);
    List<Map<String, dynamic>> known = const [];
    try {
      final r = await widget.api.get('/api/people');
      known = [
        for (final e in ((r as Map)['people'] as List? ?? const []))
          Map<String, dynamic>.from(e as Map)
      ];
    } on ApiError {
      // An empty list still lets a NEW name be typed, which is the case that
      // matters on a library nobody has named anybody in yet.
    }
    if (!mounted) return;

    final taken = {for (final p in people) (p['id'] as num?)?.toInt()};
    final choice = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PersonPicker(
        people: [
          for (final p in known)
            if (!taken.contains((p['id'] as num?)?.toInt())) p
        ],
      ),
    );
    if (choice == null || !mounted) return;

    try {
      final r = await widget.api.post('/api/gallery/${photo.id}/tag', choice);
      final m = r is Map ? r : const {};
      setState(() => people.add({
            'id': (m['person_id'] as num?)?.toInt(),
            'name': '${m['name'] ?? choice['name'] ?? 'Someone'}',
          }));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.status == 404
              ? 'Your computer needs its SafeNest updated for this.'
              : e.message)));
    }
  }

  /// Take a name off this photo.
  ///
  /// It removes the LINK between this photo and that person — not the person,
  /// and not the photo. The wording has to carry that, because "remove" next
  /// to somebody's name reads as deleting them from the library.
  Future<void> _untag(Map<String, dynamic> person) async {
    final id = (person['id'] as num?)?.toInt();
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${person['name'] ?? 'them'} from this photo?'),
        content: const Text(
            'Only this photo stops being theirs. They stay in People, and '
            'every other photo of them is untouched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api
          .post('/api/gallery/${photo.id}/untag', {'person_id': id});
      setState(() =>
          people.removeWhere((p) => (p['id'] as num?)?.toInt() == id));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

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

        // ALWAYS shown, even with nobody in it — this is the only way to say
        // who is in a photograph the face finder missed, and a section that
        // appears only once somebody is already tagged can never be the place
        // the first tag is made.
        const SizedBox(height: 16),
        Text('People', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final pr in people)
            InputChip(
              avatar: const Icon(Icons.person_outline, size: 17),
              label: Text('${pr['name'] ?? 'Someone'}'),
              onDeleted: () => _untag(pr),
              deleteIcon: const Icon(Icons.close, size: 16),
              tooltip: 'Remove from this photo',
            ),
          ActionChip(
            avatar: const Icon(Icons.person_add_alt, size: 17),
            label: const Text('Add someone'),
            onPressed: _tag,
          ),
        ]),

        const SizedBox(height: 16),
        Text(
          'This photo is stored on your own computer.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}



/// Choose who is in a photo: somebody already known, or a new name.
///
/// THE NEW NAME COMES FIRST and is always available, because the common case
/// for hand-tagging is exactly the person the face finder has never seen — a
/// photo taken from behind, or somebody who appears once. A picker that only
/// offers existing people cannot serve that case at all.
///
/// The server takes either shape at the same endpoint: `{person_id}` picks
/// somebody known, `{name}` finds them by name or creates them. So this
/// returns whichever the person chose and lets the server reconcile it — which
/// also means typing a name that already exists attaches to that person
/// instead of making a second one with the same name.
class _PersonPicker extends StatefulWidget {
  const _PersonPicker({required this.people});
  final List<Map<String, dynamic>> people;

  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  final _name = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _isPlaceholder(String n) =>
      RegExp(r'^Person\s*\d+$', caseSensitive: false).hasMatch(n);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _filter.trim().toLowerCase();
    final shown = [
      for (final p in widget.people)
        if (q.isEmpty || '${p['name'] ?? ''}'.toLowerCase().contains(q)) p
    ];
    final typed = _name.text.trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Who is in this photo?',
              style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Type a name, or pick somebody below',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _filter = v),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              Navigator.pop(context, {'name': v.trim()});
            }
          },
        ),
        if (typed.isNotEmpty &&
            !shown.any((p) =>
                '${p['name'] ?? ''}'.toLowerCase() == typed.toLowerCase()))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt)),
            title: Text('Add “$typed”',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Somebody new'),
            onTap: () => Navigator.pop(context, {'name': typed}),
          ),
        if (shown.isNotEmpty) ...[
          const Divider(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: shown.length,
              itemBuilder: (ctx, i) {
                final p = shown[i];
                final name = '${p['name'] ?? ''}'.trim();
                final placeholder = name.isEmpty || _isPlaceholder(name);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  // An unnamed cluster is still worth offering — tagging a
                  // photo to it is a perfectly good way to say "this is that
                  // one" before deciding what to call them.
                  title: Text(placeholder ? 'Unnamed person' : name),
                  subtitle: Text('${p['count'] ?? 0} photos'),
                  onTap: () => Navigator.pop(
                      ctx, {'person_id': (p['id'] as num?)?.toInt()}),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }
}
