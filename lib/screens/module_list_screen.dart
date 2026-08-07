/// One list and one form, for all seven record modules.
///
/// Driven entirely by ModuleSpec, because the server treats them identically:
/// `GET /api/<key>` lists, `POST` creates, `DELETE /api/<key>/<id>` removes. Seven
/// hand-written screens would be seven places to fix a bug and six to forget.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../modules.dart';
import '../session.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<Session>().api.get('/api/${widget.spec.key}');
      // Some modules answer with a bare list, others wrap it in {items: []}.
      final list = d is List
          ? d
          : (d is Map ? (d['items'] ?? d['rows'] ?? const []) : const []);
      setState(() {
        _rows = [for (final e in (list as List)) Map<String, dynamic>.from(e as Map)];
        _loading = false;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ModuleFormScreen(spec: widget.spec)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
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
    // The dialog was awaited, so this screen may have been disposed in the
    // meantime — reading context after that is a crash, not a style point.
    if (ok != true || !mounted) return;
    try {
      await context.read<Session>().api.delete('/api/${widget.spec.key}/${row['id']}');
      _load();
    } on ApiError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse('${v ?? ''}');
    if (n == null) return '';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    return Scaffold(
      appBar: AppBar(title: Text(s.label), automaticallyImplyLeading: !widget.embedded),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                            onPressed: _load, child: const Text('Try again')),
                      ]),
                    )
                  ])
                : _rows.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(children: [
                            Icon(s.icon, size: 44, color: s.colour),
                            const SizedBox(height: 14),
                            Text('Nothing here yet',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(s.blurb,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                        )
                      ])
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, i) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final r = _rows[i];
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
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: s.colour.withValues(alpha: 0.14),
                              child: Icon(s.icon, size: 20, color: s.colour),
                            ),
                            title: Text('${r[s.titleField] ?? '—'}'),
                            subtitle: sub.isEmpty ? null : Text(sub),
                            trailing: amount.isEmpty
                                ? null
                                : Text(amount,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                            onLongPress: () => _delete(r),
                          );
                        },
                      ),
      ),
    );
  }
}

/// Adding one, built from the same spec.
class ModuleFormScreen extends StatefulWidget {
  const ModuleFormScreen({super.key, required this.spec});
  final ModuleSpec spec;

  @override
  State<ModuleFormScreen> createState() => _ModuleFormScreenState();
}

class _ModuleFormScreenState extends State<ModuleFormScreen> {
  final _values = <String, dynamic>{};
  final _controllers = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in widget.spec.fields) {
      if (f.kind == FieldKind.choice && f.choices.isNotEmpty) {
        _values[f.key] = f.choices.first;
      } else if (f.kind == FieldKind.toggle) {
        _values[f.key] = false;
      } else if (f.kind == FieldKind.date && f.required) {
        _values[f.key] = DateFormat('yyyy-MM-dd').format(DateTime.now());
      }
      _controllers[f.key] = TextEditingController();
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
      if (f.required &&
          (body[f.key] == null || '${body[f.key]}'.isEmpty)) {
        setState(() => _error = '${f.label} is needed');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().api.post('/api/${widget.spec.key}', body);
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    return Scaffold(
      appBar: AppBar(title: Text('Add to ${s.label}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final f in s.fields) ...[
            _field(f),
            const SizedBox(height: 14),
          ],
          if (_error != null) ...[
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
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
            for (final c in f.choices)
              DropdownMenuItem(value: c, child: Text(c))
          ],
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldKind.toggle:
        return SwitchListTile(
          title: Text(f.label),
          value: _values[f.key] == true,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldKind.date:
        final v = _values[f.key] as String?;
        return ListTile(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).dividerColor)),
          title: Text(f.label),
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
              setState(() => _values[f.key] =
                  DateFormat('yyyy-MM-dd').format(picked));
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
