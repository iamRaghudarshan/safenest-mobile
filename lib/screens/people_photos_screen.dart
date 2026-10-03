/// Photos of these people together.
///
/// WHAT WAS MISSING, in the owner's words: "when selecting faces it's showing
/// that person, but in Google Photos you search the face along with another
/// person and get only the ones with both — multiple faces not working."
///
/// The capability was there and unreachable. `/api/gallery?person=1,2` has
/// always ANDed the ids server-side — the comment there says so — but nothing
/// a person could find led to it. Tapping a face in Collections opened
/// `/api/people/{id}/photos`, which takes ONE id and is a dead end: no way to
/// add a second face, no way even to see that adding one was possible. The one
/// place that could combine faces was a checklist behind the gallery's filter
/// menu, three taps down, which for anybody who never opened that menu is the
/// same as not existing.
///
/// So this screen is the answer to the question instead of a filter that
/// happens to express it. The faces you have chosen are across the top with
/// their names; "Add someone" is the next chip along; a face comes off with one
/// tap. The count says what it is showing, and when two people have never been
/// photographed together it says THAT, with the way out — because "0 photos" on
/// a screen you reached by tapping two faces is indistinguishable from a search
/// that broke.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../widgets/face_circle.dart';
import '../widgets/photo_tile.dart';
import 'gallery_screen.dart' show Photo;
import 'photo_viewer.dart';

/// Matching the server's cap: each extra face is another subquery, and a photo
/// with eight identified people in it is rare enough that nobody is filtering
/// for one.
const kMaxFaces = 8;

class PeoplePhotosScreen extends StatefulWidget {
  const PeoplePhotosScreen({
    super.key,
    required this.people,
    required this.startWith,
    this.debugPhotos,
  });

  /// Everyone the clustering has found, so another face can be added without
  /// another round trip. `{id, name, cover_url, box, count}` as /api/people
  /// returns them.
  final List<Map<String, dynamic>> people;

  /// The face that was tapped to get here.
  final int startWith;

  /// For tests and the layout sweep — lay the screen out without a server.
  final List<Photo>? debugPhotos;

  @override
  State<PeoplePhotosScreen> createState() => _PeoplePhotosScreenState();
}

class _PeoplePhotosScreenState extends State<PeoplePhotosScreen> {
  late final Set<int> _chosen = {widget.startWith};
  List<Photo> _photos = const [];
  bool _loading = true;
  String? _error;
  int? _total;

  @override
  void initState() {
    super.initState();
    if (widget.debugPhotos != null) {
      _photos = widget.debugPhotos!;
      _total = _photos.length;
      _loading = false;
      return;
    }
    _load();
  }

  Map<String, dynamic>? _person(int id) {
    for (final p in widget.people) {
      if ((p['id'] as num?)?.toInt() == id) return p;
    }
    return null;
  }

  String _nameOf(int id) {
    final p = _person(id);
    final n = '${p?['name'] ?? ''}'.trim();
    // An unnamed cluster is most of them, and "Person 7" is what the rest of
    // the app calls one.
    return n.isEmpty ? 'Person $id' : n;
  }

  String get _title {
    final names = [for (final id in _chosen) _nameOf(id)];
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names.first} and ${names.last}';
    return '${names.take(names.length - 1).join(', ')} and ${names.last}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // THE SERVER ALREADY DOES THE HARD PART. `person=1,2` means "in all of
      // these", not "in any of these" — OR would return MORE photos the more
      // faces you picked, which is the opposite of what choosing a second face
      // is for.
      final ids = _chosen.join(',');
      final d = await context
          .read<Session>()
          .api
          .get('/api/gallery?person=$ids&limit=200');
      final list = d is List
          ? d
          : (d is Map ? (d['items'] ?? d['photos'] ?? const []) : const []);
      if (!mounted) return;
      setState(() {
        _photos = [
          for (final e in (list as List))
            Photo.fromJson(Map<String, dynamic>.from(e as Map)),
        ];
        _total = d is Map && d['total'] is num
            ? (d['total'] as num).toInt()
            : _photos.length;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load these photos.';
        });
      }
    }
  }

  void _drop(int id) {
    // NEVER DOWN TO NOTHING. A screen called "Photos of" with nobody chosen has
    // no question to answer, so the last face is not removable — the way back
    // is the back arrow.
    if (_chosen.length == 1) return;
    setState(() => _chosen.remove(id));
    _load();
  }

  Future<void> _add() async {
    final others = [
      for (final p in widget.people)
        if (!_chosen.contains((p['id'] as num?)?.toInt() ?? -1)) p
    ];
    if (others.isEmpty) return;

    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickFace(people: others, with_: _title),
    );
    if (picked == null || !mounted) return;
    setState(() => _chosen.add(picked));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = context.read<Session>().baseUrl ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(_title, overflow: TextOverflow.ellipsis),
      ),
      body: Column(children: [
        _Faces(
          chosen: _chosen.toList(),
          nameOf: _nameOf,
          person: _person,
          base: base,
          onDrop: _chosen.length > 1 ? _drop : null,
          onAdd: _chosen.length < kMaxFaces &&
                  widget.people.length > _chosen.length
              ? _add
              : null,
        ),
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _chosen.length == 1
                    ? '${_total ?? _photos.length} photos'
                    : '${_total ?? _photos.length} with all of them',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _Empty(text: _error!, onRetry: _load)
                  : _photos.isEmpty
                      ? _NoneTogether(
                          names: [for (final id in _chosen) _nameOf(id)],
                          onDrop: _chosen.length > 1
                              ? () => _drop(_chosen.last)
                              : null,
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 2,
                            crossAxisSpacing: 2,
                          ),
                          itemCount: _photos.length,
                          itemBuilder: (_, i) => PhotoTile(
                            photo: _photos[i],
                            onOpen: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => PhotoViewer(
                                  photos: _photos,
                                  initialIndex: i,
                                ),
                              ),
                            ),
                          ),
                        ),
        ),
      ]),
    );
  }
}

