/// Earlier copies of one document.
///
/// THE RULE THIS SCREEN EXISTS TO MAKE VISIBLE: replacing a file never
/// destroys the old one. Uploading the wrong scan over the right one used to
/// take the right one with it, and what a document store holds is usually
/// irreplaceable — a policy, a deed, a letter from a hospital.
///
/// DOWNLOAD SITS BESIDE RESTORE for a reason. The usual reason to open this
/// list is working out WHICH copy you want, and a Restore you have to perform
/// first, in order to find out, is a Restore somebody then has to undo.
///
/// The last ten are kept. That is said on the screen rather than left to be
/// discovered, because somebody who replaces a file eleven times and counts
/// will otherwise report the missing one as a bug.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';
import '../dates.dart';

class DocVersionsScreen extends StatefulWidget {
  const DocVersionsScreen({
    super.key,
    required this.api,
    required this.id,
    required this.title,
  });

  final Api api;
  final int id;
  final String title;

  @override
  State<DocVersionsScreen> createState() => _DocVersionsScreenState();
}

class _DocVersionsScreenState extends State<DocVersionsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// True when anything was restored, so the screen behind reloads. Returned
  /// on pop rather than by callback: the caller may have been rebuilt while
  /// this was open.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.get('/api/documents/${widget.id}/versions');
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

  Future<void> _download(Map<String, dynamic> v) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await widget.api.download(
          '/api/documents/${widget.id}/versions/${v['version']}/file');
      final dir = await getTemporaryDirectory();
      final name = ('${v['orig_name'] ?? '${widget.title} (v${v['version']})'
          '.${v['ext'] ?? 'bin'}'}')
          .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_');
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes);
      await OpenFilex.open(f.path);
    } on ApiError catch (e) {
      // 410 is its own answer: the row is there and the file is not, which is
      // what retention looks like from the outside.
      messenger.showSnackBar(SnackBar(
        content: Text(e.status == 410
            ? 'That version is no longer on the disk.'
            : e.message),
      ));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('That version could not be opened.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restore version ${v['version']}?'),
        // Said plainly, because it is the thing that makes this safe to press:
        // restoring is itself undoable, since the copy being replaced is kept
        // as a new version rather than thrown away.
        content: const Text(
            'It becomes the current file. The one it replaces is kept as a '
            'new version, so this can be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.post(
          '/api/documents/${widget.id}/versions/${v['version']}/restore',
          const {});
      _changed = true;
      messenger.showSnackBar(
          SnackBar(content: Text('Version ${v['version']} is now current')));
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, _) {},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Versions'),
          leading: BackButton(
              onPressed: () => Navigator.pop(context, _changed)),
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
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Replacing a file keeps the old one, so nothing is '
                          'lost by uploading the wrong scan. The last ten are '
                          'kept.',
                          style: TextStyle(fontSize: 12.5, height: 1.45),
                        ),
                      ),
                      Expanded(
                        child: _items.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(30),
                                  child: Text('No earlier versions yet.'),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _items.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (ctx, i) {
                                  final v = _items[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      child: Text('${v['version']}'),
                                    ),
                                    title: Text(
                                      '${v['note'] ?? v['orig_name'] ?? 'Version ${v['version']}'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(_meta(v)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                              Icons.download_outlined),
                                          tooltip: 'Open this version',
                                          onPressed: _busy
                                              ? null
                                              : () => _download(v),
                                        ),
                                        TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => _restore(v),
                                          child: const Text('Restore'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  static String _meta(Map<String, dynamic> v) {
    final bits = <String>[];
    final size = (v['size_bytes'] as num?)?.toInt() ?? 0;
    if (size > 0) {
      bits.add(size >= 1048576
          ? '${(size / 1048576).toStringAsFixed(1)} MB'
          : '${(size / 1024).round()} KB');
    }
    final when = '${v['created_at'] ?? ''}';
    if (when.isNotEmpty) {
      final d = DateTime.tryParse(when);
      if (d != null) bits.add(fmtDate(d));
    }
    return bits.join(' · ');
  }
}
