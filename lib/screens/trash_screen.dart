/// Recently deleted — where a deleted photo actually goes.
///
/// WHY THIS HAD TO EXIST BEFORE MULTI-SELECT DELETE DID
/// `DELETE /api/gallery/{id}` is a SOFT delete: it sets is_trashed and the photo
/// stays. The endpoints to see, restore and permanently remove those have been
/// there since the beginning and the phone reached none of them — so a photo
/// deleted from the phone went somewhere the phone could not look, and the
/// confirmation's promise that you can put it back was true of the product and
/// false of the app you were holding.
///
/// Selecting a whole day of holiday photos and deleting them by accident is
/// exactly the mistake a grid with multi-select invites. This is the undo.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/photo_tile.dart';
import 'gallery_screen.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, this.initialPhotos});

  /// For tests — lay the screen out without a server.
  final List<Photo>? initialPhotos;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Photo> _photos = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final Set<int> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/gallery/trash');
      final raw = d is Map ? (d['items'] as List? ?? const []) : const [];
      if (!mounted) return;
      setState(() {
        _photos = [
          for (final e in raw) Photo.fromJson(Map<String, dynamic>.from(e as Map))
        ];
        _loading = false;
        _error = null;
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

  Future<void> _run(String verb, String path) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<Session>().api;
    setState(() => _busy = true);
    try {
      for (var i = 0; i < ids.length; i += 4) {
        await Future.wait(ids.skip(i).take(4).map((id) => path == 'restore'
            ? api.post('/api/gallery/$id/restore')
            : api.delete('/api/gallery/$id/permanent')));
      }
      _selected.clear();
      await _load();
      messenger.showSnackBar(SnackBar(
          content: Text('$verb ${ids.length} '
              '${ids.length == 1 ? "photo" : "photos"}')));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Empty the whole bin in one call — /api/gallery/trash/empty exists for it,
  /// and doing it photo by photo over a few thousand would be both slow and a
  /// worse thing to interrupt halfway.
  Future<void> _emptyAll() async {
    final n = _photos.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Empty recently deleted?'),
        content: Text(
            'All $n ${n == 1 ? "photo" : "photos"} are removed from your '
            'computer for good. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Empty it',
                  style: TextStyle(color: kDanger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await context.read<Session>().api.post('/api/gallery/trash/empty');
      _selected.clear();
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('Emptied')));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteForever() async {
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Permanently delete $n ${n == 1 ? "photo" : "photos"}?'),
        // The one place in this app where a warning is the honest word. There
        // is no further undo, and the copy on the phone may be long gone.
        content: const Text(
            'This cannot be undone. They are removed from your computer for '
            'good — if this phone no longer has them, they are gone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete for ever',
                  style: TextStyle(color: kDanger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run('Permanently deleted', 'permanent');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recently deleted'),
        actions: [
          if (_photos.isNotEmpty && !_selecting)
            TextButton(
              onPressed: _busy ? null : _emptyAll,
              child: const Text('Empty', style: TextStyle(color: kDanger)),
            ),
          if (_photos.isNotEmpty && !_selecting)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(
                      () => _selected.addAll(_photos.map((p) => p.id))),
              child: const Text('Select all'),
            ),
        ],
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                      top: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    IconButton(
                      tooltip: 'Cancel',
                      onPressed: _busy ? null : () => setState(_selected.clear),
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text('${_selected.length} selected',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: BrandButton(
                        label: 'Put back',
                        icon: Icons.restore,
                        block: true,
                        onPressed:
                            _busy ? null : () => _run('Restored', 'restore'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _deleteForever,
                        icon: const Icon(Icons.delete_forever_outlined,
                            size: 18, color: kDanger),
                        label: const Text('Delete',
                            style: TextStyle(color: kDanger)),
                      ),
                    ),
                  ]),
                ]),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Problem(message: _error!, onRetry: _load)
              : _photos.isEmpty
                  ? const _Empty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                            child: Text(
                                '${_photos.length} '
                                '${_photos.length == 1 ? "photo" : "photos"}. '
                                'Put them back, or remove them for good.',
                                style: theme.textTheme.bodySmall),
                          ),
                        ),
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
                              (ctx, i) {
                                final p = _photos[i];
                                return PhotoTile(
                                  photo: p,
                                  // Everything here is selectable from the
                                  // first tap: there is nothing else to do
                                  // with a deleted photo, so making somebody
                                  // long-press first would be ceremony.
                                  selecting: true,
                                  selected: _selected.contains(p.id),
                                  onOpen: () => setState(() {
                                    if (!_selected.remove(p.id)) {
                                      _selected.add(p.id);
                                    }
                                  }),
                                );
                              },
                              childCount: _photos.length,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ]),
                    ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 44, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: kModuleColours['gallery'],
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: kModuleColours['gallery']!.withValues(alpha: 0.38),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.delete_outline,
                  size: 30, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('Nothing deleted',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                  'Photos you delete come here first, so a mistake is only a '
                  'mistake until you empty this.',
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
