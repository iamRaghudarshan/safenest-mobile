/// One list and one sheet, for all seven record modules.
///
/// WHAT WAS MISSING, and it was most of the screen: you could add a record and
/// long-press to delete one, and that was all. There was no way to EDIT
/// anything, no filter, and no way to mark a card or a loan paid. Every web
/// screen does all four — tap a row, a sheet opens filled in, save or delete
/// from inside it — so the phone was not a smaller version of the web app, it
/// was a much emptier one.
///
/// A SHEET, not a pushed page, because that is what the web app uses and because
/// on a phone a sheet keeps the list visible behind it. Add and edit are the
/// same sheet: an empty one is an add, a filled one is an edit, and having two
/// would mean fixing every field twice.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'dart:async';

import '../alarms.dart';
import '../api.dart';
import '../modules.dart';
import '../dates.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/card_face.dart';
import '../widgets/expense_calendar.dart';
import '../widgets/master_picker.dart';
import '../widgets/pill.dart';
import '../widgets/skeleton.dart';

class ModuleListScreen extends StatefulWidget {
  const ModuleListScreen(
      {super.key, required this.spec, this.embedded = false, this.initialRows});
  final ModuleSpec spec;

  /// True when this IS a tab rather than a screen pushed on top of one — a tab
  /// with a back arrow is a tab that looks broken.
  final bool embedded;

  /// Rows to start from instead of fetching, so a test can lay the screen and
  /// its sheet out without a server. Same device the Dashboard uses; the forms
  /// grew from four fields to seven and nothing here could be laid out to check
  /// whether they still fit a small phone.
  final List<Map<String, dynamic>>? initialRows;

  @override
  State<ModuleListScreen> createState() => _ModuleListScreenState();
}

