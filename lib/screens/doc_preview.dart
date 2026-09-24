/// Reading a document without downloading it first.
///
/// WHAT THE PHONE WAS DOING BEFORE. Every document that was not an image or a
/// PDF offered one thing: download it and open it in whatever the phone had.
/// That is fine for acting on a file and hopeless for the question people
/// actually have in a list — "which letter is this?" — because answering it
/// cost a download, an app switch, and a trip back.
///
/// The server reads the content and sends it as text or rows: plain text,
/// CSV, and the modern Office formats, which are ZIPs of XML and need no
/// converter installed anywhere. See backend/app/officedoc.py for why that is
/// not LibreOffice.
///
/// WHAT IT CANNOT SHOW, AND SAYS SO. Layout, images and formatting are not
/// there. A Word file rendered as bare paragraphs with no warning reads as a
/// document that has LOST its formatting, and somebody goes looking for the
/// version that still had it — so the screen says "text only" out loud and
/// keeps the download a tap away.
library;

import 'package:flutter/material.dart';

import '../api.dart';

class DocPreviewScreen extends StatefulWidget {
  const DocPreviewScreen({
    super.key,
    required this.api,
    required this.id,
    required this.title,
    this.onDownload,
  });

  final Api api;
  final int id;
  final String title;

  /// Offered whenever the preview cannot show everything — which is most of
  /// the time for an Office file.
  final Future<void> Function()? onDownload;

  @override
  State<DocPreviewScreen> createState() => _DocPreviewScreenState();
}

class _DocPreviewScreenState extends State<DocPreviewScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.get('/api/documents/${widget.id}/preview');
      if (!mounted) return;
      setState(() => _data = (d as Map).cast<String, dynamic>());
    } on ApiError catch (e) {
      if (!mounted) return;
      // 415 is not a fault: it is the server saying this kind of file has no
      // text in it to show. Worth different words from a real failure.
      setState(() => _error = e.status == 415
          ? 'This kind of file cannot be shown as text.'
          : e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'That could not be read.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.onDownload != null)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download',
              onPressed: () => widget.onDownload!(),
            ),
        ],
      ),
      body: _error != null
          ? _Message(text: _error!, onDownload: widget.onDownload)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : _body(_data!),
    );
  }

  Widget _body(Map<String, dynamic> p) {
    final kind = (p['kind'] ?? '').toString();
    final truncated = p['truncated'] == true;
    final textOnly = p['text_only'] == true;

    Widget content;
    switch (kind) {
      case 'csv':
      case 'sheet':
        content = _Rows(rows: _rows(p['rows']));
        break;
      case 'doc':
        content = _Paragraphs(lines: _strings(p['paragraphs']));
        break;
      case 'slides':
        content = _Slides(slides: (p['slides'] as List? ?? const [])
            .map((s) => _strings(s))
            .toList());
        break;
      default:
        content = _PlainText(text: (p['text'] ?? '').toString());
    }

    return Column(
      children: [
        Expanded(child: content),
        if (truncated || textOnly)
          _Note(
            text: textOnly
                ? 'Text only — layout, images and formatting are not shown.'
                    '${truncated ? ' Only the first part is here.' : ''}'
                    ' Download it to see the document itself.'
                : 'Showing the start of this file. Download it to see the rest.',
            onDownload: widget.onDownload,
          ),
      ],
    );
  }

  static List<String> _strings(Object? v) =>
      (v as List? ?? const []).map((e) => (e ?? '').toString()).toList();

  static List<List<String>> _rows(Object? v) => (v as List? ?? const [])
      .map((r) => (r as List? ?? const []).map((c) => (c ?? '').toString()).toList())
      .toList();
}

class _PlainText extends StatelessWidget {
  const _PlainText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.55,
        ),
      ),
    );
  }
}

class _Paragraphs extends StatelessWidget {
  const _Paragraphs({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    // Measured for READING, not for data: a letter set in the same monospace
    // as a log file is a letter nobody reads.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final line = lines[i];
        if (line.trim().isEmpty) return const SizedBox(height: 12);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SelectableText(
            line,
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
        );
      },
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.rows});
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('Nothing in this sheet.'));
    }
    // Scrolls both ways. A spreadsheet wrapped to the phone's width stops
    // being a table, and a table nobody can line up is worse than a list.
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(
            color: Colors.black.withValues(alpha: 0.12),
            width: 1,
          ),
          children: [
            for (var i = 0; i < rows.length; i++)
              TableRow(
                // The first row is treated as a header for LOOKS only. Plenty
                // of exports have no header, and styling a data row bold is a
                // much smaller wrong than dropping it.
                decoration: i == 0
                    ? BoxDecoration(color: Colors.black.withValues(alpha: 0.05))
                    : null,
                children: [
                  for (final cell in rows[i])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      child: Text(
                        cell,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400,
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

class _Slides extends StatelessWidget {
  const _Slides({required this.slides});
  final List<List<String>> slides;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: slides.length,
      itemBuilder: (context, i) {
        final lines = slides[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      lines.isEmpty ? 'No text on this slide' : lines.first,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              for (final line in lines.skip(1))
                Padding(
                  padding: const EdgeInsets.only(left: 32, top: 6),
                  child: Text(line,
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.onDownload});
  final String text;
  final Future<void> Function()? onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, height: 1.45)),
          ),
          if (onDownload != null)
            TextButton(
              onPressed: () => onDownload!(),
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onDownload});
  final String text;
  final Future<void> Function()? onDownload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 44),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.5)),
            if (onDownload != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => onDownload!(),
                child: const Text('Download it'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
