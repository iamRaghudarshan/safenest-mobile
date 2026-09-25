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

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../widgets/face_circle.dart';
import 'saved_search_sheet.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/photo_tile.dart';
import 'gallery_screen.dart';
import 'person_faces.dart';
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

  /// Albums the library already implies, which nobody has accepted yet.
  ///
  /// SUGGESTIONS, NOT ALBUMS. Nothing is created until one is tapped, because
  /// a gallery that quietly grows albums nobody asked for is a mess to undo —
  /// and the one thing worse than not offering this is offering it by making
  /// twelve albums on somebody's behalf.
  List<Map<String, dynamic>> _suggested = const [];
  bool _suggesting = false;

  /// Dismissed for this visit only, and deliberately not remembered.
  ///
  /// A suggestion is recomputed from the photos every time, so "never show me
  /// this again" would need a store of its own keyed on something that has no
  /// stable identity — the group changes the moment a photo is added to it.
  /// Hiding it until the screen is left is honest about what it can promise.
  final Set<String> _waved = <String>{};

  Future<void> _loadSuggestions() async {
    setState(() => _suggesting = true);
    try {
      final r =
          await context.read<Session>().api.get('/api/gallery/albums/suggested');
      if (!mounted) return;
      setState(() {
        _suggested = [
          for (final e in ((r as Map)['suggestions'] as List? ?? const []))
            if ((e as Map)['exists'] != true) Map<String, dynamic>.from(e)
        ];
        _suggesting = false;
      });
    } on ApiError {
      // Silent. This is an offer, not a feature that was asked for — an error
      // banner over a suggestion nobody requested is pure noise, and an older
      // computer simply answers 404 here.
      if (mounted) setState(() => _suggesting = false);
    }
  }

  Future<void> _accept(Map<String, dynamic> s) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<Session>().api;
    try {
      await api.post('/api/gallery/albums/suggested', {
        'name': s['name'],
        'photo_ids': s['photo_ids'],
      });
      messenger.showSnackBar(
          SnackBar(content: Text('“${s['name']}” created')));
      if (!mounted) return;
      setState(() => _suggested.remove(s));
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The suggestion strip. Absent entirely when there is nothing to suggest —
  /// an empty "Suggested" heading is a promise the screen cannot keep.
  Widget _suggestionStrip() {
    final live = [
      for (final s in _suggested)
        if (!_waved.contains('${s['name']}')) s
    ];
    if (live.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: Row(children: [
            const Icon(Icons.auto_awesome, size: 16),
            const SizedBox(width: 6),
            Text('Suggested albums',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            itemCount: live.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final s = live[i];
              final count = (s['count'] ?? 0) as int;
              return SizedBox(
                width: 150,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: s['cover_url'] == null
                            ? Container(
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .surfaceContainerHighest)
                            : Image.network(_abs(ctx, '${s['cover_url']}'),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox()),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                        child: Text('${s['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                            '$count ${count == 1 ? 'photo' : 'photos'}',
                            style: Theme.of(ctx).textTheme.labelSmall),
                      ),
                      Row(children: [
                        TextButton(
                          onPressed: () =>
                              setState(() => _waved.add('${s['name']}')),
                          child: const Text('No',
                              style: TextStyle(fontSize: 12)),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _accept(s),
                          child: const Text('Create',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ]),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Make an album that is a QUESTION rather than a list.
  ///
  /// "Photos, 2024, beach" answers itself every time it is opened, so a photo
  /// taken tomorrow that matches appears without anybody filing it. The phone
  /// could already SHOW these — the server returns them among the albums —
  /// but there was no way to make one except on the computer.
  ///
  /// The rule is CHOSEN, never typed. A rule somebody types is a rule they
  /// can spell wrong, and a saved search that quietly matches nothing because
  /// of a typo is the worst version of this feature.
  Future<void> _newSavedSearch() async {
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);

    // Only the labels this library actually contains. Offering "desert" to
    // somebody with no desert photographs is how a picker becomes a list of
    // dead ends.
    List<Map<String, dynamic>> labels = const [];
    try {
      final r = await api.get('/api/gallery/labels');
      labels = [
        for (final e in ((r as Map)['items'] as List? ?? const []))
          Map<String, dynamic>.from(e as Map)
      ];
    } on ApiError catch (e) {
      if (e.status == 404) {
        messenger.showSnackBar(const SnackBar(
            content:
                Text('Your computer needs its SafeNest updated for this.')));
        return;
      }
    }
    if (!mounted) return;

    final made = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SavedSearchSheet(api: api, labels: labels),
    );
    if (made == true && mounted) await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (!_suggesting && _suggested.isEmpty) unawaited(_loadSuggestions());
    try {
      final d = await context.read<Session>().api.get('/api/gallery/albums');
      setState(() {
        _albums = [
          for (final a in ((d as Map)['albums'] as List? ?? const []))
            Map<String, dynamic>.from(a as Map),
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
      return Column(children: [
        _newRow(),
        _suggestionStrip(),
        const Expanded(
          child: _Empty(
            icon: Icons.photo_album_outlined,
            title: 'No albums yet',
            // The note used to say albums are made on the computer. A saved
            // search can now be made here, so saying otherwise would send
            // somebody to the wrong machine.
            note: 'Make a saved search here, or an album on the computer.',
          ),
        ),
      ]);
    }
    return Column(children: [
      _newRow(),
      _suggestionStrip(),
      Expanded(
        child: RefreshIndicator(
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
          final smart = a['smart'] == true;
          return _Cover(
            title: '${a['name'] ?? 'Album'}',
            count: (a['count'] ?? 0) as int,
            note: smart ? '${a['rule_text'] ?? 'saved search'}' : null,
            badge: smart ? Icons.search : null,
            imageUrl: a['cover_url'] == null
                ? null
                : _abs(ctx, '${a['cover_url']}'),
            square: false,
            onTap: () => Navigator.of(ctx)
                .push(
                  MaterialPageRoute(
                    builder: (_) => CollectionScreen(
                      title: '${a['name'] ?? 'Album'}',
                      // /api/gallery/albums/{id} answers {id, name, count} and NO
                      // photos — so this screen fetched an album and rendered an
                      // empty grid. The photos come from the main index with an
                      // album filter, which is what the web app uses too.
                      path: '/api/gallery?album=${a['id']}',
                      // A SAVED SEARCH has no membership to edit: nothing was
                      // ever filed into it, so "add" would write to a list
                      // this view does not read and "remove" would look
                      // broken when the rule put the photo straight back.
                      albumId: smart ? null : a['id'] as int?,
                    ),
                  ),
                )
                .then((_) => _load()),
          );
        },
      ),
        ),
      ),
    ]);
  }

  /// The one control that makes a saved search here rather than only on the
  /// computer. A row, not a floating button: it belongs with the albums it
  /// adds to, and a FAB would sit over the last row of covers.
  Widget _newRow() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 8, top: 4),
        child: TextButton.icon(
          onPressed: _newSavedSearch,
          icon: const Icon(Icons.saved_search, size: 18),
          label: const Text('Saved search'),
        ),
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

  // Face-finding: kicked off from this screen and polled for progress. The server
  // has had /api/gallery/index (start) and its GET (status) all along; the phone
  // just never offered a "do it now" or showed how it was getting on.
  bool _scanning = false;
  Map<String, dynamic> _scan = const {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _checkScan(); // if a pass is already running, pick up its progress
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _beginPolling(Map<String, dynamic> first) {
    if (!mounted) return;
    setState(() {
      _scan = first;
      _scanning = true;
    });
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pollScan());
  }

  Future<void> _checkScan() async {
    try {
      final d = await context.read<Session>().api.get('/api/gallery/index');
      final m = d is Map
          ? Map<String, dynamic>.from(d)
          : const <String, dynamic>{};
      if (m['running'] == true) _beginPolling(m);
    } catch (_) {
      /* offline — nothing to show */
    }
  }

  Future<void> _startScan({bool rebuild = false}) async {
    try {
      final d = await context.read<Session>().api.post('/api/gallery/index', {
        'jobs': const ['faces'],
        if (rebuild) 'rebuild': true,
      });
      _beginPolling(d is Map ? Map<String, dynamic>.from(d) : const {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start — check your computer is awake.'),
          ),
        );
      }
    }
  }

  Future<void> _pollScan() async {
    try {
      final d = await context.read<Session>().api.get('/api/gallery/index');
      if (!mounted) return;
      final m = d is Map
          ? Map<String, dynamic>.from(d)
          : const <String, dynamic>{};
      final running = m['running'] == true;
      setState(() {
        _scan = m;
        _scanning = running;
      });
      if (!running) {
        _poll?.cancel();
        _poll = null;
        await _load(); // the new grouping is ready
      }
    } catch (_) {
      /* transient; keep polling */
    }
  }

  Future<void> _stopScan() async {
    _poll?.cancel();
    _poll = null;
    setState(() => _scanning = false);
    try {
      await context.read<Session>().api.post('/api/gallery/index/stop', null);
    } catch (_) {}
    _load();
  }

  /// A banner while a scan runs, or a quiet "scan again" button once there are
  /// people. The empty state has its own, more prominent button.
  Widget _scanHeader() {
    final theme = Theme.of(context);
    if (_scanning) {
      final done = (_scan['done'] ?? 0) as int;
      final total = (_scan['total'] ?? 0) as int;
      final found = (_scan['people'] ?? _scan['faces_found'] ?? 0) as int;
      return Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 2),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: kModuleColours['gallery']!.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.face_retouching_natural, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    total > 0
                        ? 'Finding people… $done of $total · $found so far'
                        : 'Finding people…',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(onPressed: _stopScan, child: const Text('Stop')),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? (done / total).clamp(0.0, 1.0) : null,
                minHeight: 4,
              ),
            ),
          ],
        ),
      );
    }
    if (_people.isNotEmpty) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
          child: TextButton.icon(
            onPressed: () => _startScan(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Scan for new faces'),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// A face the server has not been told a name for.
  ///
  /// It calls them "Person 3", "Person 12" and so on — a placeholder, not a
  /// name. Treating those as named would bury the ones actually worth naming
  /// among the ones already done.
  bool _isUnnamed(Map<String, dynamic> p) {
    final n = '${p['name'] ?? ''}'.trim();
    return n.isEmpty ||
        RegExp(r'^Person\s*\d+$', caseSensitive: false).hasMatch(n);
  }

  /// Name a face, or rename one. PUT /api/people/{id} has always taken this and
  /// the phone had no way to send it — so every face stayed "Person 3" for ever
  /// however many photos it appeared in.
  Future<void> _name(Map<String, dynamic> p) async {
    final unnamed = _isUnnamed(p);
    final c = TextEditingController(text: unnamed ? '' : '${p['name']}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(unnamed ? 'Who is this?' : 'Rename'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api.put('/api/people/${p['id']}', {
        'name': name,
      });
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Long-press: name, or remove the grouping.
  Future<void> _manage(Map<String, dynamic> p) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(_isUnnamed(p) ? 'Add a name' : 'Rename'),
              onTap: () => Navigator.pop(ctx, 'name'),
            ),
            // The repair tools. "Group again" re-runs the rule; this is where
            // a person overrules it, and without it a wrong grouping has no
            // answer at all beyond deleting the person and starting over.
            ListTile(
              leading: const Icon(Icons.face_retouching_natural),
              title: const Text('Review faces'),
              subtitle: const Text('Merge, split, or move a face that is '
                  'somebody else'),
              onTap: () => Navigator.pop(ctx, 'faces'),
            ),
            // "This is me" — the one person the library can treat specially.
            //
            // Cleared from everybody else by the server, because two "me"s
            // makes "photos of me" meaningless and the second one is always
            // the mistake.
            if (!_isUnnamed(p))
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('This is me'),
                onTap: () => Navigator.pop(ctx, 'me'),
              ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: kDanger),
              title: const Text('Remove this person'),
              // Says exactly what goes, because "remove person" beside a grid of
              // faces reads as deleting their photographs.
              subtitle: const Text('The grouping goes. The photos stay.'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'name') return _name(p);
    if (choice == 'faces') return _reviewFaces(p);
    if (choice == 'me') return _markMe(p);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this person?'),
        content: const Text(
          'They stop being grouped as one person. Every photo they are in '
          'stays exactly where it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api.delete('/api/people/${p['id']}');
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _markMe(Map<String, dynamic> p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api
          .post('/api/people/${p['id']}/me', const {});
      messenger.showSnackBar(
          SnackBar(content: Text('${p['name']} is you')));
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.status == 404
              ? 'Your computer needs its SafeNest updated for this.'
              : e.message)));
    }
  }

  /// Every face filed under one person, and the tools to move them.
  ///
  /// It is handed the whole people list because both repairs need somewhere to
  /// put a face: merging asks which other person is the same one, and moving a
  /// single face asks who it really is. Fetching that list again inside the
  /// screen would show a different set from the one just tapped.
  Future<void> _reviewFaces(Map<String, dynamic> p) async {
    final session = context.read<Session>();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PersonFacesScreen(
          api: session.api,
          personId: (p['id'] as num).toInt(),
          name: _isUnnamed(p) ? 'Unnamed person' : '${p['name']}',
          baseUrl: session.baseUrl ?? '',
          people: _people,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  /// Group every face again, using the current rule.
  ///
  /// WHY THIS BUTTON EXISTS. Grouping happens once, as each photo is indexed,
  /// and never revisits its own decisions — so a library grouped by an older,
  /// worse rule stays that way for ever. Improving the rule does nothing for
  /// the photographs already in.
  ///
  /// It asks first, with the numbers, because this rewrites every grouping in
  /// the library. Names are kept whatever the answer: named people are used
  /// as anchors, and only faces that match nobody named are grouped afresh.
  Future<void> _regroup() async {
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic>? preview;
    try {
      final r = await api.post('/api/people/regroup', {'dry_run': true});
      preview = (r as Map).cast<String, dynamic>();
    } on ApiError catch (e) {
      // 404 means the computer is running an older SafeNest that has no such
      // route — worth saying plainly rather than "something went wrong".
      messenger.showSnackBar(SnackBar(
        content: Text(e.status == 404
            ? 'Your computer needs its SafeNest updated for this.'
            : e.message),
      ));
      return;
    }
    if (!mounted) return;

    final moved = (preview['moved'] as num?)?.toInt() ?? 0;
    final before = (preview['people_before'] as num?)?.toInt() ?? 0;
    final after = (preview['people_after'] as num?)?.toInt() ?? 0;
    if (moved == 0) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Nothing would change — the grouping is already '
              'what the current rule gives.')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Group faces again?'),
        content: Text(
          '$moved face${moved == 1 ? '' : 's'} would move, and you would go '
          'from $before ${before == 1 ? 'person' : 'people'} to $after.\n\n'
          'Names you have given are kept.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Leave it')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Group again')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    messenger.showSnackBar(const SnackBar(content: Text('Grouping…')));
    try {
      final r = await api.post('/api/people/regroup', const {}) as Map;
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Done — ${r['people_after']} '
            '${(r['people_after'] as num?) == 1 ? 'person' : 'people'}'),
      ));
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/people');
      setState(() {
        _people = [
          for (final p in ((d as Map)['people'] as List? ?? const []))
            Map<String, dynamic>.from(p as Map),
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
    return Column(
      children: [
        _scanHeader(),
        // Offered only once there is something to regroup. On an empty or
        // barely-indexed library it would be a button that reports "nothing
        // would change", which teaches people to ignore it.
        if (_people.length > 1 && !_scanning)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _regroup,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Group again'),
              ),
            ),
          ),
        Expanded(child: _content(context)),
      ],
    );
  }

  Widget _content(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _Retry(message: _error!, onRetry: _load);
    if (_people.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline, size: 44),
              const SizedBox(height: 14),
              const Text(
                'No people found yet',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan your backed-up photos for faces — it runs on your computer '
                'and groups the people it finds.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _scanning ? null : () => _startScan(),
                icon: const Icon(Icons.face_retouching_natural),
                label: Text(_scanning ? 'Finding people…' : 'Find people'),
              ),
            ],
          ),
        ),
      );
    }
    // GOOGLE PHOTOS SHAPES A FACE AS A CIRCLE, and it is not decoration: a
    // square crop of a face reads as a photograph of a person, a circle reads
    // as a person. Four across rather than three, because the name matters more
    // than the size of the crop.
    //
    // Unnamed faces come FIRST. The server names them "Person 3" and so on,
    // which tells nobody anything — putting them at the top with "Add a name"
    // is what turns face detection into something useful, and it is exactly
    // what Google Photos does with them.
    final named = _people.where((p) => !_isUnnamed(p)).toList();
    final unnamed = _people.where(_isUnnamed).toList();
    final ordered = [...unnamed, ...named];

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        // Cells are deliberately tall enough for a 66px face plus two text lines
        // even at a large system text scale: at 0.72 the avatar + name + count
        // summed a few pixels past the cell and bottom-overflowed. 0.64 leaves
        // real slack rather than fitting to the pixel.
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 10,
          mainAxisSpacing: 16,
          childAspectRatio: 0.64,
        ),
        itemCount: ordered.length,
        itemBuilder: (ctx, i) {
          final p = ordered[i];
          final unnamedOne = _isUnnamed(p);
          final count = (p['count'] ?? 0) as int;
          return GestureDetector(
            // An unnamed face asks who it is; a named one opens their photos.
            // Tapping "Add a name" and being shown a grid instead would be the
            // one thing on this screen that ignores what it says.
            onTap: () => unnamedOne
                ? _name(p)
                : Navigator.of(ctx)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => CollectionScreen(
                            title: '${p['name'] ?? 'Someone'}',
                            path: '/api/people/${p['id']}/photos',
                          ),
                        ),
                      )
                      .then((_) => _load()),
            onLongPress: () => _manage(p),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(
                          ctx,
                        ).colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: unnamedOne
                              ? kBrand.withValues(alpha: 0.55)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      // The FACE, not the middle of the photograph it came
                      // from. The server sends where it is; without that this
                      // circle showed a shoulder on any group shot.
                      child: FaceCircle(
                        imageUrl: p['cover_url'] == null
                            ? null
                            : _abs(ctx, '${p['cover_url']}'),
                        box: p['box'] is Map
                            ? (p['box'] as Map).cast<String, dynamic>()
                            : null,
                        // 66 to match the container it fills — a smaller
                        // value leaves a ring of background inside the border.
                        size: 66,
                      ),
                    ),
                    if (unnamedOne)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: kBrand,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  unnamedOne ? 'Add a name' : '${p['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: unnamedOne ? kBrand : null,
                  ),
                ),
                Text('$count', style: Theme.of(ctx).textTheme.labelSmall),
              ],
            ),
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
            Map<String, dynamic>.from(g as Map),
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
        note:
            'Once you have photos from previous years, this shows what you '
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
              child: Text(
                '${g['label']}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(
              height: 132,
              child: Builder(
                builder: (ctx) {
                  final items = [
                    for (final e in (g['items'] as List? ?? const []))
                      Photo.fromJson(Map<String, dynamic>.from(e as Map)),
                  ];
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: items.length,
                    separatorBuilder: (_, i) => const SizedBox(width: 8),
                    itemBuilder: (c2, i) => GestureDetector(
                      onTap: () => Navigator.of(c2).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PhotoViewer(photos: items, initialIndex: i),
                        ),
                      ),
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
                            color: Theme.of(
                              c2,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
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
  const CollectionScreen({
    super.key,
    required this.title,
    required this.path,
    this.albumId,
    this.initialPhotos,
  });
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

  /// "Uploading 3 of 12…" while photos from the phone stream in. A line over
  /// the grid rather than a dialog, so the album stays visible as it fills.
  String? _addNote;

  static const _pageSize = 120;
  int _offset = 0;
  int? _total;
  bool _hasMore = true;
  bool _loadingMore = false;

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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api.put(
        '/api/gallery/albums/${widget.albumId}',
        {'name': name},
      );
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
          'deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete album'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<Session>().api.delete(
        '/api/gallery/albums/${widget.albumId}',
      );
      navigator.pop(true);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// "Add photos" has two answers — photos the app already holds, and photos
  /// still on the phone — and which one someone means is not guessable, so a
  /// sheet asks. Only albums get this; a person's photos are computed.
  Future<void> _addMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from your gallery'),
              subtitle: const Text('Photos already in the app'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Upload from this phone'),
              subtitle: const Text('Straight into this album'),
              onTap: () => Navigator.pop(ctx, 'phone'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'gallery') await _addFromGallery();
    if (choice == 'phone') await _addFromPhone();
  }

  Future<void> _addFromGallery() async {
    final ids = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => const AlbumAddPicker()),
    );
    if (ids == null || ids.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final d = await context.read<Session>().api.post(
        '/api/gallery/albums/${widget.albumId}/photos',
        {'photo_ids': ids},
      );
      await _load();
      // The server reports what it actually added; photos that were already in
      // the album are skipped there, and saying "added 0" for a re-pick is the
      // honest outcome rather than a fault.
      final added = (d is Map ? d['added'] : null) ?? ids.length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            added == 0
                ? 'Those photos were already in this album'
                : 'Added $added photo${added == 1 ? '' : 's'}',
          ),
        ),
      );
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromPhone() async {
    // Static in file_picker 11, and withData false on purpose — the bytes are
    // read one file at a time below, not all at once into memory. Same shape as
    // the Documents upload, which is the proven path.
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.media,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<Session>().api;
    final total = picked.files.length;
    var done = 0, dupes = 0, failed = 0;
    // What actually got stored, so the album can be filled from the ids rather
    // than from the server having honoured album_id. See the attach below.
    final uploaded = <int>[];
    for (final (i, f) in picked.files.indexed) {
      final path = f.path;
      if (path == null) {
        failed++;
        continue;
      }
      if (mounted) {
        setState(() => _addNote = 'Uploading ${i + 1} of $total…');
      }
      try {
        final bytes = await File(path).readAsBytes();
        // The album is attached by the SERVER (album_id on the upload), so a
        // photo the library already holds still lands in the album — the
        // upload comes back duplicate:true with the existing photo attached.
        final d = await api.postMultipartJson(
          '/api/gallery/upload?faces=0&album_id=${widget.albumId}',
          fileField: 'file',
          filename: f.name,
          bytes: bytes,
        );
        done++;
        if (d is Map && d['duplicate'] == true) dupes++;
        final item = d is Map ? d['item'] : null;
        final id = item is Map ? (item['id'] as num?)?.toInt() : null;
        if (id != null) uploaded.add(id);
      } on ApiError {
        failed++;
      } catch (_) {
        failed++;
      }
    }
    // PUT THEM IN THE ALBUM FROM HERE, rather than trusting album_id.
    //
    // The upload carries album_id, but this app talks to whatever server version
    // the owner happens to be running, and an older one does not know that
    // parameter — FastAPI ignores a query parameter no argument claims, so the
    // photos uploaded perfectly and the album stayed empty with nothing anywhere
    // saying why. Reported exactly that way: two photos sent from the phone,
    // both in the gallery, the album still reading "0 photos".
    //
    // /albums/{id}/photos has existed as long as albums have, so this works
    // against every server. Adding a photo already in the album is a no-op
    // server-side, so doing both costs nothing where album_id WAS honoured.
    var attached = true;
    if (uploaded.isNotEmpty) {
      try {
        await api.post('/api/gallery/albums/${widget.albumId}/photos', {
          'photo_ids': uploaded,
        });
      } catch (_) {
        attached = false;
      }
    }

    if (!mounted) return;
    setState(() => _addNote = null);
    await _load();
    final also = dupes > 0 ? ' ($dupes already in your gallery)' : '';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          !attached
              // The photos are safe; they are just not where they were asked to
              // go, which is a different problem from an upload that failed.
              ? 'Uploaded $done, but they could not be put in this album'
              : failed == 0
              ? 'Added $done photo${done == 1 ? '' : 's'} to this album$also'
              : 'Added $done$also — $failed could not be sent',
        ),
      ),
    );
  }

  Future<void> _removeSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await context.read<Session>().api.post(
        '/api/gallery/albums/${widget.albumId}/remove',
        {'photo_ids': ids},
      );
      _selected.clear();
      await _load();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${ids.length} from this album — '
            'still in your gallery',
          ),
        ),
      );
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One page at a time.
  ///
  /// This used to fetch `widget.path` once and render whatever came back. The
  /// server answers 150 by default, so any collection bigger than that showed
  /// its first 150 photos, gave no sign there were more, and looked exactly
  /// like a complete collection — a silent truncation of somebody's own
  /// records. It mattered little when this screen only held albums; it holds
  /// favourites, places and "recently added" now, and those are the ones that
  /// grow without anyone curating them.
  Future<void> _load({bool more = false}) async {
    if (more && (_loadingMore || !_hasMore)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _offset = 0;
        _hasMore = true;
      }
    });
    try {
      // The paths here already carry a query string as often as not
      // (`?album=3`, `?fav=1`, `?near=…`), so the separator has to be worked
      // out rather than assumed. Appending a second `?` produces a request the
      // server reads as one enormous parameter name and answers with page one
      // for ever.
      final sep = widget.path.contains('?') ? '&' : '?';
      final start = more ? _offset : 0;
      final d = await context.read<Session>().api.get(
        '${widget.path}${sep}offset=$start&limit=$_pageSize',
      );
      // Albums answer {album:…, items:[…]}, people answer {items:[…]}, and a
      // bare list is possible too. Accepting all three beats guessing one.
      final list = d is List
          ? d
          : (d is Map ? (d['items'] ?? d['photos'] ?? const []) : const []);
      final page = [
        for (final e in (list as List))
          Photo.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      if (!mounted) return;

      // An endpoint that does not understand `offset` answers the second page
      // with the first one — and appending that would duplicate every photo
      // and ask again for ever, which on a phone means a grid that grows until
      // it runs out of memory. This app talks to whatever server version the
      // owner happens to be running, and older builds of `/api/people/{id}/
      // photos` took no offset at all, so the guard is not theoretical.
      final known = _photos.map((p) => p.id).toSet();
      final fresh = more
          ? page.where((p) => !known.contains(p.id)).toList()
          : page;
      final ignoredOffset = more && page.isNotEmpty && fresh.isEmpty;

      setState(() {
        if (more) {
          _photos.addAll(fresh);
        } else {
          _photos = fresh;
        }
        _offset = _photos.length;
        // An endpoint that reports a total is believed; one that does not is
        // judged by whether the page came back full.
        final total = d is Map ? d['total'] : null;
        _total = total is int ? total : null;
        _hasMore = ignoredOffset
            ? false
            : (_total != null
                  ? _photos.length < _total!
                  : page.length >= _pageSize);
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        // A failure part-way through must not throw away the pages already on
        // screen — that turns a flaky connection into "my album emptied".
        if (!more) _error = e.message;
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
      });
      if (more) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
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
            IconButton(
              tooltip: 'Add photos',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _addNote != null ? null : _addMenu,
            ),
          if (_isAlbum && !_selecting)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'rename' ? _rename() : _deleteAlbum(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename album')),
                PopupMenuItem(value: 'delete', child: Text('Delete album')),
              ],
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            // "12 of 340" while more is still to come. A bare count that is
            // really a page count is the thing this screen used to get wrong.
            child: Text(
              _total != null && _total! > _photos.length
                  ? '${_photos.length} of $_total'
                  : '${_photos.length} photos',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Cancel',
                          onPressed: _busy
                              ? null
                              : () => setState(_selected.clear),
                          icon: const Icon(Icons.close),
                        ),
                        Expanded(
                          child: Text(
                            '${_selected.length} selected',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                  ],
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _Retry(message: _error!, onRetry: _load)
          : Column(
              children: [
                if (_addNote != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _addNote!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                Expanded(child: _grid(context)),
              ],
            ),
    );
  }

  Widget _grid(BuildContext context) {
    return _photos.isEmpty
        ? _Empty(
            icon: Icons.photo_outlined,
            title: 'Nothing here',
            note: _isAlbum
                ? 'Use ＋ to put photos in this album.'
                : 'This collection has no photos in it.',
          )
        : GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: _photos.length,
            // PhotoTile rather than a bare Image: it already knows
            // how to be selected, caps its decode, and shows a
            // broken-image glyph instead of a grey square. Three
            // behaviours that were reimplemented worse here.
            itemBuilder: (ctx, i) {
              // Fetch the next page while there is still a screenful
              // left to scroll, so the grid never stops under a
              // finger. The builder is the trigger rather than a
              // scroll listener because it fires for exactly the
              // tiles being laid out, whatever the row height
              // happens to be.
              if (i >= _photos.length - 12 && _hasMore && !_loadingMore) {
                // After this frame: calling setState from inside a
                // build is an error, and _load does.
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _load(more: true),
                );
              }
              return PhotoTile(
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
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => PhotoViewer(
                        photos: _photos,
                        initialIndex: i,
                        onChanged: _load,
                      ),
                    ),
                  );
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
              );
            },
          );
  }
}

