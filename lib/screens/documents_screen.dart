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
import '../masters.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/pill.dart';
import '../widgets/skeleton.dart';

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

  /// Fallback only. The real list comes from /api/masters — see _catLabel.
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

  /// The user's own document categories, with their emoji.
  List<MasterItem> _masters = const [];

  Future<void> _loadCategories() async {
    try {
      final list = await context
          .read<Session>()
          .masters
          .load('document_category');
      if (mounted) setState(() => _masters = list);
    } catch (_) {
      // The fallback above covers it — a lookup failing must not cost somebody
      // the ability to see their documents.
    }
  }

  /// One filter chip, in the app's own pill shape rather than Material's.
  Widget _catChip(String key, String label, String? emoji) {
    final on = _category == key;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? kModuleColours['documents'] : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            setState(() => _category = key);
            _load();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: on
                      ? kModuleColours['documents']!
                      : theme.colorScheme.outlineVariant,
                  width: 1.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (emoji != null) ...[
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : theme.colorScheme.onSurfaceVariant,
                  )),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadCategories();
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
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              children: [
                // "All" is not a category the server knows — it is the absence
                // of a filter, so it is not in the master list and is added here.
                _catChip('all', 'All', null),
                for (final m in _masters) _catChip(m.key, m.label, m.emoji),
                // Only while the list is still loading, so the row is never
                // empty and never jumps in width once it arrives.
                if (_masters.isEmpty)
                  for (final e in _categories.entries)
                    if (e.key != 'all') _catChip(e.key, e.value, null),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const SkeletonList()
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

  Widget _listView() => ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
        itemCount: _docs.length,
        itemBuilder: (ctx, i) {
          final d = _docs[i];
          final tint = _tint(d);
          final cat = '${d['category'] ?? ''}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: BrandCard(
              onTap: () => _open(d),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(children: [
                // A PDF and a photo are different things to open, so they are
                // different colours. A column of identical grey file glyphs
                // makes you read every filename to find anything.
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: tint.withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(_icon(d), size: 21, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${d['title'] ?? 'Document'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(_meta(d),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx).textTheme.bodySmall),
                        if (cat.isNotEmpty && cat != 'other') ...[
                          const SizedBox(height: 7),
                          Pill(_catLabel(cat), colour: tint),
                        ],
                      ]),
                ),
                if ((d['is_favourite'] ?? 0) == 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.star, size: 18, color: kWarn),
                  ),
              ]),
            ),
          );
        },
      );

  IconData _icon(Map<String, dynamic> d) {
    if (d['is_pdf'] == true) return Icons.picture_as_pdf_outlined;
    if (d['is_image'] == true) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  /// Colour by what the file IS, not by its category — that is what decides how
  /// it opens, and it is the thing being scanned for.
  Color _tint(Map<String, dynamic> d) {
    if (d['is_pdf'] == true) return kDanger;
    if (d['is_image'] == true) return kModuleColours['gallery']!;
    return kModuleColours['documents']!;
  }

  /// The category's own label, from the user's list — with its emoji.
  ///
  /// `_categories` below is a hardcoded eight and stays only as the fallback
  /// for a category not in the list. The web app's Documents screen reads
  /// /api/masters?type=document_category, so a renamed or added category
  /// appeared there and never here.
  String _catLabel(String key) {
    for (final m in _masters) {
      if (m.key == key) {
        return m.emoji == null ? m.label : '${m.emoji} ${m.label}';
      }
    }
    return _categories[key] ?? key;
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
