/// Building the rule behind a saved search.
///
/// EVERY FIELD IS A CHOICE, never free text. A rule somebody types is a rule
/// they can spell wrong, and a saved search that quietly matches nothing
/// because of a typo is the worst version of this feature — it looks like the
/// feature is broken rather than like the word was wrong.
///
/// AN EMPTY RULE IS REFUSED. An album that matches everything is the gallery
/// under another name, and somebody who made one by accident would have to
/// work out why it will not stop growing.
library;

import 'package:flutter/material.dart';

import '../api.dart';

class SavedSearchSheet extends StatefulWidget {
  const SavedSearchSheet({super.key, required this.api, required this.labels});

  final Api api;

  /// {label, count} — only what this library actually contains.
  final List<Map<String, dynamic>> labels;

  @override
  State<SavedSearchSheet> createState() => _SavedSearchSheetState();
}

class _SavedSearchSheetState extends State<SavedSearchSheet> {
  final _name = TextEditingController();
  String _label = '';
  String _kind = '';
  bool _fav = false;
  int? _year;
  int? _month;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _rule => {
        if (_label.isNotEmpty) 'label': _label,
        if (_kind.isNotEmpty) 'kind': _kind,
        if (_fav) 'favourite': 1,
        if (_year != null) 'year': _year,
        if (_month != null) 'month': _month,
      };

  String? get _problem {
    if (_name.text.trim().isEmpty) return 'Give it a name';
    if (_rule.isEmpty) return 'Choose at least one thing to match';
    return null;
  }

  Future<void> _save() async {
    if (_problem != null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.post('/api/gallery/albums', {
        'name': _name.text.trim(),
        'rule': _rule,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // 409 is the useful one: the server refuses a duplicate name, and
      // saying so beats the save appearing not to happen.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = <int>[
      for (var y = DateTime.now().year; y >= DateTime.now().year - 12; y--) y
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Saved search',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'A question, not a list. Photos that match it later show up on '
              'their own — nothing has to be filed.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Beach days, Videos from 2024…',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.labels.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('What is in the photo',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final l in widget.labels.take(24))
                    ChoiceChip(
                      label: Text('${l['label']}  ${l['count']}'),
                      selected: _label == '${l['label']}',
                      onSelected: (_) => setState(() =>
                          _label = _label == '${l['label']}'
                              ? ''
                              : '${l['label']}'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text('Kind',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final (key, label) in const [
                  ('photo', 'Photos'),
                  ('video', 'Videos'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _kind == key,
                    onSelected: (_) =>
                        setState(() => _kind = _kind == key ? '' : key),
                  ),
                FilterChip(
                  label: const Text('★ Favourites'),
                  selected: _fav,
                  onSelected: (v) => setState(() => _fav = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('When',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<int?>(
                    value: _year,
                    isExpanded: true,
                    hint: const Text('Any year'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Any year')),
                      for (final y in years)
                        DropdownMenuItem<int?>(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => setState(() => _year = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<int?>(
                    value: _month,
                    isExpanded: true,
                    hint: const Text('Any month'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Any month')),
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem<int?>(
                            value: m, child: Text(months[m - 1])),
                    ],
                    onChanged: (v) => setState(() => _month = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_problem != null)
              Text(_problem!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_problem != null || _busy) ? null : _save,
                child: Text(_busy ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
