/// Browsing by what is IN the photo — beach, chart, dog, receipt.
///
/// WHY THIS IS NOT A SEARCH BOX. Searching needs the word first, and the word
/// is the thing people do not have: nobody types "whiteboard" on the chance
/// that the computer used the same word. A list of what the library actually
/// contains turns a guess into a choice.
///
/// ONLY LABELS THAT WERE FOUND IN REAL PHOTOS. The vocabulary has dozens of
/// entries and a given household will have none of most of them; offering
/// "desert" to somebody with no desert photographs is how a category browser
/// becomes a list of dead ends. The server already filters by count — this
/// screen just shows what comes back.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import 'library_tabs.dart' show CollectionScreen;

class LabelsScreen extends StatefulWidget {
  const LabelsScreen({super.key});

  @override
  State<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends State<LabelsScreen> {
  List<Map<String, dynamic>> _items = const [];
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
      final r = await context.read<Session>().api.get('/api/gallery/labels');
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
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What is in them')),
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
                        padding: EdgeInsets.all(34),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.label_outline, size: 44),
                          SizedBox(height: 14),
                          Text('Nothing recognised yet'),
                          SizedBox(height: 8),
                          // The honest reason, rather than an empty screen:
                          // labels come from the indexer, and it may simply
                          // not have run over this library yet.
                          Text(
                            'Your computer works these out while it indexes '
                            'the gallery. Back some photos up, give it a '
                            'little time, and they will appear.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12),
                          ),
                        ]),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final l in _items)
                                ActionChip(
                                  avatar: const Icon(Icons.label_outline,
                                      size: 16),
                                  label: Text('${l['label']}  ${l['count']}'),
                                  onPressed: () =>
                                      Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => CollectionScreen(
                                        title: '${l['label']}',
                                        // The same index everything else
                                        // reads, with one more filter — not a
                                        // second listing endpoint that would
                                        // drift from it.
                                        path:
                                            '/api/gallery?label=${Uri.encodeQueryComponent('${l['label']}')}',
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
    );
  }
}
