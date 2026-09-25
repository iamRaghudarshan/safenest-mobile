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
/// CATEGORIES AND FOLDERS ARE BOTH HERE NOW, and the earlier note in this file
/// said they should not be. That note was right when it was written: the server
/// had only categories, so a folder tree on the phone would have been a second
/// organisation of the same drawer, invented locally and true nowhere else.
///
/// The server has real folders now. So the phone shows the ONE tree the server
/// keeps, and categories go on being what they already were — a cross-cutting
/// label, like a colour, not a place. Browsing is by folder; the category chips
/// filter whatever is in view.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../dates.dart';
import '../session.dart';
import '../sharing.dart';
import 'doc_preview.dart';
import 'doc_versions.dart';
import 'scan_screen.dart';
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
  // A LIST by default — it is the view that answers "which of these is newest /
  // biggest / expiring", which is what a filing drawer is usually opened for; the
  // grid is for recognising a document by its shape. The choice is remembered
  // (it was documented as remembered long before it actually was).
  bool _grid = false;
  static const _viewKey = 'documents.view.grid';
  String _category = 'all';
  String _query = '';

  /// Which folder is open. 0 is the TOP LEVEL, which is a real place — not
  /// "no filter". Searching leaves the tree entirely, because a search limited
  /// to the folder somebody happens to be standing in is the complaint every
  /// file manager that did it has had.
  int _folder = 0;

  /// Narrowing by what a file IS and when it arrived, and the order.
  ///
  /// Kept out of the search box deliberately: these NARROW a listing and a
  /// search REPLACES it, and mixing them gives "search inside the filter" or
  /// "filter inside the search" depending on which ran last.
  String _ftype = '';
  String _since = '';
  String _until = '';
  String _sort = '';
  bool _filtersOpen = false;
  List<Map<String, dynamic>> _folders = const [];
  List<Map<String, dynamic>> _path = const [];

  /// Multi-select. A Set because every rebuild asks "is this one picked?" once
  /// per row, and a list would make that a scan.
  final Set<int> _picked = <int>{};
  bool get _selecting => _picked.isNotEmpty;
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
    // Restore the remembered grid/list choice, if there is one.
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(_viewKey);
      if (v != null && mounted) setState(() => _grid = v);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Searching or filtering by category looks through the WHOLE tree;
      // browsing shows one folder. They are different questions, and the
      // single endpoint answers whichever it is given.
      final searching = _query.isNotEmpty || _category != 'all';
      final d = await context.read<Session>().api.get('/api/documents', {
        if (_category != 'all') 'category': _category,
        if (_query.isNotEmpty) 'q': _query,
        if (!searching) 'folder': '$_folder',
        if (_ftype.isNotEmpty) 'ftype': _ftype,
        if (_since.isNotEmpty) 'since': _since,
        if (_until.isNotEmpty) 'until': _until,
        if (_sort.isNotEmpty) 'sort': _sort,
      });
      setState(() {
        final root = d as Map;
        _docs = [
          for (final e in (root['items'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map)
        ];
        _folders = [
          for (final e in (root['folders'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map)
        ];
        _path = [
          for (final e in (root['path'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map)
        ];
        // Anything selected that is no longer on screen would make a bulk
        // action fire on rows nobody can see — which is exactly the case
        // where nobody can check what they are about to do.
        _picked.removeWhere(
            (id) => !_docs.any((d) => (d['id'] as num).toInt() == id));
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

  // ------------------------------------------------------------ folders

  void _openFolder(int id) {
    setState(() {
      _folder = id;
      _picked.clear();
    });
    _load();
  }

  Future<void> _newFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 160,
          decoration: const InputDecoration(hintText: 'Bank statements'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api.post('/api/documents/folders', {
        'name': name,
        'parent_id': _folder == 0 ? null : _folder,
      });
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _renameFolder(Map<String, dynamic> f) async {
    // Opens with the CURRENT name. An empty box turns a rename into "type the
    // whole thing again", which is not what the word means.
    final controller = TextEditingController(text: '${f['name'] ?? ''}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(
            controller: controller, autofocus: true, maxLength: 160),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<Session>()
          .api
          .put('/api/documents/folders/${f['id']}', {'name': name});
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _trashFolder(Map<String, dynamic> f) async {
    final docs = (f['documents'] as num?)?.toInt() ?? 0;
    final subs = (f['folders'] as num?)?.toInt() ?? 0;
    // Says what it will take with it. A folder delete that quietly binned
    // forty documents would be a nasty surprise, and the count is the only
    // thing that makes the confirmation worth reading.
    final extra = (docs == 0 && subs == 0)
        ? ''
        : ' and ${[
            if (docs > 0) '$docs document${docs == 1 ? '' : 's'}',
            if (subs > 0) '$subs folder${subs == 1 ? '' : 's'}',
          ].join(' and ')} inside it';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to the recycle bin?'),
        content: Text('“${f['name']}”$extra will go to the recycle bin.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Move it')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<Session>()
          .api
          .delete('/api/documents/folders/${f['id']}');
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ------------------------------------------------------------ selection

  void _toggle(int id) => setState(() {
        if (!_picked.remove(id)) _picked.add(id);
      });

  Future<void> _bulk(String action, String said) async {
    if (_picked.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await context.read<Session>().api.post(
          '/api/documents/bulk', {'ids': _picked.toList(), 'action': action});
      // Reports what CHANGED, not what was asked for. The two differ when a
      // document was already starred, and "4 starred" over 2 real changes is
      // the kind of small lie that makes people stop believing the counts.
      final n = (r is Map ? (r['changed'] as num?)?.toInt() : null) ?? 0;
      messenger.showSnackBar(SnackBar(content: Text('$n $said')));
      setState(_picked.clear);
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _moveSelected() async {
    final target = await _pickFolder();
    if (target == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api.post('/api/documents/move', {
        'ids': _picked.toList(),
        'folder_id': target.$1,
      });
      messenger.showSnackBar(
          SnackBar(content: Text('${_picked.length} moved to ${target.$2}')));
      setState(_picked.clear);
      await _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// A flat list of every folder, indented by depth. Returns (id, name), with
  /// a null id meaning the top level.
  Future<(int?, String)?> _pickFolder() async {
    List<Map<String, dynamic>> all = const [];
    try {
      final r = await context.read<Session>().api.get('/api/documents/folders');
      all = [
        for (final e in ((r as Map)['items'] as List? ?? const []))
          Map<String, dynamic>.from(e as Map)
      ];
    } on ApiError catch (_) {
      // An empty list still lets somebody move things to the top level, which
      // is more useful than refusing to open the sheet.
    }
    if (!mounted) return null;

    int depthOf(Map<String, dynamic> f) {
      var n = 0;
      var cur = f['parent_id'];
      final seen = <int>{};
      // Bounded, and cycle-aware: a loop in the tree would otherwise hang the
      // sheet rather than the request that made it.
      while (cur is num && n < 32 && seen.add(cur.toInt())) {
        n++;
        final parent = all.firstWhere(
          (x) => (x['id'] as num).toInt() == cur,
          orElse: () => const {},
        );
        cur = parent['parent_id'];
      }
      return n;
    }

    return showModalBottomSheet<(int?, String)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Documents (top level)'),
              onTap: () => Navigator.pop(ctx, (null, 'the top level')),
            ),
            for (final f in all)
              ListTile(
                contentPadding: EdgeInsets.only(
                    left: 16 + depthOf(f) * 18.0, right: 16),
                leading: const Icon(Icons.folder_outlined),
                title: Text('${f['name']}'),
                onTap: () => Navigator.pop(
                    ctx, ((f['id'] as num).toInt(), '${f['name']}')),
              ),
            if (all.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No folders yet. Make one first.'),
              ),
          ],
        ),
      ),
    );
  }

  /// Several documents as ONE file.
  ///
  /// Sharing them individually already works, and this is the other half of
  /// it: twelve files attached one by one is twelve chances to miss one,
  /// where a zip is one thing to send and one thing to receive. It is also
  /// what "sharing" means in this product — the file goes to the owner's own
  /// share sheet, not behind a link.
  Future<void> _exportSelected() async {
    if (_picked.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<Session>().api;
    messenger.showSnackBar(const SnackBar(content: Text('Packing…')));
    try {
      // The zip is BUILT by the server — it holds the files, and asking the
      // phone to download twelve documents and zip them would spend the
      // battery and the connection to arrive at the same bytes.
      final bytes = await api.downloadPost(
          '/api/documents/export', {'ids': _picked.toList()});
      final dir = await getTemporaryDirectory();
      final out = Directory('${dir.path}/share');
      if (!await out.exists()) await out.create(recursive: true);
      final now = DateTime.now();
      final name = 'documents-${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}.zip';
      final f = File('${out.path}/$name');
      await f.writeAsBytes(bytes);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
      if (mounted) setState(_picked.clear);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.status == 404
            ? 'Your computer needs its SafeNest updated for this.'
            : e.message),
      ));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Those could not be packed.')));
    }
  }

  Future<void> _shareSelected() async {
    if (_picked.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final chosen = _docs
        .where((d) => _picked.contains((d['id'] as num).toInt()))
        .toList();
    messenger.showSnackBar(const SnackBar(content: Text('Preparing…')));
    final err = await shareFromServer(
      context.read<Session>().api,
      items: [
        for (final d in chosen)
          (
            path: '${d['file_url']}',
            name: '${d['title'] ?? 'document'}.${d['ext'] ?? 'bin'}',
          ),
      ],
    );
    if (!mounted) return;
    if (err != null) {
      messenger.showSnackBar(SnackBar(content: Text(err)));
    } else {
      setState(_picked.clear);
    }
  }

  /// Extensions the server can show as text or rows. Kept in step with
  /// TEXT_EXT / CSV_EXT / OFFICE_EXT in backend/app/routers/documents.py.
  ///
  /// Duplicated here ON PURPOSE rather than asked for: the listing already
  /// carries `is_text`, and this is only the fallback for a row that predates
  /// that field. Opening the preview and having it 415 is a worse first
  /// impression than not offering it.
  static const _previewable = {
    'txt', 'md', 'log', 'json', 'xml', 'yml', 'yaml', 'ini', 'conf',
    'csv', 'tsv', 'docx', 'xlsx', 'pptx',
  };

  bool _canPreview(Map<String, dynamic> doc) =>
      doc['is_text'] == true ||
      _previewable.contains((doc['ext'] ?? '').toString().toLowerCase());

  /// Read it in the app. Falls back to downloading, which is what every
  /// non-image did before.
  void _preview(Map<String, dynamic> doc) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DocPreviewScreen(
        api: context.read<Session>().api,
        id: (doc['id'] as num).toInt(),
        title: (doc['title'] ?? 'Document').toString(),
        onDownload: () => _open(doc),
      ),
    ));
  }

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

  /// Long-press a document: share it, or open it.
  ///
  /// Sharing a bill or a policy to an accountant, a landlord or an insurer is
  /// most of what a filed document is FOR, and there was no way to get one out
  /// of the app at all.
  Future<void> _actions(Map<String, dynamic> doc) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Share'),
            subtitle: const Text('Sends the file itself, not a link'),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
          if (_canPreview(doc))
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Read here'),
              subtitle: const Text('Without downloading it'),
              onTap: () => Navigator.pop(ctx, 'preview'),
            ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open'),
            onTap: () => Navigator.pop(ctx, 'open'),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Versions'),
            subtitle: const Text('Earlier copies, kept when you replace it'),
            onTap: () => Navigator.pop(ctx, 'versions'),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'open') return _open(doc);
    if (choice == 'preview') return _preview(doc);
    if (choice == 'versions') {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DocVersionsScreen(
            api: context.read<Session>().api,
            id: (doc['id'] as num).toInt(),
            title: '${doc['title'] ?? 'Document'}',
          ),
        ),
      );
      // Restoring changes which file IS the document, so the list behind is
      // showing a stale size and thumbnail until it reloads.
      if (changed == true && mounted) await _load();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<Session>().api;
    messenger.showSnackBar(const SnackBar(content: Text('Preparing…')));
    final name = '${doc['title'] ?? 'document'}.${doc['ext'] ?? 'pdf'}';
    final problem = await shareFromServer(api,
        items: [(path: '${doc['file_url']}', name: name)]);
    if (problem != null && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
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
            onPressed: () async {
              setState(() => _grid = !_grid);
              // Remember it, so the drawer opens the way it was left.
              (await SharedPreferences.getInstance())
                  .setBool(_viewKey, _grid);
            },
          ),
        ],
      ),
      // TWO buttons, and Scan is the big one.
      //
      // Photographing a piece of paper is the thing a phone is better at than
      // the computer — the paper is where the person is. Uploading a file that
      // is already on the phone is the rarer case, so it gets the small button.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'doc-upload',
            onPressed: _upload,
            tooltip: 'Upload a file from this phone',
            child: const Icon(Icons.upload_file),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'doc-scan',
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const ScanScreen()));
              if (saved == true) _load();
            },
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan'),
          ),
        ],
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
          // The way back up. Hidden while searching, because results come
          // from the WHOLE tree and a breadcrumb over them would name a
          // folder most of the results are not in.
          _filterBar(),
          if (_query.isEmpty && _category == 'all') _crumbs(),
          if (_selecting) _selectionBar(),
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
                    : (_docs.isEmpty && _folders.isEmpty)
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

  /// Grouped by what a file IS, not by extension — "was it .xls or .xlsx,
  /// and did I save that one as .csv?" is the question this exists to avoid
  /// having to answer. Keys match TYPE_GROUPS on the server.
  static const _fileTypes = <(String, String)>[
    ('pdf', 'PDFs'),
    ('image', 'Images'),
    ('doc', 'Documents'),
    ('sheet', 'Spreadsheets'),
    ('slides', 'Slides'),
    ('archive', 'Archives'),
    ('other', 'Other'),
  ];

  /// '' is the DEFAULT order — favourites first, then newest — and it is in
  /// the list because naming it is the only way back to it after choosing
  /// another.
  static const _sorts = <(String, String)>[
    ('', 'Starred first'),
    ('name', 'Name'),
    ('oldest', 'Oldest first'),
    ('largest', 'Largest'),
    ('smallest', 'Smallest'),
  ];

  int get _activeFilters =>
      (_ftype.isEmpty ? 0 : 1) +
      ((_since.isEmpty && _until.isEmpty) ? 0 : 1) +
      (_sort.isEmpty ? 0 : 1);

  Widget _filterBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              FilterChip(
                avatar: const Icon(Icons.tune, size: 16),
                label: Text(_activeFilters > 0
                    ? 'Filters ($_activeFilters)'
                    : 'Filters'),
                selected: _filtersOpen || _activeFilters > 0,
                onSelected: (_) =>
                    setState(() => _filtersOpen = !_filtersOpen),
              ),
              if (_activeFilters > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ActionChip(
                    label: const Text('Clear'),
                    onPressed: () {
                      setState(() {
                        _ftype = '';
                        _since = '';
                        _until = '';
                        _sort = '';
                      });
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (_filtersOpen) _filterPanel(),
      ],
    );
  }

  Widget _filterPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (key, label) in _fileTypes)
                ChoiceChip(
                  label: Text(label),
                  selected: _ftype == key,
                  onSelected: (_) {
                    setState(() => _ftype = _ftype == key ? '' : key);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _dateField('From', _since, (v) {
                setState(() => _since = v);
                _load();
              })),
              const SizedBox(width: 8),
              Expanded(child: _dateField('To', _until, (v) {
                setState(() => _until = v);
                _load();
              })),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Sort', style: TextStyle(fontSize: 12.5)),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<String>(
                  value: _sort,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final (key, label) in _sorts)
                      DropdownMenuItem(value: key, child: Text(label)),
                  ],
                  onChanged: (v) {
                    setState(() => _sort = v ?? '');
                    _load();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateField(String label, String value, ValueChanged<String> onPick) {
    return OutlinedButton(
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(value) ?? now,
          firstDate: DateTime(now.year - 30),
          lastDate: DateTime(now.year + 1),
        );
        if (picked == null) return;
        // ISO, because that is what the server parses; anything else is
        // silently ignored by it and looks to the person like a filter that
        // does nothing.
        onPick('${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}');
      },
      onLongPress: value.isEmpty ? null : () => onPick(''),
      child: Text(value.isEmpty ? label : value,
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _crumbs() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          TextButton(
            onPressed: _folder == 0 ? null : () => _openFolder(0),
            child: const Text('Documents'),
          ),
          for (final c in _path) ...[
            const Icon(Icons.chevron_right, size: 16),
            TextButton(
              onPressed: () => _openFolder((c['id'] as num).toInt()),
              child: Text('${c['name']}'),
            ),
          ],
          TextButton.icon(
            onPressed: _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('New folder'),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar() {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear selection',
              onPressed: () => setState(_picked.clear),
            ),
            Expanded(
              child: Text('${_picked.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
                icon: const Icon(Icons.star_border),
                tooltip: 'Star',
                onPressed: () => _bulk('star', 'starred')),
            IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Share',
                onPressed: _shareSelected),
            IconButton(
                icon: const Icon(Icons.folder_zip_outlined),
                tooltip: 'Send as one zip',
                onPressed: _exportSelected),
            IconButton(
                icon: const Icon(Icons.drive_file_move_outline),
                tooltip: 'Move to a folder',
                onPressed: _moveSelected),
            IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Move to recycle bin',
                onPressed: () =>
                    _bulk('trash', 'moved to the recycle bin')),
          ],
        ),
      ),
    );
  }

  /// One folder, as a row. Rename and delete sit behind a long press rather
  /// than two more buttons per row: a wall of folders should read as folders.
  Widget _folderTile(Map<String, dynamic> f) {
    final docs = (f['documents'] as num?)?.toInt() ?? 0;
    final subs = (f['folders'] as num?)?.toInt() ?? 0;
    return ListTile(
      leading: const Icon(Icons.folder, size: 30),
      title: Text('${f['name']}',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (subs > 0) '$subs folder${subs == 1 ? '' : 's'}',
          if (docs > 0) '$docs item${docs == 1 ? '' : 's'}',
          if (subs == 0 && docs == 0) 'Empty',
        ].join(' · '),
        style: const TextStyle(fontSize: 12),
      ),
      onTap: () => _openFolder((f['id'] as num).toInt()),
      onLongPress: () async {
        final choice = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Move to recycle bin'),
                onTap: () => Navigator.pop(ctx, 'trash'),
              ),
            ]),
          ),
        );
        if (choice == 'rename') await _renameFolder(f);
        if (choice == 'trash') await _trashFolder(f);
      },
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
        itemCount: _folders.length + _docs.length,
        itemBuilder: (ctx, index) {
          if (index < _folders.length) {
            final f = _folders[index];
            return InkWell(
              onTap: () => _openFolder((f['id'] as num).toInt()),
              borderRadius: BorderRadius.circular(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder, size: 46),
                  const SizedBox(height: 6),
                  Text('${f['name']}',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            );
          }
          final d = _docs[index - _folders.length];
          final picked = _picked.contains((d['id'] as num).toInt());
          return InkWell(
            onTap: () => _selecting
                ? _toggle((d['id'] as num).toInt())
                : (_canPreview(d) ? _preview(d) : _open(d)),
            onLongPress: () => _toggle((d['id'] as num).toInt()),
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(fit: StackFit.expand, children: [
                    ClipRRect(
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
                    // Shown only when ticked. A permanent circle on every
                    // tile turns a wall of documents into a wall of controls.
                    if (picked)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor:
                              Theme.of(ctx).colorScheme.primary,
                          child: const Icon(Icons.check,
                              size: 16, color: Colors.white),
                        ),
                      ),
                  ]),
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
        itemCount: _folders.length + _docs.length,
        itemBuilder: (ctx, index) {
          if (index < _folders.length) return _folderTile(_folders[index]);
          final i = index - _folders.length;
          final d = _docs[i];
          final tint = _tint(d);
          final cat = '${d['category'] ?? ''}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: BrandCard(
              // Once ANYTHING is selected a tap picks rather than opens.
              // Mixing the two is how somebody selects four documents and
              // loses the lot by tapping the fifth.
              onTap: () => _selecting
                  ? _toggle((d['id'] as num).toInt())
                  : (_canPreview(d) ? _preview(d) : _open(d)),
              onLongPress: () => _selecting
                  ? _toggle((d['id'] as num).toInt())
                  : _actions(d),
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
    if (made != null) bits.add(fmtDate(made));
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


