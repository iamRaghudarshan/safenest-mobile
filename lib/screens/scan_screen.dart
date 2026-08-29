/// Photograph a document and file it — the thing a phone is genuinely better at.
///
/// WHY THE PLATFORM'S OWN SCANNER AND NOT OUR OWN
/// The web app carries a 642-line scanner: live camera, real-time page
/// detection, auto-capture, perspective correction, per-page filters. It has to,
/// because a browser is given a camera stream and nothing else.
///
/// A phone is not in that position. iOS has VisionKit — the scanner Apple Notes
/// uses — and Android has ML Kit's. Both do edge detection, auto-capture,
/// perspective correction, multi-page and colour/greyscale filters, natively,
/// better than a port of the web implementation would, and with none of the
/// code. Reimplementing that in Dart would be building a worse copy of
/// something already on the device.
///
/// THE SERVER ALREADY EXPECTED THIS. `POST /api/documents/scan` takes
/// `files: list[UploadFile]` — one already-enhanced JPEG per page, in order —
/// and assembles them into ONE multi-page PDF, up to 30 pages. (It was 25 MB
/// too; that cap is gone — settings.document_max_mb, 0 by default, because a
/// ceiling this app invents is one the owner cannot argue with.) Its
/// docstring says "the client sends already-enhanced JPEGs", which is precisely
/// what a native scanner hands back. Nothing on the phone had ever called it.
///
/// ORDER MATTERS: the order of the list is the page order of the PDF, which is
/// why pages can be reordered and removed before saving and why that is not a
/// nicety.
library;