// =============================================================== pieces

class _Faces extends StatelessWidget {
  const _Faces({
    required this.chosen,
    required this.nameOf,
    required this.person,
    required this.base,
    required this.onDrop,
    required this.onAdd,
  });

  final List<int> chosen;
  final String Function(int) nameOf;
  final Map<String, dynamic>? Function(int) person;
  final String base;
  final void Function(int)? onDrop;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        children: [
          for (final id in chosen)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: SizedBox(
                width: 68,
                child: Column(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surfaceContainerHighest,
                        border: Border.all(color: kBrand, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: FaceCircle(
                        imageUrl: person(id)?['cover_url'] == null
                            ? null
                            : absoluteMedia('${person(id)!['cover_url']}', base),
                        box: person(id)?['box'] is Map
                            ? (person(id)!['box'] as Map)
                                .cast<String, dynamic>()
                            : null,
                      ),
                    ),
                    // ONE TAP TO TAKE A FACE BACK OFF. Without it the only way
                    // to undo a combination is to leave and start again, which
                    // is what makes a filter feel like a trap.
                    if (onDrop != null)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: GestureDetector(
                          onTap: () => onDrop!(id),
                          behavior: HitTestBehavior.opaque,
                          child: Semantics(
                            button: true,
                            label: 'Remove ${nameOf(id)}',
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 3),
                                ],
                              ),
                              child: const Icon(Icons.close, size: 14),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 5),
                  Text(nameOf(id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          if (onAdd != null)
            // THE LABEL IS PART OF THE BUTTON. Wrapping only the circle left
            // "Add someone" looking like a control and doing nothing when
            // tapped — which is worse than not having a label at all, because
            // the person concludes the feature is broken rather than that they
            // missed the target. Caught by a test tapping the words.
            SizedBox(
              width: 68,
              child: InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(14),
                child: Column(children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surfaceContainerHighest,
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant, width: 2),
                    ),
                    child: const Icon(Icons.add, size: 24),
                  ),
                  const SizedBox(height: 5),
                  Text('Add someone',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Everyone else, to add one.
class _PickFace extends StatelessWidget {
  const _PickFace({required this.people, required this.with_});
  final List<Map<String, dynamic>> people;
  final String with_;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = context.read<Session>().baseUrl ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Who else is in it?',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Only photos with $with_ and the person you pick',
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: people.length,
              itemBuilder: (_, i) {
                final p = people[i];
                final id = (p['id'] as num?)?.toInt() ?? 0;
                final name = '${p['name'] ?? ''}'.trim();
                return InkWell(
                  onTap: () => Navigator.pop(context, id),
                  borderRadius: BorderRadius.circular(12),
                  child: Column(children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: FaceCircle(
                        imageUrl: p['cover_url'] == null
                            ? null
                            : absoluteMedia('${p['cover_url']}', base),
                        box: p['box'] is Map
                            ? (p['box'] as Map).cast<String, dynamic>()
                            : null,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(name.isEmpty ? 'Person $id' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5)),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Nobody has been photographed with everybody.
class _NoneTogether extends StatelessWidget {
  const _NoneTogether({required this.names, required this.onDrop});
  final List<String> names;
  final VoidCallback? onDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = names.length == 2
        ? '${names.first} and ${names.last}'
        : 'all of them';
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 0, 34, 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.group_off_outlined,
              size: 34, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 14),
          // SAYING WHY, not showing an empty grid. "0 photos" on a screen you
          // reached by tapping two faces is indistinguishable from a search
          // that broke.
          Text('No photo has $who in it',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text('This shows only the photos everybody chosen appears in.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: theme.colorScheme.onSurfaceVariant)),
          if (onDrop != null) ...[
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: onDrop,
              child: const Text('Take the last face off'),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      );
}
