/// Documents, shaped like Google Drive.
///
/// WHAT A PHONE IS ACTUALLY BETTER AT
/// Photographing a bill and having it filed. The computer is better for reading
/// and organising; the phone is where the piece of paper is. The server reads
/// the text off whatever arrives (OCR) without being asked, which is what makes
/// a photographed receipt findable later rather than merely stored.
///
/// Adding goes through the system file picker, which offers the camera among its
/// choices. A dedicated "photograph a document" button — straight to the camera,
/// no menu — is not built yet and would be the obvious next thing here.
///
/// GRID OR LIST, like Drive, because the two answer different questions: a grid
/// to recognise a document by its shape, a list to compare dates and sizes.
/// The choice is remembered.
///
/// Categories stand in for Drive's folders. The server already files documents
/// by category — id, bill, medical and so on — and inventing a second folder
/// tree on the phone would mean two organisations of the same drawer.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  bool _grid = true;
  String _category = 'all';
  String _query = '';
  String? _error;
  final _search = TextEditingController();

  static const _categories = <String, String>{
    'all': 'All',
    'id': 'ID',
    'bill': 'Bills',
    'medical': 'Medical',
    'property': 'Property',
    'vehicle': 'Vehicle',
    'education': 'Education',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/documents', {
        if (_category != 'all') 'category': _category,
        if (_query.isNotEmpty) 'q': _query,
      });
      setState(() {
        _docs = [
          for (final e in ((d as Map)['items'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map)
        ];
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  String _abs(String u) =>
      u.startsWith('http') ? u : '${context.read<Session>().baseUrl ?? ''}$u';

  /// Opened by downloading first, then handing the file to whatever the phone
  /// uses for PDFs. The media URL is signed and expiring, so a viewer that
  /// fetched it later — or a second time — would get nothing.
  Future<void> _open(Map<String, dynamic> doc) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Opening…')));
    try {
      final session = context.read<Session>();
      final res = await session.api.download('${doc['file_url']}');
      final dir = await getTemporaryDirectory();
      final name = '${doc['title'] ?? 'document'}.${doc['ext'] ?? 'bin'}'
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(res);
      await OpenFilex.open(f.path);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open it: $e')));
    }
  }

  Future<void> _upload() async {
    // Static in file_picker 11 — `FilePicker.platform` was the 8.x spelling.
    // Upgraded because 8.x compiles against android-34 and the build now
    // requires 36; the API change came with it.
    //
    // withData false on purpose: reading every chosen file into memory to hand
    // it to the picker is how a phone dies on a large selection. The path is
    // enough — the bytes are read one file at a time below.
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final session = context.read<Session>();
    var done = 0, failed = 0;
    for (final f in picked.files) {
      final path = f.path;
      if (path == null) continue;
      try {
        final bytes = await File(path).readAsBytes();
        final ok = await session.api.postMultipart(
          '/api/documents',
          fileField: 'file',
          filename: f.name,
          bytes: bytes,
          fields: {'title': f.name.split('.').first, 'category': _category == 'all' ? 'other' : _category},
        );
        ok ? done++ : failed++;
      } catch (_) {
        failed++;
      }
    }
    messenger.showSnackBar(SnackBar(
        content: Text(failed == 0
            ? 'Added $done document${done == 1 ? '' : 's'}'
            : 'Added $done, $failed could not be sent')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            tooltip: _grid ? 'Show as a list' : 'Show as a grid',
            icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _upload,
        icon: const Icon(Icons.upload_file),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                setState(() => _query = v.trim());
                _load();
              },
              decoration: InputDecoration(
                hintText: 'Search — including words inside your documents',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                          _load();
                        }),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final e in _categories.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _category == e.key,
                      onSelected: (_) {
                        setState(() => _category = e.key);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                                onPressed: _load, child: const Text('Try again')),
                          ]),
                        ),
                      )
                    : _docs.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(36),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.folder_open_outlined, size: 44),
                                SizedBox(height: 14),
                                Text('Nothing filed here yet'),
                                SizedBox(height: 8),
                                Text(
                                  'Add a photo of a bill or a PDF. Your computer '
                                  'reads the text off it, so you can find it later '
                                  'by what it says.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ]),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: _grid ? _gridView() : _listView(),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _gridView() => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: _docs.length,
        itemBuilder: (ctx, i) {
          final d = _docs[i];
          return InkWell(
            onTap: () => _open(d),
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      child: Image.network(
                        _abs('${d['thumb_url']}'),
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                        errorBuilder: (a, b, c) =>
                            Center(child: Icon(_icon(d), size: 40)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('${d['title'] ?? 'Document'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(_meta(d), style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
          );
        },
      );

  Widget _listView() => ListView.separated(
        itemCount: _docs.length,
        separatorBuilder: (_, i) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final d = _docs[i];
          return ListTile(
            leading: Icon(_icon(d), size: 30),
            title: Text('${d['title'] ?? 'Document'}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_meta(d)),
            trailing: (d['is_favourite'] ?? 0) == 1
                ? const Icon(Icons.star, size: 18, color: Colors.amber)
                : null,
            onTap: () => _open(d),
          );
        },
      );

  IconData _icon(Map<String, dynamic> d) {
    if (d['is_pdf'] == true) return Icons.picture_as_pdf_outlined;
    if (d['is_image'] == true) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _meta(Map<String, dynamic> d) {
    final bits = <String>[];
    final size = (d['size_bytes'] ?? 0) as int;
    if (size > 0) {
      bits.add(size < 1048576
          ? '${(size / 1024).round()} KB'
          : '${(size / 1048576).toStringAsFixed(1)} MB');
    }
    final made = DateTime.tryParse('${d['created_at'] ?? ''}');
    if (made != null) bits.add(DateFormat('d MMM y').format(made));
    // An expiry that has passed, or is close, is the single most useful thing
    // to know about a document — so it wins the line if it is there.
    final status = d['expiry_status'];
    if (status == 'expired') return 'Expired · ${bits.join(' · ')}';
    if (d['days_until_expiry'] != null && (d['days_until_expiry'] as int) <= 60) {
      return 'Expires in ${d['days_until_expiry']} days · ${bits.join(' · ')}';
    }
    return bits.join(' · ');
  }
}
