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

import '../api.dart';
import '../modules.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';

class ModuleListScreen extends StatefulWidget {
  const ModuleListScreen({super.key, required this.spec, this.embedded = false});
  final ModuleSpec spec;

  /// True when this IS a tab rather than a screen pushed on top of one — a tab
  /// with a back arrow is a tab that looks broken.
  final bool embedded;

  @override
  State<ModuleListScreen> createState() => _ModuleListScreenState();
}

class _ModuleListScreenState extends State<ModuleListScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  ApiError? _err;
  String _filter = '';

  /// Cards and loans can be marked paid; the others have no such idea.
  bool get _payable =>
      widget.spec.key == 'cards' || widget.spec.key == 'loans';

  @override
  void initState() {
    super.initState();
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
    } on ApiError catch (e) {
      setState(() {
        _err = e;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _shown {
    if (_filter.isEmpty) return _rows;
    final q = _filter.toLowerCase();
    return _rows.where((r) {
      // Searches every field rather than just the title: looking for "HDFC"
      // should find a card whose bank it is, even though the row is titled by
      // something else.
      return r.values.any((v) => '$v'.toLowerCase().contains(q));
    }).toList();
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

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final theme = Theme.of(context);
    final rows = _shown;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.label),
        automaticallyImplyLeading: !widget.embedded,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSheet(),
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        if (_rows.length > 5)
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
              ? const Center(child: CircularProgressIndicator())
              : _err != null
                  ? _Retry(message: _err!.message, onRetry: _load)
                  : rows.isEmpty
                      ? _Empty(spec: s, filtered: _filter.isNotEmpty)
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
                              ].join(' · ');
                              final paid = r['is_paid'] == 1 || r['paid'] == true;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: BrandCard(
                                  onTap: () => _openSheet(r),
                                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                                  child: Row(children: [
                                    // A colour bar rather than a circle: it
                                    // states the module without stealing the
                                    // width a real value needs.
                                    Container(
                                      width: 4,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: s.colour,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('${r[s.titleField] ?? '—'}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleSmall),
                                          if (sub.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(sub,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (amount.isNotEmpty)
                                      Text(amount,
                                          style: TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w700,
                                              color: s.colour)),
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
        case FieldKind.toggle:
          _values[f.key] = current == 1 || current == true;
        case FieldKind.date:
          _values[f.key] = current?.toString() ??
              (f.required ? DateFormat('yyyy-MM-dd').format(DateTime.now()) : null);
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
          if (_values[f.key] != null) body[f.key] = _values[f.key];
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
            CircleAvatar(
              backgroundColor: s.colour.withValues(alpha: 0.14),
              child: Icon(s.icon, size: 19, color: s.colour),
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

  Widget _field(ModuleField f) {
    switch (f.kind) {
      case FieldKind.choice:
        return DropdownButtonFormField<String>(
          initialValue: _values[f.key] as String?,
          decoration: InputDecoration(labelText: f.label),
          items: [
            for (final c in f.choices) DropdownMenuItem(value: c, child: Text(c))
          ],
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldKind.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _values[f.key] == true,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldKind.date:
        final v = _values[f.key] as String?;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: BorderSide(color: Theme.of(context).dividerColor)),
          title: Text(f.label, style: const TextStyle(fontSize: 14)),
          subtitle: Text(v ?? 'Not set'),
          trailing: const Icon(Icons.calendar_today, size: 18),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(v ?? '') ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() =>
                  _values[f.key] = DateFormat('yyyy-MM-dd').format(picked));
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
            prefixText: f.kind == FieldKind.money ? '₹ ' : null,
          ),
        );
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.spec, required this.filtered});
  final ModuleSpec spec;
  final bool filtered;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(children: [
            Icon(spec.icon, size: 44, color: spec.colour),
            const SizedBox(height: 14),
            Text(filtered ? 'Nothing matches' : 'Nothing here yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(filtered ? 'Try a different search' : spec.blurb,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        )
      ]);
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ]),
        )
      ]);
}
