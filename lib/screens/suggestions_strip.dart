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
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../widgets/photo_tile.dart';

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

  /// How many are shown before "Show more".
  ///
  /// The server offers one per busy day, which on a real library is eight or
  /// more — and eight full-width cards stacked above the albums is not a
  /// suggestion panel, it is the screen. Two is an offer; the rest are there
  /// for anybody who wants them.
  static const _visible = 2;
  bool _all = false;

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
        for (final s in (_all ? _items : _items.take(_visible))) _card(s),
        if (_items.length > _visible)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all
                    ? 'Show fewer'
                    : 'Show ${_items.length - _visible} more'),
              ),
            ),
          ),
      ],
    );
  }

  /// The photographs the suggestion is ABOUT, as a small overlapping stack.
  ///
  /// It drew a generic icon in a tinted square — for a suggestion about
  /// somebody's own pictures, which is the one thing worth showing. "A moving
  /// highlight from 25 September" means nothing on its own; three faces from
  /// that afternoon mean everything.
  ///
  /// Overlapped rather than in a row: it says "several of these" in the width
  /// of one and a half, and a card in a list has no room for three squares
  /// side by side.
  Widget _covers(Map<String, dynamic> s, IconData fallbackIcon) {
    final base = context.read<Session>().baseUrl ?? '';
    final urls = [
      for (final u in ((s['covers'] as List?) ?? const []))
        absoluteMedia('$u', base)
    ];
    if (urls.isEmpty) {
      return Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(fallbackIcon, size: 20),
      );
    }
    return SizedBox(
      width: 46.0 + (urls.length - 1) * 13,
      height: 46,
      child: Stack(
        children: [
          // Reversed so the FIRST photo ends up on top: it is the one the
          // suggestion leads with, and the others are depth behind it.
          for (var i = urls.length - 1; i >= 0; i--)
            Positioned(
              left: i * 13.0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.surface, width: 1.6),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x22000000), blurRadius: 3, offset:
                            Offset(0, 1))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    urls[i],
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Container(
                      width: 44,
                      height: 44,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: Icon(fallbackIcon, size: 18),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
          _covers(
              s,
              kind == 'reel'
                  ? Icons.movie_filter_outlined
                  : kind == 'collage'
                      ? Icons.auto_awesome_mosaic_outlined
                      : Icons.folder_open),
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
