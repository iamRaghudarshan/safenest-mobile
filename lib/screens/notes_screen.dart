/// Notes — a Google-Keep-style module on the phone: a two-column masonry of
/// coloured cards (notes and checklists), pinned first, with an editor sheet,
/// colours, labels, pin, archive and a recycle bin, and search across titles,
/// bodies and checklist lines. Its own screen, like Documents or Gallery — not
/// one of the generic record modules.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../offline/records.dart';
import '../theme.dart';
import '../session.dart';

// Keep's pastels; text on a coloured card is forced dark to suit them.
const _colors = <String, Color?>{
  'default': null,
  'red': Color(0xFFFAAFA8),
  'orange': Color(0xFFF39F76),
  'yellow': Color(0xFFFFF8B8),
  'green': Color(0xFFE2F6D3),
  'teal': Color(0xFFB4DDD3),
  'blue': Color(0xFFD4E4ED),
  'darkblue': Color(0xFFAECCDC),
  'purple': Color(0xFFD3BFDB),
  'pink': Color(0xFFF6E2DD),
  'brown': Color(0xFFE9E3D4),
  'grey': Color(0xFFEFEFF1),
};

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Map<String, dynamic>> _notes = [];
  List<String> _labels = [];
  String _bucket = 'active';
  String _label = '';
  String _query = '';
  bool _loading = true;
  final _search = TextEditingController();

  Api get _api => context.read<Session>().api;

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

  /// True when this list is the copy held on this phone.
  bool _fromCache = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // THE PLAIN VIEW IS THE ONE HELD ON THIS PHONE. Buckets, labels and
      // search are worked out by the computer, and reproducing that here would
      // be a second implementation to keep in step -- one that would quietly
      // disagree about which notes are archived. So the default view is cached
      // and everything else asks the computer; offline, a filtered view says so
      // rather than showing the wrong notes.
      final plain = _bucket == 'notes' && _label.isEmpty && _query.isEmpty;
      if (plain) {
        final loaded = await context
            .read<OfflineRecords>()
            .list(_api, 'notes');
        if (!mounted) return;
        setState(() {
          _notes = loaded.rows;
          _fromCache = loaded.fromCache;
          _loading = false;
        });
        return;
      }

      final d = await _api.get('/api/notes', {
        'bucket': _bucket,
        if (_label.isNotEmpty) 'label': _label,
        if (_query.isNotEmpty) 'q': _query,
      });
      if (!mounted) return;
      setState(() {
        _notes = [
          for (final e in ((d as Map)['items'] as List? ?? const []))
            Map<String, dynamic>.from(e as Map)
        ];
        _labels = [for (final l in (d['labels'] as List? ?? const [])) '$l'];
        _fromCache = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(int id, String path) async {
    try {
      await context
          .read<OfflineRecords>()
          .act(_api, 'notes', id, path);
      _load();
    } catch (_) {/* a failed toggle just leaves the note as it was */}
  }

  Future<void> _delete(int id) async {
    try {
      await context.read<OfflineRecords>().remove(_api, 'notes', id);
      _load();
    } catch (_) {}
  }

  Future<void> _openEditor([Map<String, dynamic>? note, bool checklist = false]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NoteEditor(note: note, api: _api, startChecklist: checklist),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pinned = _notes.where((n) => n['pinned'] == true).toList();
    final others = _notes.where((n) => n['pinned'] != true).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      floatingActionButton: _bucket == 'active'
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('New note'))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) { setState(() => _query = v.trim()); _load(); },
            decoration: InputDecoration(
              hintText: 'Search notes — including words inside them',
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
        // The "Take a note…" bar, the way Google Keep opens — a tap starts a
        // note, the icon starts a checklist.
        if (_bucket == 'active')
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openEditor(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                  child: Row(children: [
                    Expanded(
                      child: Text('Take a note…',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 15)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check_box_outlined),
                      tooltip: 'New checklist',
                      onPressed: () => _openEditor(null, true),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            children: [
              for (final b in const [
                ('active', 'Notes'),
                ('archived', 'Archive'),
                ('trashed', 'Bin')
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(b.$2),
                    selected: _bucket == b.$1,
                    onSelected: (_) {
                      setState(() { _bucket = b.$1; _label = ''; });
                      _load();
                    },
                  ),
                ),
              if (_labels.isNotEmpty)
                const VerticalDivider(width: 16, indent: 8, endIndent: 8),
              if (_labels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _label.isEmpty,
                    onSelected: (_) { setState(() => _label = ''); _load(); },
                  ),
                ),
              for (final l in _labels)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: const Icon(Icons.label_outline, size: 16),
                    label: Text(l),
                    selected: _label == l,
                    onSelected: (_) { setState(() => _label = l); _load(); },
                  ),
                ),
            ],
          ),
        ),
        if (_fromCache && !_loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(children: [
              const Icon(Icons.cloud_off, size: 15, color: kWarn),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'From this phone — not checked with your computer',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _notes.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 96),
                        children: [
                          if (pinned.isNotEmpty && _bucket == 'active') ...[
                            _sectionTitle('Pinned'),
                            _masonry(pinned),
                            if (others.isNotEmpty) _sectionTitle('Others'),
                            _masonry(others),
                          ] else
                            _masonry(_notes),
                        ],
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('💡', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              _bucket == 'active'
                  ? 'No notes yet — tap New to jot one down or start a checklist.'
                  : _bucket == 'archived'
                      ? 'Nothing archived.'
                      : 'The bin is empty.',
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  /// Two-column masonry: split by index so uneven heights interleave like Keep.
  Widget _masonry(List<Map<String, dynamic>> notes) {
    final left = <Widget>[], right = <Widget>[];
    for (var i = 0; i < notes.length; i++) {
      (i.isEven ? left : right).add(_card(notes[i]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(children: left)),
      Expanded(child: Column(children: right)),
    ]);
  }

  Widget _card(Map<String, dynamic> n) {
    final bg = _colors[n['color'] ?? 'default'];
    final items = [
      for (final it in (n['items'] as List? ?? const []))
        Map<String, dynamic>.from(it as Map)
    ];
    final labels = [for (final l in (n['labels'] as List? ?? const [])) '$l'];
    final title = '${n['title'] ?? ''}';
    final body = '${n['body'] ?? ''}';
    final isChecklist = n['kind'] == 'checklist';
    final done = items.where((i) => i['checked'] == true).length;

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: bg ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        elevation: bg == null ? 0 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: bg == null
                  ? Theme.of(context).colorScheme.outlineVariant
                  : Colors.transparent),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openEditor(n),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 6),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: bg != null ? const Color(0xFF202124) : null)),
                  if (isChecklist) ...[
                    if (title.isNotEmpty) const SizedBox(height: 4),
                    for (final it in items.take(8))
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(
                            it['checked'] == true
                                ? Icons.check_box_outlined
                                : Icons.check_box_outline_blank,
                            size: 16,
                            color: bg != null ? const Color(0xFF202124) : null),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('${it['text'] ?? ''}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      bg != null ? const Color(0xFF202124) : null,
                                  decoration: it['checked'] == true
                                      ? TextDecoration.lineThrough
                                      : null)),
                        ),
                      ]),
                    if (items.length > 8)
                      Text('+${items.length - 8} more',
                          style: const TextStyle(fontSize: 12)),
                    if (items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('$done/${items.length} done',
                            style: TextStyle(
                                fontSize: 11,
                                color: bg != null
                                    ? const Color(0xFF5f6368)
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ),
                  ] else if (body.isNotEmpty) ...[
                    if (title.isNotEmpty) const SizedBox(height: 4),
                    Text(body,
                        maxLines: 12,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: bg != null ? const Color(0xFF202124) : null)),
                  ],
                  if (labels.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final l in labels)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(999)),
                              child: Text(l,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: bg != null
                                          ? const Color(0xFF202124)
                                          : null)),
                            ),
                        ],
                      ),
                    ),
                  // Actions
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _bucket == 'trashed'
                            ? [
                                _iconBtn(Icons.restore, 'Restore',
                                    () => _act(n['id'] as int, 'restore'), bg),
                                _iconBtn(Icons.delete_forever, 'Delete for good',
                                    () => _delete(n['id'] as int), bg),
                              ]
                            : [
                                _iconBtn(
                                    n['pinned'] == true
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                    'Pin',
                                    () => _act(n['id'] as int, 'pin'),
                                    bg),
                                _iconBtn(Icons.archive_outlined,
                                    _bucket == 'archived' ? 'Unarchive' : 'Archive',
                                    () => _act(n['id'] as int, 'archive'), bg),
                                _iconBtn(Icons.delete_outline, 'Bin',
                                    () => _act(n['id'] as int, 'trash'), bg),
                              ]),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap, Color? bg) =>
      IconButton(
        icon: Icon(icon,
            size: 18, color: bg != null ? const Color(0xFF5f6368) : null),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      );
}

