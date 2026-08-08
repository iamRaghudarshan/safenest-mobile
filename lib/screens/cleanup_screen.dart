/// Free up space — exact duplicates and near-duplicates, grouped.
///
/// Two different questions, and the server answers them differently:
///
///   /duplicates  photos with the SAME content hash. Byte-identical copies —
///                the same picture sent to you twice, or a folder imported
///                twice. Deleting all but one loses nothing at all.
///   /similar     photos with a close perceptual hash (dHash, distance 8 by
///                default). Resized, re-saved, filtered or burst-mode copies.
///                These are NOT identical, so which one to keep is a judgement
///                and the app must not make it silently.
///
/// That difference drives the whole screen. For exact duplicates the choice is
/// free and one is pre-picked. For similar photos the person chooses, and the
/// wording says why: "these look alike" rather than "these are the same".
///
/// NOTHING IS DELETED OUTRIGHT. /duplicates/resolve soft-trashes, so everything
/// lands in Recently deleted and can be put back. On a screen whose whole job is
/// removing photos in bulk, that is the property that makes it safe to use.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/pill.dart';
import 'gallery_screen.dart';

class CleanupScreen extends StatefulWidget {
  const CleanupScreen({super.key, this.initialGroups, this.initialMode});

  /// For tests — lay the screen out without a server.
  final List<Map<String, dynamic>>? initialGroups;
  final int? initialMode;

  @override
  State<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends State<CleanupScreen> {
  /// 0 = exact duplicates, 1 = similar.
  ///
  /// Starts on SIMILAR, because exact duplicates essentially cannot happen:
  /// the upload endpoint dedupes on content_hash, so sending the same bytes
  /// three times returns the same photo three times and the library grows by
  /// one. Verified by doing exactly that. The exact tab is kept because a
  /// library that predates content_hash may still have some, but it is not
  /// where anybody's space has gone.
  int _mode = 1;
  List<_Group> _groups = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? 1;   // similar, per the comment above
    if (widget.initialGroups != null) {
      _groups = widget.initialGroups!.map(_Group.fromJson).toList();
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<Session>().api.get(
          _mode == 0 ? '/api/gallery/duplicates' : '/api/gallery/similar');
      final raw = d is Map ? (d['groups'] as List? ?? const []) : const [];
      if (!mounted) return;
      setState(() {
        _groups = [
          for (final g in raw) _Group.fromJson(Map<String, dynamic>.from(g as Map))
        ];
        _loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  /// Everything not chosen as the keeper, across every group.
  List<int> get _doomed => [
        for (final g in _groups)
          for (final p in g.photos)
            if (p.id != g.keepId) p.id
      ];

  Future<void> _clean() async {
    final ids = _doomed;
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${ids.length} '
            '${ids.length == 1 ? "photo" : "photos"}?'),
        content: Text(
            'One from each group is kept. The rest go to Recently deleted, '
            'where you can put them back.'
            '${_mode == 1 ? "\n\nThese only LOOK alike — check you have kept the "
                "one you want." : ""}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // One call for the lot — the endpoint takes a list, and doing it photo by
      // photo over a few hundred would be slower and worse to interrupt.
      await context
          .read<Session>()
          .api
          .post('/api/gallery/duplicates/resolve', {'delete_ids': ids});
      await _load();
      messenger.showSnackBar(SnackBar(
          content: Text('Removed ${ids.length} — they are in Recently deleted')));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doomed = _doomed.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Free up space')),
      bottomNavigationBar: doomed == 0
          ? null
          : SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                      top: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  if (_busy) const SizedBox(height: 6),
                  BrandButton(
                    label: 'Remove $doomed and keep ${_groups.length}',
                    icon: Icons.auto_delete_outlined,
                    block: true,
                    onPressed: _busy ? null : _clean,
                  ),
                ]),
              ),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Segmented(
            labels: const ['Exact copies', 'Look alike'],
            index: _mode,
            onChanged: _busy
                ? (_) {}
                : (i) {
                    setState(() => _mode = i);
                    _load();
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            _mode == 0
                ? 'Byte-for-byte identical copies. Your computer already '
                    'refuses these on upload, so there are rarely any.'
                : 'Resized, re-saved or edited copies. These are NOT identical '
                    '— choose which to keep.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _Problem(message: _error!, onRetry: _load)
                  : _groups.isEmpty
                      ? _Nothing(mode: _mode)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                          itemCount: _groups.length,
                          itemBuilder: (ctx, i) => _GroupCard(
                            group: _groups[i],
                            index: i + 1,
                            exact: _mode == 0,
                            onKeep: (id) =>
                                setState(() => _groups[i].keepId = id),
                          ),
                        ),
        ),
      ]),
    );
  }
}