class _ModuleListScreenState extends State<ModuleListScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  ApiError? _err;
  String _filter = '';
  bool _calendar = false;

  /// Only Expenses gets a calendar: it is the one module where "what did a day
  /// cost" is a question, and it has a real date to hang a grid on. Guarding on
  /// the date field alone would put an empty calendar on Documents.
  bool get _hasCalendar => widget.spec.key == 'expenses';

  /// Cards and loans can be marked paid; the others have no such idea.
  bool get _payable =>
      widget.spec.key == 'cards' || widget.spec.key == 'loans';

  /// Reminders and to-dos can be ticked off, and could not be from this app at
  /// all. Both have had a /toggle endpoint since the beginning; nothing here
  /// called it, so the only way to finish something was to delete it — which
  /// also threw away the record that it had ever been done.
  bool get _tickable =>
      widget.spec.key == 'reminders' || widget.spec.key == 'todos';

  /// Done, for whichever of the two it is. Reminders carry is_done (0/1) and
  /// to-dos carry status ('pending'/'done'); they are not the same field and
  /// there is no third thing to fall back on.
  bool _isDone(Map<String, dynamic> r) =>
      r['is_done'] == 1 || r['is_done'] == true || r['status'] == 'done';

  @override
  void initState() {
    super.initState();
    if (widget.initialRows != null) {
      _rows = widget.initialRows!;
      _loading = false;
      return;
    }
    // Expenses opens on the calendar — "what did a day cost" is the question this
    // module is most often asked. The list is a tap away on the toggle.
    _calendar = _hasCalendar;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<Session>().api.get('/api/${widget.spec.key}');
      final list = d is List
          ? d
          : (d is Map ? (d['items'] ?? d['rows'] ?? const []) : const []);
      setState(() {
        _rows = [for (final e in (list as List)) Map<String, dynamic>.from(e as Map)];
        _loading = false;
        _err = null;
      });
      // ALARMS FOLLOW THE SERVER. Re-scheduled from the rows just fetched, so
      // a reminder deleted or re-timed on the computer stops ringing here —
      // otherwise the phone keeps a schedule set days ago and goes off for
      // something already done, which is how people learn to ignore it.
      //
      // Only for reminders, and never blocking the list: an alarm that could
      // not be scheduled must not stop somebody seeing what is due.
      if (widget.spec.key == 'reminders') {
        unawaited(Alarms.instance.syncFrom(_rows).catchError((_) => 0));
      }
    } on ApiError catch (e) {
      setState(() {
        _err = e;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _shown {
    var out = _rows;
    if (_filter.isNotEmpty) {
      final q = _filter.toLowerCase();
      out = _rows.where((r) {
        // Searches every field rather than just the title: looking for "HDFC"
        // should find a card whose bank it is, even though the row is titled by
        // something else.
        return r.values.any((v) => '$v'.toLowerCase().contains(q));
      }).toList();
    }
    if (!_tickable) return out;

    // Finished things sink, and what is late rises. The server returns reminders
    // in is_done then due_date order and to-dos in status then due_date order,
    // which is close — but a list you have been ticking through redraws with the
    // done ones still sitting where they were until the next reload, and the
    // item you just completed staying at the top reads as the tap not working.
    final sorted = [...out];
    sorted.sort((a, b) {
      final da = _isDone(a), db = _isDone(b);
      if (da != db) return da ? 1 : -1;
      final ka = a['days'] is num ? (a['days'] as num).toInt() : 1 << 30;
      final kb = b['days'] is num ? (b['days'] as num).toInt() : 1 << 30;
      return ka.compareTo(kb);
    });
    return sorted;
  }

  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse('${v ?? ''}');
    if (n == null) return '';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);
  }

  Future<void> _openSheet([Map<String, dynamic>? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RecordSheet(spec: widget.spec, existing: existing),
    );
    if (saved == true) _load();
  }

  /// The tinted badges on a row: when it is due, whether it is paid, how
  /// urgent it is. Transcribed from format.ts::dueLabel, which the web list uses
  /// for exactly the same job — same wording, same thresholds, same tones, so a
  /// reminder reading "2d overdue" in red on the laptop reads the same here.
  List<Widget> _badges(
      Map<String, dynamic> r, int? days, bool late, bool done) {
    final out = <Widget>[];

    if (_payable) {
      final paid = r['paid_this_month'] == true;
      out.add(Pill(paid ? 'Paid this month' : 'Not paid',
          tone: paid ? PillTone.ok : PillTone.warn,
          icon: paid ? Icons.check_circle_outline : Icons.schedule));
    }

    // A finished thing needs no urgency badge; saying "3d overdue" next to
    // something already ticked off is just wrong.
    if (!done && days != null) {
      if (days < 0) {
        out.add(Pill('${days.abs()}d overdue',
            tone: PillTone.danger, icon: Icons.priority_high));
      } else if (days == 0) {
        out.add(const Pill('Due today',
            tone: PillTone.danger, icon: Icons.today_outlined));
      } else if (days == 1) {
        out.add(const Pill('Due tomorrow', tone: PillTone.warn));
      } else if (days <= 7) {
        out.add(Pill('In $days days', tone: PillTone.warn));
      }
      // Beyond a week is not news, and a row of grey pills on everything makes
      // the coloured ones stop meaning anything.
    }

    if (!done && '${r['time_fmt'] ?? ''}'.isNotEmpty) {
      out.add(Pill('${r['time_fmt']}',
          tone: PillTone.brand, icon: Icons.notifications_active_outlined));
    }

    if (widget.spec.key == 'todos' && !done) {
      final p = '${r['priority'] ?? ''}';
      if (p == 'high') {
        out.add(const Pill('High', tone: PillTone.danger));
      } else if (p == 'low') {
        out.add(const Pill('Low', tone: PillTone.muted));
      }
      // 'medium' is the default and the common case — a badge on nearly every
      // row is noise, not information.
    }

    final rec = '${r['recurrence'] ?? 'none'}';
    if (rec != 'none' && rec.isNotEmpty && rec != 'null') {
      out.add(Pill(prettyChoice(rec),
          tone: PillTone.muted, icon: Icons.repeat));
    }

    return out;
  }

  Future<void> _pay(Map<String, dynamic> row, {required bool paid}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<Session>()
          .api
          .post('/api/${widget.spec.key}/${row['id']}/${paid ? 'pay' : 'unpay'}', {});
      _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<Session>()
          .api
          .post('/api/${widget.spec.key}/${row['id']}/toggle', {});
      _load();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final theme = Theme.of(context);
    final rows = _shown;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.label),
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          if (_hasCalendar)
            IconButton(
              tooltip: _calendar ? 'List' : 'Calendar',
              icon: Icon(_calendar
                  ? Icons.view_list_outlined
                  : Icons.calendar_month_outlined),
              onPressed: () => setState(() => _calendar = !_calendar),
            ),
        ],
      ),
      // .fab — 58px, radius 20, the 135° brand gradient and its glow. Material's
      // default is a flat circle in one colour, which is the one control on the
      // screen that should look like the app rather than like Android.
      floatingActionButton: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kBrand, kBrand2],
          ),
          boxShadow: [
            BoxShadow(
              color: kBrand.withValues(alpha: 0.44),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          // A Container with an InkWell is not a button as far as a screen
          // reader is concerned — it announces nothing and has no role. The
          // widget this replaced carried both for free, so they have to be put
          // back by hand rather than lost to a nicer gradient.
          child: Semantics(
            button: true,
            label: 'Add to ${s.label}',
            child: Tooltip(
              message: 'Add to ${s.label}',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openSheet(),
                child: const Icon(Icons.add, size: 30, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
      body: Column(children: [
        if (!_calendar && _rows.length > 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: TextField(
              onChanged: (v) => setState(() => _filter = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search ${s.label.toLowerCase()}',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        Expanded(
          child: _loading
              // Placeholder cards, not a spinner — the shape of what is coming
              // reads as "loading" where a lone circle on a blank page reads as
              // "broken", and over a home network that wait is long enough to
              // matter.
              ? const SkeletonList()
              : _err != null
                  ? _LoadError(message: _err!.message, onRetry: _load)
                  : _calendar
                      ? RefreshIndicator(
                          onRefresh: _load,
                          child: ExpenseCalendar(
                            rows: _rows,
                            dateField: s.dateField!,
                            amountField: s.amountField!,
                            titleField: s.titleField,
                            subtitleField: s.subtitleField,
                            onTapRow: (r) => _openSheet(r),
                          ),
                        )
                      : rows.isEmpty
                      ? _Empty(
                          spec: s,
                          filtered: _filter.isNotEmpty,
                          onAdd: () => _openSheet())
                      : RefreshIndicator(
                          onRefresh: _load,
                          // Cards with air between them, not flat rows divided
                          // by hairlines. A divided list is a desktop table; on a
                          // phone each record should be a thing you can tap,
                          // which means it needs edges.
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
                            itemCount: rows.length,
                            itemBuilder: (ctx, i) {
                              final r = rows[i];
                              final amount = s.amountField == null
                                  ? ''
                                  : _money(r[s.amountField]);
                              final date = s.dateField == null
                                  ? ''
                                  : '${r[s.dateField] ?? ''}';
                              final sub = [
                                if (s.subtitleField != null &&
                                    '${r[s.subtitleField] ?? ''}'.isNotEmpty)
                                  '${r[s.subtitleField]}',
                                if (date.isNotEmpty) date,
                                // An hour is the thing you scan a reminder list
                                // for, so it goes on the line rather than being
                                // reachable only by opening the record.
                                if ('${r['time_fmt'] ?? ''}'.isNotEmpty)
                                  '${r['time_fmt']}',
                                if ('${r['recurrence'] ?? 'none'}' != 'none' &&
                                    '${r['recurrence'] ?? ''}'.isNotEmpty)
                                  prettyChoice('${r['recurrence']}'),
                              ].join(' · ');
                              // paid_this_month is what the endpoint actually
                              // returns. is_paid and paid are not fields of
                              // anything, so this tick was stuck on "unpaid" for
                              // every card and every loan however often it was
                              // pressed.
                              final paid = r['paid_this_month'] == true;
                              final done = _isDone(r);
                              // days is negative once something is late. The web
                              // app colours these; the phone showed a late
                              // reminder exactly like one due next month.
                              final days = r['days'] is num
                                  ? (r['days'] as num).toInt()
                                  : null;
                              final late = !done && days != null && days < 0;
                              final accent = rowAccent(s, r);
                              // Built once. It was called twice per row — once
                              // to ask whether it was empty and once to render —
                              // which is a list-length multiplier on work that
                              // allocates widgets.
                              final badges = _badges(r, days, late, done);

                              // CARDS DO NOT LOOK LIKE LIST ROWS. The web app
                              // draws an actual credit card — bank gradient,
                              // gold chip, masked number, due date and limit —
                              // and the phone was rendering the same generic
                              // row it uses for an expense.
                              if (s.key == 'cards') {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: CardFace(
                                    card: r,
                                    onTap: () => _openSheet(r),
                                    onPay: () => _pay(r, paid: !paid),
                                  ),
                                );
                              }

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: BrandCard(
                                  onTap: () => _openSheet(r),
                                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                                  // Badges sit UNDER the row, across the whole
                                  // card, rather than inside the title column.
                                  // Beside the amount and the pay button they
                                  // were squeezed into 41 logical pixels and
                                  // every pill overflowed its own text — a
                                  // horizontal row is the wrong place for
                                  // something that needs to wrap.
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                  Row(children: [
                                    // .rowitem .grip — 44px, radius 13, SOLID
                                    // colour, white 22px glyph. A 4px bar was
                                    // here before: technically the accent, but
                                    // so thin that every list read as grey.
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: accent.colour,
                                        borderRadius: BorderRadius.circular(13),
                                        boxShadow: [
                                          BoxShadow(
                                            color: accent.colour
                                                .withValues(alpha: 0.32),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Icon(accent.icon,
                                          size: 22, color: Colors.white),
                                    ),
                                    const SizedBox(width: 12),
                                    if (_tickable)
                                      // The tick is the primary action on these
                                      // two modules, so it sits first and at
                                      // full touch size rather than being an
                                      // afterthought at the end of the row.
                                      IconButton(
                                        tooltip: done ? 'Not done yet' : 'Done',
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(
                                          done
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          color: done
                                              ? kOk
                                              : theme.colorScheme.outline,
                                        ),
                                        onPressed: () => _toggle(r),
                                      ),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('${r[s.titleField] ?? '—'}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                decoration: done
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                                color: done
                                                    ? theme.colorScheme
                                                        .onSurfaceVariant
                                                    : null,
                                              )),
                                          if (sub.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(sub,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                        color: late
                                                            ? kDanger
                                                            : null)),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (amount.isNotEmpty)
                                      Text(amount,
                                          style: TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w800,
                                              // Tabular figures, so a column of
                                              // amounts lines up on the decimal
                                              // instead of jittering per row.
                                              fontFeatures: const [
                                                FontFeature.tabularFigures()
                                              ],
                                              // The row's accent, not the
                                              // module's: money coming IN reads
                                              // green and an investment that is
                                              // down reads red.
                                              color: accent.colour)),
                                    if (_payable)
                                      IconButton(
                                        tooltip:
                                            paid ? 'Mark not paid' : 'Mark paid',
                                        icon: Icon(
                                          paid
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          color: paid
                                              ? kOk
                                              : theme.colorScheme.outline,
                                        ),
                                        onPressed: () => _pay(r, paid: !paid),
                                      ),
                                  ]),
                                  if (badges.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    // Indented to the title, not to the card, so
                                    // the badges read as belonging to the record
                                    // rather than floating under it.
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(left: 56, right: 4),
                                      child: Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: badges),
                                    ),
                                  ],
                                ]),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}

/// Add or edit — the same sheet, because an empty one is an add.
class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.spec, this.existing});
  final ModuleSpec spec;
  final Map<String, dynamic>? existing;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  final _values = <String, dynamic>{};
  final _controllers = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    for (final f in widget.spec.fields) {
      final current = e?[f.key];
      switch (f.kind) {
        case FieldKind.choice:
          _values[f.key] = current?.toString() ??
              (f.choices.isNotEmpty ? f.choices.first : null);
        case FieldKind.master:
          // Never defaulted to the first item. Pre-selecting a category means
          // every expense saved without touching the field is filed under
          // whatever happens to sort first, which is worse than being asked.
          _values[f.key] =
              (current == null || '$current'.isEmpty) ? null : '$current';
        case FieldKind.toggle:
          _values[f.key] = current == 1 || current == true;
        case FieldKind.date:
          _values[f.key] = current?.toString() ??
              (f.required ? wireDate(DateTime.now()) : null);
        case FieldKind.time:
          // Never defaulted, even on a required-looking field. A time nobody
          // chose is an alarm nobody asked for, and it would go off.
          _values[f.key] = (current == null || '$current'.isEmpty) ? null : '$current';
        default:
          _controllers[f.key] =
              TextEditingController(text: current == null ? '' : '$current');
      }
      _controllers.putIfAbsent(f.key, () => TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final body = <String, dynamic>{};
    for (final f in widget.spec.fields) {
      switch (f.kind) {
        case FieldKind.choice:
        case FieldKind.date:
        case FieldKind.master:
          if (_values[f.key] != null) body[f.key] = _values[f.key];
        case FieldKind.time:
          // Sent even when empty, unlike every other field. The server only
          // clears a time when the key is PRESENT and blank — omitting it means
          // "leave it as it was", so a cleared alarm would quietly come back.
          body[f.key] = _values[f.key] ?? '';
        case FieldKind.toggle:
          body[f.key] = (_values[f.key] == true) ? 1 : 0;
        default:
          final t = _controllers[f.key]!.text.trim();
          if (t.isNotEmpty) body[f.key] = t;
      }
      if (f.required && (body[f.key] == null || '${body[f.key]}'.isEmpty)) {
        setState(() => _error = '${f.label} is needed');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<Session>().api;
    try {
      if (_editing) {
        await api.put('/api/${widget.spec.key}/${widget.existing!['id']}', body);
      } else {
        await api.post('/api/${widget.spec.key}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this?'),
        content: const Text('It is removed from your computer as well.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context
          .read<Session>()
          .api
          .delete('/api/${widget.spec.key}/${widget.existing!['id']}');
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            // The same solid tile the rows and the empty state use. A 14% wash
            // was the odd one out, and the sheet is the screen you look at
            // longest.
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: s.colour,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: s.colour.withValues(alpha: 0.34),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(s.icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_editing ? 'Edit' : 'Add to ${s.label}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            if (_editing)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: kDanger),
                onPressed: _delete,
              ),
          ]),
          const SizedBox(height: 14),
          for (final f in s.fields) ...[
            _field(f),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            const SizedBox(height: 10),
          ],
          BrandButton(
            label: _editing ? 'Save changes' : 'Add it',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ]),
      ),
    );
  }

  /// "18:30" -> "6:30 pm", matching how the server words it in a notification.
  String _readTime(String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0;
    final m = int.tryParse(p.length > 1 ? p[1] : '') ?? 0;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
  }

  Widget _field(ModuleField f) {
    switch (f.kind) {
      case FieldKind.choice:
        return DropdownButtonFormField<String>(
          initialValue: _values[f.key] as String?,
          decoration: InputDecoration(labelText: f.label, helperText: f.hint),
          items: [
            // The VALUE stays exactly what the column accepts; only the label is
            // tidied. Showing 'half_yearly' raw was the giveaway that these were
            // database strings leaking onto the screen.
            for (final c in f.choices)
              DropdownMenuItem(value: c, child: Text(prettyChoice(c)))
          ],
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldKind.master:
        return MasterPicker(
          type: f.masterType!,
          label: f.label,
          value: _values[f.key] as String?,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldKind.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          subtitle: f.hint == null ? null : Text(f.hint!),
          value: _values[f.key] == true,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldKind.time:
        final tv = _values[f.key] as String?;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: BorderSide(color: Theme.of(context).dividerColor)),
          title: Text(f.label, style: const TextStyle(fontSize: 14)),
          subtitle: Text(tv == null ? (f.hint ?? 'Not set') : _readTime(tv)),
          // A set time can be taken back off. Without this the only way to undo
          // one is to delete the reminder and write it again — and an alarm you
          // cannot cancel is worse than one you never set.
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (tv != null)
              IconButton(
                tooltip: 'Clear the time',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _values[f.key] = null),
              ),
            const Icon(Icons.schedule, size: 18),
          ]),
          onTap: () async {
            final parts = (tv ?? '').split(':');
            final picked = await showTimePicker(
              context: context,
              initialTime: parts.length >= 2
                  ? TimeOfDay(
                      hour: int.tryParse(parts[0]) ?? 9,
                      minute: int.tryParse(parts[1]) ?? 0)
                  : const TimeOfDay(hour: 9, minute: 0),
            );
            if (picked != null) {
              // Sent as 24-hour "HH:MM" whatever the phone's clock is set to —
              // the server stores that form and the picker's own am/pm is only
              // how this device happens to show it.
              setState(() => _values[f.key] =
                  '${picked.hour.toString().padLeft(2, '0')}:'
                  '${picked.minute.toString().padLeft(2, '0')}');
            }
          },
        );
      case FieldKind.date:
        final v = _values[f.key] as String?;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: BorderSide(color: Theme.of(context).dividerColor)),
          title: Text(f.label, style: const TextStyle(fontSize: 14)),
          // Shown as dd-mm-yyyy; STORED as yyyy-MM-dd below. The field used to
          // print its own wire value, so a form asked people to read the date
          // in the database's spelling rather than their own.
          subtitle: Text(
              (v ?? '').isEmpty ? 'Not set' : (fmtDate(parseDate(v)) ) ),
          trailing: const Icon(Icons.calendar_today, size: 18),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(v ?? '') ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              // wireDate, not the display format. Sending dd-mm-yyyy here is
              // how a date reaches the database meaning a different day.
              setState(() => _values[f.key] = wireDate(picked));
            }
          },
        );
      default:
        return TextField(
          controller: _controllers[f.key],
          keyboardType: f.kind == FieldKind.money || f.kind == FieldKind.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          maxLines: f.kind == FieldKind.note ? 3 : 1,
          decoration: InputDecoration(
            labelText: f.label,
            helperText: f.hint,
            prefixText: f.kind == FieldKind.money ? '₹ ' : null,
          ),
        );
    }
  }
}