// ---------------------------------------------------------------- the editor
class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.note, required this.api, this.startChecklist = false});
  final Map<String, dynamic>? note;
  final Api api;
  final bool startChecklist;
  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _labelInput;
  late String _kind;
  late String _color;
  late List<String> _labels;
  late List<Map<String, dynamic>> _items;
  late bool _pinned;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _title = TextEditingController(text: '${n?['title'] ?? ''}');
    _body = TextEditingController(text: '${n?['body'] ?? ''}');
    _labelInput = TextEditingController();
    _kind = widget.startChecklist ? 'checklist' : '${n?['kind'] ?? 'note'}';
    _color = '${n?['color'] ?? 'default'}';
    _labels = [for (final l in (n?['labels'] as List? ?? const [])) '$l'];
    _items = [
      for (final it in (n?['items'] as List? ?? const []))
        {'text': '${(it as Map)['text'] ?? ''}', 'checked': it['checked'] == true}
    ];
    if (_items.isEmpty) _items = [{'text': '', 'checked': false}];
    _pinned = n?['pinned'] == true;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _labelInput.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      'title': _title.text.trim(),
      'kind': _kind,
      'color': _color,
      'labels': _labels,
      'pinned': _pinned,
      'body': _kind == 'note' ? _body.text : '',
      'items': _kind == 'checklist'
          ? [
              for (final it in _items)
                if ('${it['text']}'.trim().isNotEmpty)
                  {'text': it['text'], 'checked': it['checked']}
            ]
          : [],
    };
    try {
      final id = widget.note?['id'];
      if (id != null) {
        await context
            .read<OfflineRecords>()
            .save(widget.api, 'notes', id: id, body: body);
      } else {
        await context.read<OfflineRecords>().save(widget.api, 'notes', body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not save the note')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _title,
            autofocus: widget.note == null,
            decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          // Note ⇄ Checklist
          Row(children: [
            ChoiceChip(
                label: const Text('Note'),
                selected: _kind == 'note',
                onSelected: (_) => setState(() => _kind = 'note')),
            const SizedBox(width: 8),
            ChoiceChip(
                label: const Text('Checklist'),
                selected: _kind == 'checklist',
                onSelected: (_) => setState(() => _kind = 'checklist')),
          ]),
          const SizedBox(height: 8),
          if (_kind == 'note')
            TextField(
              controller: _body,
              maxLines: null,
              minLines: 4,
              decoration: const InputDecoration(hintText: 'Write something…'),
            )
          else
            Column(children: [
              for (var i = 0; i < _items.length; i++)
                Row(children: [
                  Checkbox(
                      value: _items[i]['checked'] == true,
                      onChanged: (v) =>
                          setState(() => _items[i]['checked'] = v ?? false)),
                  Expanded(
                    child: TextField(
                      controller:
                          TextEditingController(text: '${_items[i]['text']}')
                            ..selection = TextSelection.collapsed(
                                offset: '${_items[i]['text']}'.length),
                      onChanged: (v) => _items[i]['text'] = v,
                      decoration:
                          const InputDecoration(hintText: 'List item', isDense: true),
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _items.removeAt(i))),
                ]),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _items.add({'text': '', 'checked': false})),
                    icon: const Icon(Icons.add),
                    label: const Text('Add item')),
              ),
            ]),
          const SizedBox(height: 8),
          // Colours
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final e in _colors.entries)
                GestureDetector(
                  onTap: () => setState(() => _color = e.key),
                  child: Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: e.value ?? Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _color == e.key
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: _color == e.key ? 2.5 : 1),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          // Labels
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final l in _labels)
              InputChip(
                  label: Text(l),
                  onDeleted: () => setState(() => _labels.remove(l))),
          ]),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _labelInput,
                decoration: const InputDecoration(hintText: 'Add a label', isDense: true),
                onSubmitted: (_) => _addLabel(),
              ),
            ),
            TextButton(onPressed: _addLabel, child: const Text('Add')),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pin to top'),
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(widget.note == null ? 'Create note' : 'Save changes'),
            ),
          ),
        ]),
      ),
    );
  }

  void _addLabel() {
    final l = _labelInput.text.trim();
    if (l.isNotEmpty && !_labels.contains(l)) setState(() => _labels.add(l));
    _labelInput.clear();
  }
}
