/// The recycle bin, and the two ways out of it.
///
/// WHY THE PHONE NEEDED THIS AND NOT JUST THE COMPUTER. Deleting a document
/// on the phone already put it here — the bin simply could not be reached from
/// the phone, so a mis-tap on a scan of somebody's passport looked permanent
/// to the person who made it. They would then re-scan the original rather than
/// walk to a computer, and the bin quietly filled with files nobody could see.
/// A bin that only one device can open is worse than no bin: it takes the
/// space and gives back none of the reassurance.
///
/// RESTORE AND DELETE ARE NOT SYMMETRICAL and the screen must not pretend they
/// are. Restore is free — it puts the row back and nothing was ever lost.
/// Permanent delete removes the row AND both stored files, and a household
/// document store is usually holding the only copy that exists. So restoring
/// is one tap and deleting asks, by name, every time.
///
/// Emptying asks harder still, because it is the one action here whose size is
/// invisible: "Empty" beside a list scrolled to the top does not look like
/// forty documents.
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class DocTrashScreen extends StatefulWidget {
  const DocTrashScreen({super.key, required this.api});
  final Api api;

  @override
  State<DocTrashScreen> createState() => _DocTrashScreenState();
}

class _DocTrashScreenState extends State<DocTrashScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// Whether anything at all changed, so the list behind knows to reload.
  /// A restored document has to reappear there without the person going
  /// looking for a refresh.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.get('/api/documents/trash');
      if (!mounted) return;
      setState(() {
        _items = [
          for (final e in ((r as Map)['items'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map)
        ];
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

  Future<void> _restore(Map<String, dynamic> d) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.api.post('/api/documents/${d['id']}/restore', const {});
      _changed = true;
      messenger.showSnackBar(
          SnackBar(content: Text('“${d['title']}” put back')));
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _destroy(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete for good?'),
        // Named, not "this document". The bin is a list of similar-looking
        // rows and the confirmation is the last chance to notice the wrong
        // one is selected.
        content: Text('“${d['title']}” and its file are removed from your '
            'computer. This cannot be undone, and for most papers here this '
            'is the only copy.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kDanger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.api.delete('/api/documents/${d['id']}/permanent');
      _changed = true;
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _empty() async {
    final n = _items.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Empty the bin — $n '
            '${n == 1 ? 'document' : 'documents'}?'),
        // The COUNT is the whole point of this sentence. "Empty" over a list
        // scrolled to the top does not look like forty documents.
        content: const Text(
            'Every document here, and its file, is removed from your '
            'computer. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty', style: TextStyle(color: kDanger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final r = await widget.api.post('/api/documents/trash/empty', const {});
      _changed = true;
      final n = (r is Map ? (r['deleted'] as num?)?.toInt() : null) ?? 0;
      messenger.showSnackBar(SnackBar(
          content: Text('$n ${n == 1 ? 'document' : 'documents'} deleted')));
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
        title: const Text('Recycle bin'),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : _empty,
              child: const Text('Empty', style: TextStyle(color: kDanger)),
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
              : _items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.delete_outline, size: 44),
                          SizedBox(height: 12),
                          Text('The bin is empty',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          SizedBox(height: 6),
                          Text(
                            'Deleted documents wait here until you empty it, '
                            'so a mis-tap is never the end of anything.',
                            textAlign: TextAlign.center,
                          ),
                        ]),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final d = _items[i];
                          final when = '${d['trashed_fmt'] ?? ''}'.trim();
                          return ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text('${d['title'] ?? 'Document'}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(when.isEmpty
                                ? '${d['ext'] ?? ''}'.toUpperCase()
                                : 'Deleted $when'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Restore first and unadorned, because it is
                                // the safe one and the one people came for.
                                TextButton(
                                  onPressed: _busy ? null : () => _restore(d),
                                  child: const Text('Put back'),
                                ),
                                IconButton(
                                  tooltip: 'Delete for good',
                                  icon: const Icon(Icons.delete_forever,
                                      color: kDanger),
                                  onPressed: _busy ? null : () => _destroy(d),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
