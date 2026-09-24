/// Things the library implies, offered rather than done.
///
/// The computer can see that twelve photos were taken on one afternoon. Making
/// a collage out of them without asking produces a gallery somebody has to
/// undo, and the person who minds most is the one whose library is already
/// large — so every card carries BOTH answers, the same size, side by side.
///
/// NO MEANS NEVER AGAIN, and that is the property the whole strip lives on. A
/// suggestion that returns tomorrow is how people learn to scroll past the
/// panel, and then the good ones go unread with the rest. The server stores
/// only the NOs, against a key derived from the thing itself.
///
/// It draws nothing at all when there is nothing to offer. An empty panel with
/// a heading is a permanent reminder that the feature exists and has no
/// opinion, which is worse than silence.
library;

import 'package:flutter/material.dart';

import '../api.dart';

class SuggestionsStrip extends StatefulWidget {
  const SuggestionsStrip({super.key, required this.api, this.onMade});

  final Api api;

  /// Called after something is created, so the grid behind can reload — the
  /// creation is an ordinary photo and belongs in the timeline immediately.
  final VoidCallback? onMade;

  @override
  State<SuggestionsStrip> createState() => _SuggestionsStripState();
}

class _SuggestionsStripState extends State<SuggestionsStrip> {
  List<Map<String, dynamic>> _items = const [];
  String _busy = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('/api/gallery/suggestions');
      if (!mounted) return;
      setState(() {
        _items = ((r as Map)['items'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
        _loaded = true;
      });
    } catch (_) {
      // Nothing is waiting on this. A strip that cannot load is a strip that
      // is not drawn, which is the right failure for an optional panel.
      if (mounted) setState(() => _loaded = true);
    }
  }

  /// Removed here rather than by reloading: the answer is already known, and a
  /// panel that blinks through a spinner to show one fewer card draws the eye
  /// to exactly the thing that just went away.
  void _drop(String key) =>
      setState(() => _items = _items.where((s) => s['key'] != key).toList());

  Future<void> _no(Map<String, dynamic> s) async {
    final key = '${s['key']}';
    _drop(key);
    try {
      await widget.api.post('/api/gallery/suggestions/dismiss', {'key': key});
    } catch (_) {
      // It is already off the screen. Putting it back to report a failure
      // would be a worse outcome than the failure.
    }
  }

  Future<void> _make(Map<String, dynamic> s) async {
    final key = '${s['key']}';
    setState(() => _busy = key);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.post('/api/gallery/creations', {
        'kind': s['kind'],
        'photo_ids': s['photo_ids'],
        'title': s['title'],
        'key': key,
      });
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(s['kind'] == 'reel'
            ? 'Highlight saved to your gallery'
            : 'Collage saved to your gallery'),
      ));
      _drop(key);
      widget.onMade?.call();
    } on ApiError catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text('SUGGESTIONS',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
        ),
        for (final s in _items) _card(s),
      ],
    );
  }

  Widget _card(Map<String, dynamic> s) {
    final kind = '${s['kind']}';
    final key = '${s['key']}';
    final canMake = kind == 'collage' || kind == 'reel';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              kind == 'reel'
                  ? Icons.movie_filter_outlined
                  : kind == 'collage'
                      ? Icons.auto_awesome_mosaic_outlined
                      : Icons.folder_open,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s['title'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text('${s['detail'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy.isEmpty ? () => _no(s) : null,
            child: const Text('No thanks'),
          ),
          if (canMake)
            FilledButton(
              onPressed: _busy.isEmpty ? () => _make(s) : null,
              child: Text(_busy == key ? 'Making…' : 'Make it'),
            ),
        ],
      ),
    );
  }
}