class _Group {
  _Group(this.photos, this.keepId);
  final List<Photo> photos;

  /// Which one survives. The server suggests one (`keep_id`); tapping another
  /// changes it, which is the entire interaction on this screen.
  int keepId;

  static _Group fromJson(Map<String, dynamic> j) {
    final items = (j['items'] as List? ?? const [])
        .map((e) => Photo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final suggested = j['keep_id'] as int?;
    return _Group(
      items,
      suggested ?? (items.isEmpty ? -1 : items.first.id),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.index,
    required this.exact,
    required this.onKeep,
  });
  final _Group group;
  final int index;
  final bool exact;
  final ValueChanged<int> onKeep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = context.read<Session>().baseUrl ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BrandCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // No trailing "keeping 1": it overflowed a narrow phone by 23px and
          // it was already said, more usefully, on the button — "Remove 2 and
          // keep 1" covers every group at once.
          Row(children: [
            Flexible(
              child: Text('Group $index',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Pill('${group.photos.length} copies',
                tone: exact ? PillTone.warn : PillTone.muted),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final p = group.photos[i];
                final keep = p.id == group.keepId;
                final url = p.thumbUrl.startsWith('http')
                    ? p.thumbUrl
                    : '$base${p.thumbUrl}';
                return GestureDetector(
                  onTap: () => onKeep(p.id),
                  child: Stack(children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: keep ? kOk : kDanger.withValues(alpha: 0.5),
                            width: keep ? 2.5 : 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ColorFiltered(
                        // The ones going away are dimmed, not hidden: you are
                        // about to delete them and should be able to see what
                        // they are.
                        colorFilter: keep
                            ? const ColorFilter.mode(
                                Colors.transparent, BlendMode.multiply)
                            : ColorFilter.mode(
                                Colors.black.withValues(alpha: 0.45),
                                BlendMode.darken),
                        child: Image.network(url,
                            fit: BoxFit.cover,
                            width: 96,
                            height: 96,
                            cacheWidth: 240,
                            errorBuilder: (_, _, _) => ColoredBox(
                                color: theme
                                    .colorScheme.surfaceContainerHighest)),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: keep ? kOk : kDanger,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(keep ? 'Keep' : 'Remove',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text('Tap a photo to keep that one instead.',
              style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing({required this.mode});
  final int mode;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 44, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: kOk,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: kOk.withValues(alpha: 0.38),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.check, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
                mode == 0
                    ? 'No duplicate photos'
                    : 'Nothing looks duplicated',
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                  mode == 0
                      ? 'Your computer refuses a second copy of a photo it '
                          'already has, so exact duplicates cannot really '
                          'build up. Try "Look alike" instead — resized and '
                          're-saved copies are where the space goes.'
                      : 'Nothing was found that looks like a resized or '
                          're-saved copy of another photo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ]),
        )
      ]);
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 44, 22, 20),
          child: Column(children: [
            const Text('📡', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 190),
              child: BrandButton(label: 'Try again', onPressed: onRetry),
            ),
          ]),
        )
      ]);
}
