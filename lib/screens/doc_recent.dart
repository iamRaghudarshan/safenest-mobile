/// Recently added, recently changed, and starred.
///
/// THREE LISTS, NOT ONE FEED. They answer different questions — "what did I
/// just put in here", "what did I just work on", "what do I keep coming back
/// to" — and a single list sorted by whichever timestamp happens to be larger
/// answers none of them reliably: a document replaced this morning would
/// outrank one added an hour ago, and a starred document might not appear at
/// all. The server returns them as three lists for exactly this reason and
/// this screen keeps them apart.
///
/// WHY IT MATTERS ON A PHONE more than on a computer. A folder tree is how you
/// find a document you filed deliberately. Recent is how you find the one you
/// scanned two minutes ago and have not filed at all — which on a phone is
/// nearly every document, because the phone is where the camera is.
library;

import 'package:flutter/material.dart';

import '../api.dart';

class DocRecentScreen extends StatefulWidget {
  const DocRecentScreen({super.key, required this.api, required this.onOpen});
  final Api api;

  /// Opening is the documents screen's job — it owns downloading, previewing
  /// and the temp file. Duplicating it here would be a second code path for
  /// the same act, and the one that drifts is the one nobody opens.
  final void Function(Map<String, dynamic> doc) onOpen;

  @override
  State<DocRecentScreen> createState() => _DocRecentScreenState();
}

class _DocRecentScreenState extends State<DocRecentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  Map<String, List<Map<String, dynamic>>> _lists = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.get('/api/documents/recent');
      if (!mounted) return;
      final m = r as Map;
      List<Map<String, dynamic>> pick(String k) => [
            for (final e in ((m[k] as List?) ?? const []))
              Map<String, dynamic>.from(e as Map)
          ];
      setState(() {
        _lists = {
          'added': pick('added'),
          'changed': pick('changed'),
          'starred': pick('starred'),
        };
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent'),
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Added'),
          Tab(text: 'Changed'),
          Tab(text: 'Starred'),
        ]),
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
              : TabBarView(controller: _tabs, children: [
                  _list('added', 'Nothing has been added yet.'),
                  _list('changed',
                      'Nothing has been replaced or edited yet.'),
                  _list('starred',
                      'Star a document and it will be waiting here.'),
                ]),
    );
  }

  Widget _list(String key, String empty) {
    final items = _lists[key] ?? const [];
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(empty, textAlign: TextAlign.center),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final d = items[i];
          final bits = <String>[
            if ('${d['ext'] ?? ''}'.isNotEmpty) '${d['ext']}'.toUpperCase(),
            if ('${d['kind'] ?? ''}'.isNotEmpty)
              '${d['kind']}'.replaceAll('_', ' '),
          ];
          return ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text('${d['title'] ?? 'Document'}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: bits.isEmpty ? null : Text(bits.join(' · ')),
            trailing: (d['is_favourite'] ?? 0) == 1
                ? const Icon(Icons.star, size: 18)
                : null,
            onTap: () => widget.onOpen(d),
          );
        },
      ),
    );
  }
}