import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../api.dart';
import '../offline/store.dart';
import '../masters.dart';
import '../dates.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.initialPages});

  /// For tests — page image paths, so the screen can be laid out without a
  /// camera.
  final List<String>? initialPages;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  List<String> _pages = [];
  String _category = 'other';
  DateTime? _expiry;
  bool _busy = false;
  String? _error;

  List<MasterItem> _categories = const [];

  @override
  void initState() {
    super.initState();
    _pages = widget.initialPages ?? [];
    _loadCategories();
    // Straight into the camera on open. Somebody who tapped "Scan" has already
    // decided; making them tap a second button to start is a step with nothing
    // in it.
    if (widget.initialPages == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final l =
          await context.read<Session>().masters.load('document_category');
      if (mounted) setState(() => _categories = l);
    } catch (_) {
      // The picker falls back to "Other"; a lookup failing must not stop
      // somebody filing a document.
    }
  }

  Future<void> _scan() async {
    try {
      final got = await CunningDocumentScanner.getPictures(
        // The server refuses more than 30 and says so; stopping at the same
        // number means nobody scans 40 pages and is told afterwards.
        noOfPages: 30 - _pages.length,
      );
      if (got == null || got.isEmpty) {
        // Cancelled. If there is nothing at all, leave — an empty scan screen
        // with no pages is a dead end.
        if (mounted && _pages.isEmpty) Navigator.of(context).pop();
        return;
      }
      if (mounted) setState(() => _pages = [..._pages, ...got]);
    } on CunningDocumentScannerException catch (e) {
      if (mounted) {
        setState(() => _error = e.message.contains('permission')
            ? 'SafeNest has not been allowed to use the camera. '
                'Settings → Privacy → Camera → SafeNest.'
            : 'The scanner could not start.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'The scanner could not start.');
    }
  }

  Future<void> _save() async {
    if (_pages.isEmpty) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give it a name so you can find it later.');
      return;
    }
    final session = context.read<Session>();
    final store = context.read<OfflineStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = <({String name, List<int> bytes})>[];
      for (var i = 0; i < _pages.length; i++) {
        final f = File(_pages[i]);
        if (!await f.exists()) continue;
        files.add((name: 'page${i + 1}.jpg', bytes: await f.readAsBytes()));
      }
      if (files.isEmpty) {
        setState(() {
          _error = 'The scanned pages could not be read back.';
          _busy = false;
        });
        return;
      }

      final fields = {
        'title': title,
        'category': _category,
        'notes': _notes.text.trim(),
        if (_expiry != null)
          'expiry_date':
              '${_expiry!.year}-${_expiry!.month.toString().padLeft(2, '0')}'
                  '-${_expiry!.day.toString().padLeft(2, '0')}',
      };

      var queued = false;
      try {
        await session.api.postMultipartFiles(
          '/api/documents/scan',
          fileField: 'files',
          files: files,
          fields: fields,
        );
      } on ApiError catch (e) {
        // A REFUSAL IS NOT AN OUTAGE -- the same rule the record modules use.
        // The computer answering "no" is something the owner can act on now,
        // and queueing it would hide that behind a sync destined to fail the
        // same way. Only a failure to REACH it is held here.
        if (e.status > 0) rethrow;
        // WRITTEN TO DISK FIRST. The scanner hands back bytes in memory, and
        // memory does not survive the app closing -- which is exactly what
        // happens between scanning something on the way out and syncing it
        // that evening. Until this reaches the computer these files are the
        // only copy, so nothing deletes them; that happens after the upload
        // is confirmed.
        final dir = Directory(p.join(
            (await getApplicationDocumentsDirectory()).path,
            'pending_scans',
            DateTime.now().millisecondsSinceEpoch.toString()));
        await dir.create(recursive: true);
        final paths = <String>[];
        for (var i = 0; i < files.length; i++) {
          final f = File(p.join(dir.path, '${i + 1}_${files[i].name}'));
          await f.writeAsBytes(files[i].bytes);
          paths.add(f.path);
        }
        await store.enqueueFiles(
          module: 'documents',
          paths: paths,
          fields: fields,
        );
        queued = true;
      }

      navigator.pop(true);
      messenger.showSnackBar(SnackBar(
          content: Text(queued
              ? 'Saved on this phone — ${files.length} '
                  '${files.length == 1 ? "page" : "pages"}, send it with Sync'
              : 'Saved — ${files.length} '
                  '${files.length == 1 ? "page" : "pages"} in one document'),
          duration: Duration(seconds: queued ? 4 : 2)));
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = kModuleColours['documents']!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a document'),
        actions: [
          if (_pages.isNotEmpty && _pages.length < 30)
            TextButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Add pages'),
            ),
        ],
      ),
      body: _pages.isEmpty
          ? _Waiting(error: _error, onRetry: _scan)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                Text(
                    '${_pages.length} '
                    '${_pages.length == 1 ? "page" : "pages"} — saved as one PDF',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Drag to reorder. The order here is the order in the file.',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),

                // Reorderable, because the page order IS the document. A
                // passport photographed back-page-first is not the same
                // document, and re-scanning to fix it would be absurd.
                SizedBox(
                  height: 190,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    itemCount: _pages.length,
                    // onReorderItem, not onReorder: it already adjusts the
                    // new index for the removed item, so the usual
                    // `if (to > from) to -= 1` fudge is not only unnecessary
                    // here, it would be an off-by-one.
                    onReorderItem: (from, to) => setState(
                        () => _pages.insert(to, _pages.removeAt(from))),
                    itemBuilder: (ctx, i) => ReorderableDragStartListener(
                      key: ValueKey(_pages[i]),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _Page(
                          path: _pages[i],
                          number: i + 1,
                          onRemove: _busy
                              ? null
                              : () => setState(() => _pages.removeAt(i)),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What is it?',
                    hintText: 'e.g. Passport, Rent agreement',
                  ),
                ),
                const SizedBox(height: 14),
                Text('Category', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in _categories) _chip(m.key, m.label, m.emoji, tint),
                  if (_categories.isEmpty) _chip('other', 'Other', null, tint),
                ]),
                const SizedBox(height: 16),
                // Optional, and the one field worth offering here: an expiry is
                // what turns a filed passport into something the app can warn
                // about before it lapses.
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                      side: BorderSide(color: theme.dividerColor)),
                  title: const Text('Expires (optional)',
                      style: TextStyle(fontSize: 14)),
                  subtitle: Text(_expiry == null
                      ? 'Set one and SafeNest reminds you before it lapses'
                      // Was "8/8/2026" — unpadded, and the only place in the
                      // app using slashes.
                      : fmtDate(_expiry)),
                  trailing: const Icon(Icons.event_outlined, size: 18),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _expiry ?? now,
                      firstDate: DateTime(now.year - 30),
                      lastDate: DateTime(now.year + 50),
                    );
                    if (d != null) setState(() => _expiry = d);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 18),
                BrandButton(
                  label: 'Save to my computer',
                  icon: Icons.save_outlined,
                  block: true,
                  busy: _busy,
                  onPressed: _busy ? null : _save,
                ),
                const SizedBox(height: 10),
                Text(
                    'The text is read off it on your computer, so you can search '
                    'for it later by what it says.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall),
              ],
            ),
    );
  }

  Widget _chip(String key, String label, String? emoji, Color tint) {
    final on = _category == key;
    final theme = Theme.of(context);
    return Material(
      color: on ? tint : theme.scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _category = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on ? tint : theme.colorScheme.outlineVariant, width: 1.5),
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
                    color:
                        on ? Colors.white : theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.path, required this.number, this.onRemove});
  final String path;
  final int number;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(
        width: 130,
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.description_outlined)))),
      ),
      Positioned(
        left: 6,
        top: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('$number',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
        ),
      ),
      if (onRemove != null)
        Positioned(
          right: 4,
          top: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 15, color: Colors.white),
            ),
          ),
        ),
    ]);
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.error, required this.onRetry});
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 48, 22, 20),
          child: Column(children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kModuleColours['documents'],
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: kModuleColours['documents']!.withValues(alpha: 0.38),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.document_scanner_outlined,
                  size: 34, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Text(error ?? 'Opening the camera…',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                  'Hold the page in the frame — the edges are found for you, and '
                  'you can add more pages before saving.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            if (error != null) ...[
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 190),
                child: BrandButton(label: 'Try again', onPressed: onRetry),
              ),
            ],
          ]),
        )
      ]);
}

