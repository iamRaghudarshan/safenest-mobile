/// A category or bank chosen from the user's own list, not typed.
///
/// The web app's expense form is a row of tappable chips with an emoji on each,
/// and Documents pulls its categories straight from `/api/masters`. The phone
/// had a text box, which is worse than it looks: it produces a DIFFERENT VALUE.
/// "food" typed here and "Food & Dining" chosen there are two categories to
/// every total in the app, and nobody who types the first one ever finds out.
///
/// Chips rather than a dropdown because that is what the web app uses and
/// because on a phone a dropdown hides the options behind a tap — for a list of
/// nine that a person picks from every single time they add anything, showing
/// them is the whole point.
///
/// TYPING IS STILL ALLOWED, deliberately. The record columns are free text, the
/// list is only a set of suggestions, and a category not on it is a normal
/// thing to want at the moment of writing a record down. "Something else" opens
/// a field; what it saves goes in the record exactly as typed. It does NOT
/// silently create a master — adding to the list is what the Masters screen is
/// for, and a typo should not become a permanent category.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../masters.dart';
import '../session.dart';
import '../theme.dart';

class MasterPicker extends StatefulWidget {
  const MasterPicker({
    super.key,
    required this.type,
    required this.label,
    required this.value,
    required this.onChanged,
    this.items,
  });

  final String type;
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Supplied directly by tests, so this can be laid out without a server.
  final List<MasterItem>? items;

  @override
  State<MasterPicker> createState() => _MasterPickerState();
}

class _MasterPickerState extends State<MasterPicker> {
  List<MasterItem>? _items;
  bool _failed = false;
  bool _custom = false;
  late final TextEditingController _own =
      TextEditingController(text: widget.value ?? '');

  @override
  void initState() {
    super.initState();
    if (widget.items != null) {
      _items = widget.items;
      _syncCustom();
      return;
    }
    _load();
  }

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<Session>().masters.load(widget.type);
      if (!mounted) return;
      setState(() => _items = list);
      _syncCustom();
    } catch (_) {
      // A list that will not load must not block the record. The field falls
      // back to what it always was — a text box — rather than leaving somebody
      // unable to save an expense because a lookup failed.
      if (mounted) setState(() => _failed = true);
    }
  }

  /// An existing record whose value is not on the list is being EDITED, not
  /// mis-typed. It opens in the custom field with its value intact; anything
  /// else would silently rewrite it to whichever chip happened to be first.
  void _syncCustom() {
    final v = widget.value;
    if (v == null || v.isEmpty) return;
    final known = (_items ?? const []).any((m) => m.label == v);
    if (!known) setState(() => _custom = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;

    if (_failed) {
      return TextField(
        controller: _own,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: 'Your saved list could not be loaded — type it instead',
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(widget.label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant)),
      ),
      if (items == null)
        // Placeholder chips, so the field does not jump in height the moment
        // the list arrives and move the button out from under a thumb.
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: 72 + (i * 11 % 34),
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ])
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in items) _chip(m, theme),
          _customChip(theme),
        ]),
      if (_custom) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _own,
          autofocus: items != null,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            labelText: 'Your own ${widget.label.toLowerCase()}',
            helperText: 'Saved on this record only. Add it to the list from '
                'Profile → Manage lists.',
            helperMaxLines: 2,
          ),
        ),
      ],
    ]);
  }

  Widget _chip(MasterItem m, ThemeData theme) {
    final on = !_custom && widget.value == m.label;
    // A bank carries its own brand colour; a category carries an emoji and
    // takes the brand purple when chosen. Selected is a FILL, not a border —
    // a 1.5px outline is not a state you can see at arm's length.
    final accent = m.tint ?? kBrand;

    return Material(
      color: on ? accent : theme.scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          setState(() => _custom = false);
          widget.onChanged(m.label);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on ? accent : theme.colorScheme.outlineVariant,
                width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (m.emoji != null) ...[
              Text(m.emoji!, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
            ] else if (m.tint != null && !on) ...[
              // No emoji on a bank, so the brand colour is the mark. A 10px dot
              // is enough to tell HDFC blue from ICICI red down a list.
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: m.tint, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ],
            Text(m.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : theme.colorScheme.onSurfaceVariant,
                )),
          ]),
        ),
      ),
    );
  }

  Widget _customChip(ThemeData theme) {
    final on = _custom;
    return Material(
      color: on ? kBrand : theme.scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          setState(() => _custom = true);
          widget.onChanged(_own.text.trim().isEmpty ? null : _own.text.trim());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on ? kBrand : theme.colorScheme.outlineVariant,
                width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.edit_outlined,
                size: 14,
                color: on ? Colors.white : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Something else',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : theme.colorScheme.onSurfaceVariant,
                )),
          ]),
        ),
      ),
    );
  }
}