/// ------------------------------------------------------- add-to-album picker

/// Multi-select over the whole gallery, for putting existing photos into an
/// album. Pops with the chosen ids; the CALLER does the adding, so this screen
/// needs to know nothing about which album it is feeding.
class AlbumAddPicker extends StatefulWidget {
  const AlbumAddPicker({super.key, this.initialPhotos});

  /// For tests — lay the screen out without a server.
  final List<Photo>? initialPhotos;

  @override
  State<AlbumAddPicker> createState() => _AlbumAddPickerState();
}

class _AlbumAddPickerState extends State<AlbumAddPicker> {
  List<Photo> _photos = [];
  bool _loading = true;
  String? _error;
  final Set<int> _selected = {};

  static const _pageSize = 120;
  int _offset = 0;
  int? _total;
  bool _hasMore = true;
  bool _loadingMore = false;

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

  Future<void> _load({bool more = false}) async {
    if (more && (_loadingMore || !_hasMore)) return;
    setState(() => more ? _loadingMore = true : _loading = true);
    try {
      final start = more ? _offset : 0;
      final d = await context.read<Session>().api.get(
        '/api/gallery?offset=$start&limit=$_pageSize',
      );
      final list = d is Map ? (d['items'] ?? const []) : const [];
      final page = [
        for (final e in (list as List))
          Photo.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      if (!mounted) return;
      setState(() {
        if (more) {
          final known = _photos.map((p) => p.id).toSet();
          _photos.addAll(page.where((p) => !known.contains(p.id)));
        } else {
          _photos = page;
        }
        _offset = _photos.length;
        final total = d is Map ? d['total'] : null;
        _total = total is int ? total : null;
        _hasMore = _total != null
            ? _photos.length < _total!
            : page.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        if (!more) _error = e.message;
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _selected.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add to album'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              n == 0 ? 'Tap the photos to add' : '$n selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: BrandButton(
            label: n == 0 ? 'Add photos' : 'Add $n photo${n == 1 ? '' : 's'}',
            icon: Icons.playlist_add,
            block: true,
            onPressed: n == 0
                ? null
                : () => Navigator.pop(context, _selected.toList()),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _Retry(message: _error!, onRetry: _load)
          : _photos.isEmpty
          ? const _Empty(
              icon: Icons.photo_outlined,
              title: 'No photos yet',
              note: 'Photos you add to the app will appear here.',
            )
          : GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: _photos.length,
              itemBuilder: (ctx, i) {
                if (i >= _photos.length - 12 && _hasMore && !_loadingMore) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _load(more: true),
                  );
                }
                // Always in selection mode: tapping picks, it never
                // opens the viewer. Choosing is the whole screen.
                return PhotoTile(
                  photo: _photos[i],
                  selecting: true,
                  selected: _selected.contains(_photos[i].id),
                  onOpen: () => setState(() {
                    if (!_selected.remove(_photos[i].id)) {
                      _selected.add(_photos[i].id);
                    }
                  }),
                );
              },
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
    this.note,
    this.badge,
  });
  final String title;
  final int count;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool square;

  /// Replaces the photo count. Used for a SAVED SEARCH, where the rule is the
  /// useful line: an album that fills itself for reasons nobody can see is one
  /// people stop trusting, and when it shows the wrong photos this is the only
  /// way to tell why.
  final String? note;

  /// A small mark over the cover, saying this album answers a question rather
  /// than holding a list.
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        square ? Icons.person : Icons.photo_album_outlined,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(square ? 999 : 14),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: imageUrl == null
                      ? placeholder
                      : Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          errorBuilder: (a, b, c) => placeholder,
                        ),
                ),
              ),
              if (badge != null)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0x8C000000),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(badge, size: 13, color: Colors.white),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: square ? TextAlign.center : TextAlign.start,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          Text(
            // The RULE where there is one, because it says why these photos
            // are here; the count otherwise.
            note ?? '$count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: square ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            note,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
