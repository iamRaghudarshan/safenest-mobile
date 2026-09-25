/// Correcting a grouping the computer got wrong.
///
/// WHY THIS IS THE SCREEN THAT MATTERS. Automatic grouping will always get
/// some faces wrong: the threshold loose enough never to split one person in
/// two would also merge siblings. So the question is not whether it makes
/// mistakes — it is whether a person can fix them. "Group again" re-runs the
/// rule; this is where a human overrules it.
///
/// THREE REPAIRS, AND THEY ARE NOT THE SAME.
///
///   MERGE — the same person, filed as several. The commonest by far, because
///   one face at several angles becomes several groups.
///
///   SPLIT — two people filed as one. Renaming cannot fix that; only taking
///   the wrong faces out can. It takes FACE ids, not photo ids, because a
///   group shot holds several faces and only one of them is the mistake.
///
///   DETACH — not a person at all: a face on a poster, a reflection, the
///   photograph on somebody's ID card.
///
/// Every one of them moves a LINK. No face, no embedding and no photograph is
/// deleted by anything on this screen, which is what makes it safe to
/// experiment with — a correction can itself be corrected.
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/face_circle.dart';

class PersonFacesScreen extends StatefulWidget {
  const PersonFacesScreen({
    super.key,
    required this.api,
    required this.personId,
    required this.name,
    required this.baseUrl,
    this.people = const [],
  });

  final Api api;
  final int personId;
  final String name;
  final String baseUrl;

  /// Everyone else, for "merge into" and "this face is actually…".
  final List<Map<String, dynamic>> people;

  @override
  State<PersonFacesScreen> createState() => _PersonFacesScreenState();
}

class _PersonFacesScreenState extends State<PersonFacesScreen> {
  List<Map<String, dynamic>> _faces = const [];
  final Set<int> _picked = <int>{};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  bool get _selecting => _picked.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _abs(String u) => u.startsWith('http') ? u : '${widget.baseUrl}$u';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.get('/api/people/${widget.personId}/faces');
      if (!mounted) return;
      setState(() {
        _faces = [
          for (final e in ((r as Map)['items'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map)
        ];
        _picked.removeWhere(
            (id) => !_faces.any((f) => (f['face_id'] as num).toInt() == id));
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.status == 404
            ? 'Your computer needs its SafeNest updated for this.'
            : e.message;
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------ repairs

  Future<void> _split() async {
    if (_picked.isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await widget.api.post(
          '/api/people/${widget.personId}/split', {'face_ids': _picked.toList()});
      _changed = true;
      final n = ((r as Map)['moved'] as num?)?.toInt() ?? _picked.length;
      messenger.showSnackBar(SnackBar(
          content: Text('$n face${n == 1 ? '' : 's'} moved to a new person')));
      setState(_picked.clear);
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assignPicked() async {
    if (_picked.isEmpty) return;
    final target = await _choosePerson('Move these faces to…');
    if (target == null || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // One request per face: the server moves a single face at a time, and
      // batching them here would mean inventing an endpoint the web app does
      // not use either.
      for (final id in _picked.toList()) {
        await widget.api.post('/api/people/faces/$id/assign',
            {'person_id': target.$1});
      }
      _changed = true;
      messenger.showSnackBar(SnackBar(
          content: Text('Moved to ${target.$2}')));
      setState(_picked.clear);
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detachPicked() async {
    if (_picked.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not a person?'),
        content: Text(
            '${_picked.length} face${_picked.length == 1 ? '' : 's'} will stop '
            'belonging to anybody. Nothing is deleted — the photo and the face '
            'stay exactly as they are, so this can be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Detach')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      for (final id in _picked.toList()) {
        await widget.api
            .post('/api/people/faces/$id/assign', {'person_id': null});
      }
      _changed = true;
      setState(_picked.clear);
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge() async {
    final other = await _choosePerson('Which is the same person?');
    if (other == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge?'),
        content: Text('“${other.$2}” becomes part of “${widget.name}”. '
            'Faces move; no photo is deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Merge')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.post(
          '/api/people/${widget.personId}/merge', {'ids': [other.$1]});
      _changed = true;
      messenger.showSnackBar(
          SnackBar(content: Text('Merged into ${widget.name}')));
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hide() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api
          .post('/api/people/${widget.personId}/hide', {'hidden': true});
      _changed = true;
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Hidden from People. Their photos are untouched.')));
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Everyone except this person, as a sheet. Returns (id, name).
  Future<(int, String)?> _choosePerson(String title) {
    final others = widget.people
        .where((p) => (p['id'] as num).toInt() != widget.personId)
        .toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('There is nobody else to choose yet.')));
      return Future.value(null);
    }
    return showModalBottomSheet<(int, String)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: others.length,
                itemBuilder: (c, i) {
                  final p = others[i];
                  return ListTile(
                    leading: SizedBox(
                      width: 40,
                      height: 40,
                      child: FaceCircle(
                        imageUrl: p['cover_url'] == null
                            ? null
                            : _abs('${p['cover_url']}'),
                        box: p['box'] is Map
                            ? (p['box'] as Map).cast<String, dynamic>()
                            : null,
                        size: 40,
                      ),
                    ),
                    title: Text('${p['name']}'),
                    subtitle: Text('${p['count'] ?? 0} photos'),
                    onTap: () => Navigator.pop(
                        ctx, ((p['id'] as num).toInt(), '${p['name']}')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.merge_type),
            tooltip: 'Same as another person',
            onPressed: _busy ? null : _merge,
          ),
          IconButton(
            icon: const Icon(Icons.visibility_off_outlined),
            tooltip: 'Hide from People',
            onPressed: _busy ? null : _hide,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      FilledButton.tonal(
                          onPressed: _load, child: const Text('Try again')),
                    ]),
                  ),
                )
              : Column(
                  children: [
                    if (_selecting) _actionBar() else _hint(),
                    Expanded(child: _grid()),
                  ],
                ),
    );
  }

  Widget _hint() => const Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Text(
          'Tap any face that is not this person, then say where it belongs. '
          'Nothing is ever deleted here.',
          style: TextStyle(fontSize: 12.5, height: 1.4),
        ),
      );

  Widget _actionBar() {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(_picked.clear),
            ),
            Expanded(
              child: Text('${_picked.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: _busy ? null : _split,
              child: const Text('New person'),
            ),
            TextButton(
              onPressed: _busy ? null : _assignPicked,
              child: const Text('Move to…'),
            ),
            TextButton(
              onPressed: _busy ? null : _detachPicked,
              child: const Text('Not a person'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    if (_faces.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Text('No faces recorded for this person.'),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _faces.length,
      itemBuilder: (ctx, i) {
        final f = _faces[i];
        final id = (f['face_id'] as num).toInt();
        final picked = _picked.contains(id);
        return GestureDetector(
          onTap: () => setState(() {
            if (!_picked.remove(id)) _picked.add(id);
          }),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cropped to the FACE. On this screen especially: a grid of
              // identical group photographs is exactly the thing somebody
              // came here to sort out.
              FaceCircle(
                imageUrl: f['thumb_url'] == null
                    ? null
                    : _abs('${f['thumb_url']}'),
                box: f['box'] is Map
                    ? (f['box'] as Map).cast<String, dynamic>()
                    : null,
                size: 80,
              ),
              if (picked)
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(ctx).colorScheme.primary, width: 3),
                  ),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: Theme.of(ctx).colorScheme.primary,
                      child: const Icon(Icons.check,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
