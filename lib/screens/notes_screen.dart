/// Notes — a Google-Keep-style module on the phone: a two-column masonry of
/// coloured cards (notes and checklists), pinned first, with an editor sheet,
/// colours, labels, pin, archive and a recycle bin, and search across titles,
/// bodies and checklist lines. Its own screen, like Documents or Gallery — not
/// one of the generic record modules.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../alarms.dart';
import '../api.dart';
import '../memory/reminders.dart' show noteAlarmId;
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
  const NotesScreen({super.key, this.debugNotes, this.onBulk});

  /// The notes to draw instead of fetching them, and a hook on what a bulk
  /// action would have sent.
  ///
  /// The same door the rest of this app uses for screens that cannot be stood
  /// up without a server — see LifeMemoryScreen.debugRows for the longer note
  /// on why a widget test must not reach a disk or a network.
  final List<Map<String, dynamic>>? debugNotes;
  final void Function(String action, List<int> ids)? onBulk;

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

  /// SELECTING SEVERAL AT ONCE, which is most of what makes Keep usable.
  ///
  /// Every action here was one note at a time, through three small icons on
  /// each card. Archiving a dozen finished lists meant twelve taps on twelve
  /// cards, each of which re-sorted the grid under the thumb as it went.
  /// Long-press starts a selection; the bar at the top acts on all of it in one
  /// request.
  final Set<int> _picked = <int>{};
  bool get _selecting => _picked.isNotEmpty;

  Api get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    if (widget.debugNotes != null) {
      _notes = widget.debugNotes!;
      _loading = false;
      return;
    }
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
    final messenger = ScaffoldMessenger.of(context);
    final records = context.read<OfflineRecords>();
    try {
      await records.act(_api, 'notes', id, path);
      await _load();
      if (!mounted) return;

      // UNDO ON ARCHIVE AND BIN, which Keep has always had and this did not. A
      // note archived by a mis-tap vanished off the screen with nothing to say
      // what had happened to it, and getting it back meant knowing the Archive
      // bucket existed and which note to look for in it.
      //
      // Pinning is left without one: it does not hide anything, and the control
      // that did it is still right there to tap again.
      if (path != 'archive' && path != 'trash') return;
      messenger.showSnackBar(SnackBar(
        content: Text(path == 'archive' ? 'Archived' : 'Moved to the bin'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              // Both are toggles on the server, so the same call puts it back.
              await records.act(_api, 'notes', id, path);
              await _load();
            } catch (_) {/* the list still shows what is true */}
          },
        ),
      ));
    } catch (_) {/* a failed toggle just leaves the note as it was */}
  }

  Future<void> _delete(int id) async {
    try {
      await context.read<OfflineRecords>().remove(_api, 'notes', id);
      _load();
    } catch (_) {}
  }

  /// One action over everything selected, in ONE request.
  ///
  /// Not a loop over `act`: eleven round trips from a phone each fail on their
  /// own, so a flaky connection leaves some archived and some not with no way
  /// to tell which. The server answers with the ids it changed, which is what
  /// lets Undo name exactly those.
  Future<void> _bulk(String action,
      {Object? value, String? colour, List<String>? labels}) async {
    final ids = _picked.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _picked.clear());
    final watcher = widget.onBulk;
    if (watcher != null) {
      watcher(action, ids);
      if (widget.debugNotes != null) {
        messenger.showSnackBar(SnackBar(
          content: Text(_said(action, ids.length)),
          behavior: SnackBarBehavior.floating,
          action: {'archive', 'trash', 'pin'}.contains(action)
              ? SnackBarAction(label: 'Undo', onPressed: () {})
              : null,
        ));
        return;
      }
    }
    try {
      await _api.post('/api/notes/bulk', {
        'action': action,
        'ids': ids,
        'value': ?value,
        'color': ?colour,
        'labels': ?labels,
      });
      await _load();
      if (!mounted) return;

      // UNDO, because a bulk action is the one most worth being able to take
      // back: a mis-tap that archives eleven notes cannot be unpicked by hand
      // afterwards — you no longer know which eleven.
      final undoable = {'archive', 'trash', 'pin'}.contains(action);
      messenger.showSnackBar(SnackBar(
        content: Text(_said(action, ids.length)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: !undoable
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  try {
                    await _api.post('/api/notes/bulk', {
                      'action': action,
                      'ids': ids,
                      'value': !(value == null ? true : value == true),
                    });
                    await _load();
                  } catch (_) {/* the list still says what is true */}
                },
              ),
      ));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Could not reach your SafeNest — nothing changed.')));
      }
    }
  }

  String _said(String action, int n) {
    final what = n == 1 ? 'note' : 'notes';
    return switch (action) {
      'archive' => '$n $what archived',
      'trash' => '$n $what moved to the bin',
      'pin' => '$n $what pinned',
      'color' => '$n $what recoloured',
      'label' => '$n $what labelled',
      _ => '$n $what changed',
    };
  }

  Future<void> _pickColourForSelection() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _ColourSheet(),
    );
    if (chosen != null) await _bulk('color', colour: chosen);
  }

  Future<void> _labelSelection() async {
    final c = TextEditingController();
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a label'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Trip, Recipes, Work…'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          if (_labels.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in _labels)
                  ActionChip(label: Text(l), onPressed: () => Navigator.pop(ctx, l)),
              ],
            ),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (chosen != null && chosen.isNotEmpty) {
      await _bulk('label', labels: [chosen]);
    }
  }

  /// Keep's "Make a copy" — the thing a note is most often wanted for: a
  /// shopping list you used last week, a packing list, a format.
  Future<void> _copy(int id) async {
    try {
      await _api.post('/api/notes/$id/copy');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Copied'), behavior: SnackBarBehavior.floating));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not copy that — the computer did not answer.')));
    }
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
      appBar: _selecting
          // THE SELECTION BAR REPLACES THE TITLE, as every phone app does it,
          // so there is never any doubt about what the buttons on screen will
          // act on.
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Stop selecting',
                onPressed: () => setState(_picked.clear),
              ),
              title: Text('${_picked.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.push_pin_outlined),
                  tooltip: 'Pin',
                  onPressed: () => _bulk('pin', value: true),
                ),
                IconButton(
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: 'Colour',
                  onPressed: _pickColourForSelection,
                ),
                IconButton(
                  icon: const Icon(Icons.label_outline),
                  tooltip: 'Label',
                  onPressed: _labelSelection,
                ),
                IconButton(
                  icon: Icon(_bucket == 'archived'
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined),
                  tooltip: _bucket == 'archived' ? 'Unarchive' : 'Archive',
                  onPressed: () =>
                      _bulk('archive', value: _bucket != 'archived'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Bin',
                  onPressed: () => _bulk('trash', value: true),
                ),
              ],
            )
          : AppBar(title: const Text('Notes')),
      floatingActionButton: _bucket == 'active' && !_selecting
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
    final todo = [for (final i in items) if (i['checked'] != true) i];
    final done = items.length - todo.length;
    final id = (n['id'] as num?)?.toInt() ?? 0;
    final remindAt = DateTime.tryParse('${n['reminder_at'] ?? ''}');
    final chosen = _picked.contains(id);

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: bg ?? Theme.of(context).colorScheme.surface,
        // NO borderRadius HERE. Material asserts that shape and borderRadius
        // are never both given, and this had both since the card was written —
        // it survived because asserts are stripped from a release build and
        // because no test ever drew a card: the layout sweep stands this screen
        // up without a server, so it only ever rendered the spinner. A widget
        // test with notes in it threw on the first frame.
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              // A SELECTED CARD IS OUTLINED, not tinted: these cards already
              // carry a colour the person chose, and shading them to show
              // selection would fight it — on a dark note it would not be
              // visible at all.
              color: chosen
                  ? kBrand
                  : bg == null
                      ? Theme.of(context).colorScheme.outlineVariant
                      : Colors.transparent,
              width: chosen ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          // ONCE SOMETHING IS SELECTED, a plain tap selects too. Opening the
          // editor mid-selection is the commonest way a multi-select is lost,
          // and losing it means starting the whole selection again.
          onTap: () => _selecting
              ? setState(() {
                  if (!_picked.remove(id)) _picked.add(id);
                })
              : _openEditor(n),
          onLongPress: _bucket == 'trashed'
              ? null
              : () => setState(() {
                    if (!_picked.remove(id)) _picked.add(id);
                  }),
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
                    // KEEP'S SIGNATURE BEHAVIOUR, and the one most missed: what
                    // is still to do comes first, and what is done is counted
                    // rather than listed. A twelve-line shopping list with nine
                    // crossed out showed eight struck-through lines and hid the
                    // three that mattered — the card was spent on the part of
                    // the list already finished.
                    for (final it in todo.take(8))
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
                    if (todo.length > 8)
                      Text('+${todo.length - 8} more',
                          style: const TextStyle(fontSize: 12)),
                    if (done > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                            '$done ticked item${done == 1 ? '' : 's'}',
                            style: TextStyle(
                                fontSize: 11,
                                color: bg != null
                                    ? const Color(0xFF5f6368)
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ),
                    if (todo.isEmpty && items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('All done',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
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
                  // THE REMINDER, ON THE CARD. A note that is going to
                  // interrupt you at nine on Tuesday should say so where you
                  // can see it, not only inside the editor — Keep puts it right
                  // here, under the text, for the same reason.
                  if (remindAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(999)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.notifications_outlined,
                              size: 12,
                              color: bg != null
                                  ? const Color(0xFF202124)
                                  : null),
                          const SizedBox(width: 4),
                          // Flexible, not bare. A card is half the width of the
                          // phone, and on a 320pt one "Tomorrow 09:00" with a
                          // wide font is more than fits — a Row hands an
                          // unwrapped Text all the width it asks for and then
                          // overflows, which is the yellow-and-black stripe
                          // people report as a broken layout.
                          Flexible(
                            child: Text(_whenShort(remindAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: bg != null
                                        ? const Color(0xFF202124)
                                        : null)),
                          ),
                        ]),
                      ),
                    ),
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
                                // PIN STAYS INLINE — it is the one people use
                                // most and the one worth a single tap. The rest
                                // went behind an overflow, as Keep has them,
                                // because four icon buttons do not fit a card
                                // half the width of a 320pt phone: adding a
                                // fourth overflowed by 42 pixels, which the
                                // layout sweep caught the moment it was given a
                                // screen with cards on it.
                                _iconBtn(
                                    n['pinned'] == true
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                    'Pin',
                                    () => _act(n['id'] as int, 'pin'),
                                    bg),
                                PopupMenuButton<String>(
                                  tooltip: 'More',
                                  icon: Icon(Icons.more_vert,
                                      size: 18,
                                      color: bg != null
                                          ? const Color(0xFF5f6368)
                                          : null),
                                  onSelected: (v) {
                                    final id = n['id'] as int;
                                    if (v == 'copy') {
                                      _copy(id);
                                    } else {
                                      _act(id, v);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: 'archive',
                                        child: Text(_bucket == 'archived'
                                            ? 'Unarchive'
                                            : 'Archive')),
                                    const PopupMenuItem(
                                        value: 'copy',
                                        child: Text('Make a copy')),
                                    const PopupMenuItem(
                                        value: 'trash', child: Text('Bin')),
                                  ],
                                ),
                              ]),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  /// "Today 9:00", "Tue 9:00", "14 Oct 9:00" — as short as it can be and still
  /// unambiguous. A reminder chip that says the full date on a card two inches
  /// wide pushes the note's own words off it.
  String _whenShort(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final days = day.difference(today).inDays;
    final clock =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (days == 0) return 'Today $clock';
    if (days == 1) return 'Tomorrow $clock';
    if (days > 1 && days < 7) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${names[d.weekday - 1]} $clock';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    // A reminder in the PAST is worth saying so about: it has already gone off,
    // and a date with no qualifier reads as one still to come.
    final past = days < 0 ? 'Was ' : '';
    return '$past${d.day} ${months[d.month - 1]} $clock';
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

  /// When this note should interrupt you. Null for most notes.
  ///
  /// The column has been on the model since the first release with a comment
  /// calling it stage 2 — stored, shown on the form, acted on by nobody. It is
  /// a local alarm now, scheduled on this phone from the saved value, so it
  /// rings with no signal like every other reminder here.
  DateTime? _remindAt;

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
    _remindAt = DateTime.tryParse('${n?['reminder_at'] ?? ''}');
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

  /// Put this note's reminder in the phone's alarm queue, or take it out.
  ///
  /// Best effort by design: the note is saved either way, and a phone that
  /// refuses exact alarms must not make saving fail.
  Future<void> _syncNoteAlarm() async {
    final id = (widget.note?['id'] as num?)?.toInt();
    if (id == null) return; // a brand new note; the list reschedules on reload
    try {
      final at = _remindAt;
      if (at == null) {
        await Alarms.instance.cancel(noteAlarmId(id));
        return;
      }
      await Alarms.instance.schedule(
        id: noteAlarmId(id),
        title: _title.text.trim().isEmpty ? 'Note' : _title.text.trim(),
        body: _kind == 'checklist'
            ? '${_items.where((i) => i['checked'] != true).length} still to do'
            : _body.text.trim().isEmpty
                ? 'You asked to be reminded about this.'
                : _body.text.trim(),
        when: at,
      );
    } catch (e) {
      debugPrint('[notes] could not set the reminder: $e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      'title': _title.text.trim(),
      'kind': _kind,
      'color': _color,
      'labels': _labels,
      'pinned': _pinned,
      // Empty clears it. The server treats "" as "take it off", so there has to
      // be a value here rather than the key being absent — an absent key means
      // "leave whatever is there", which would make the reminder impossible to
      // remove.
      'reminder_at': _remindAt == null
          ? ''
          : _remindAt!.toIso8601String().substring(0, 19).replaceFirst('T', ' '),
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
      // THE ALARM IS SET HERE, and this is the only moment it can be: the note
      // list does not know the id of something just created, and a reminder
      // saved but never scheduled is the whole feature missing with nothing to
      // point at. Ids are banded away from both the reminders module's and
      // Life Memory's — see noteAlarmId.
      await _syncNoteAlarm();
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
          // REMIND ME. The last of the dead controls on this form: the column
          // existed, the form showed nothing, and nothing ever rang.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_remindAt == null
                ? Icons.notifications_none
                : Icons.notifications_active_outlined),
            title: Text(_remindAt == null
                ? 'Remind me'
                : _niceWhen(_remindAt!)),
            subtitle: _remindAt == null
                ? const Text('Rings on this phone, with or without a signal')
                : null,
            trailing: _remindAt == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'No reminder',
                    onPressed: () => setState(() => _remindAt = null),
                  ),
            onTap: _pickReminder,
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

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _remindAt ?? now.add(const Duration(days: 1)),
      // YESTERDAY IS NOT OFFERED. A reminder in the past cannot ring, and
      // flutter_local_notifications would otherwise fire it the instant it is
      // set — which reads as the app being broken rather than the date being
      // impossible.
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (day == null || !mounted) return;
    final at = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _remindAt ?? DateTime(now.year, now.month, now.day, 9)),
    );
    if (at == null || !mounted) return;
    setState(() =>
        _remindAt = DateTime(day.year, day.month, day.day, at.hour, at.minute));
  }

  String _niceWhen(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final clock =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${d.day} ${months[d.month - 1]} ${d.year}, $clock';
  }

  void _addLabel() {
    final l = _labelInput.text.trim();
    if (l.isNotEmpty && !_labels.contains(l)) setState(() => _labels.add(l));
    _labelInput.clear();
  }
}

/// Keep's palette, as a sheet.
///
/// Shown for a SELECTION rather than per note: recolouring one note is already
/// in its editor, and a second way in there would be two controls for one job.
class _ColourSheet extends StatelessWidget {
  const _ColourSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = _colors.keys.toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Colour',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final name in names)
                InkWell(
                  onTap: () => Navigator.pop(context, name),
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _colors[name] ?? theme.colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant, width: 1.4),
                    ),
                    // The "no colour" swatch needs to say so: an empty white
                    // circle beside eleven coloured ones reads as a missing
                    // image, not as a choice.
                    child: name == 'default'
                        ? Icon(Icons.format_color_reset_outlined,
                            size: 18, color: theme.colorScheme.onSurfaceVariant)
                        : null,
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}