/// `.mod-empty` — the module's own icon on its OWN colour, its purpose, and the
/// button that fixes it.
///
/// A grey outline glyph and two lines of text was what was here. The web app
/// gives this a 66px tile in the module's accent with a big soft shadow, because
/// the empty state is the FIRST thing a new customer sees in every module — it
/// is not an error condition, it is the invitation.
class _Empty extends StatelessWidget {
  const _Empty({required this.spec, required this.filtered, this.onAdd});
  final ModuleSpec spec;
  final bool filtered;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 34, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: spec.colour,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: spec.colour.withValues(alpha: 0.38),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(spec.icon, size: 30, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
                filtered
                    ? 'Nothing matches'
                    : 'No ${spec.label.toLowerCase()} yet',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(filtered ? 'Try a different search' : spec.blurb,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            if (!filtered && onAdd != null) ...[
              const SizedBox(height: 20),
              // min-width, NOT width. `.mod-empty-btn { min-width: 190px }` is
              // a floor the label may exceed; pinning it to 190 clipped
              // "Add your first" by 57 pixels on a small phone.
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 190),
                child: BrandButton(label: 'Add your first', onPressed: onAdd),
              ),
            ],
          ]),
        )
      ]);
}

/// NOT the empty state, and that distinction is the whole point.
///
/// Telling somebody "no loans yet" because their laptop is asleep reads as
/// "your records are gone" — alarming and untrue, in the one app where a person
/// keeps everything. The web app splits these two for exactly that reason and
/// says so in as many words; the phone showed one bare line of error text.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline =
        RegExp(r'offline|reach|connection|refused|timed out', caseSensitive: false)
            .hasMatch(message);
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 34, 22, 20),
        child: Column(children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: kWarn.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
                child: Text(offline ? '📡' : '⚠️',
                    style: const TextStyle(fontSize: 30))),
          ),
          const SizedBox(height: 16),
          Text(offline ? 'Can’t load right now' : 'Something went wrong',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.38)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
                'Your records are safe on your computer — they just cannot be '
                'fetched at the moment.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.outline)),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 190),
              child: BrandButton(label: 'Try again', onPressed: onRetry)),
        ]),
      )
    ]);
  }
}

