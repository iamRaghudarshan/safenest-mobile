/// Manage lists — the user's own categories and banks.
///
/// The web app has had this at Profile → Customization → "Manage lists" since
/// the beginning and the phone had nothing: the lists existed, were seeded per
/// user, and were unreachable from here. So a category could be picked on the
/// laptop and neither renamed nor added to from the phone.
///
/// Four types, from `masters.py::MASTER_TYPES`. Each carries ONE extra — an
/// emoji for categories, a brand colour for banks — and which one is decided by
/// the server, not here. Offering both would let somebody set a value the API
/// drops on the floor.
///
/// HIDDEN, NOT DELETED, is the default action. These are lookup values that
/// existing records already point at by label; removing "Groceries" does not
/// un-file the forty expenses that say Groceries, it just stops it being
/// offered. Delete is still there, one level down, for a list someone genuinely
/// wants shorter.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../masters.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/pill.dart';
import '../widgets/skeleton.dart';

class MastersScreen extends StatelessWidget {
  const MastersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Manage lists')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
            child: Text(
                'The categories and banks the forms offer you. Rename them, add '
                'your own, or hide the ones you never use.',
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
          for (final t in kMasterTypes) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BrandCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MasterListScreen(type: t))),
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: kModuleColours['expenses'],
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: kModuleColours['expenses']!
                              .withValues(alpha: 0.32),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(t.icon, size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.label,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(t.blurb, style: theme.textTheme.bodySmall),
                        ]),
                  ),
                  Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MasterListScreen extends StatefulWidget {
  const MasterListScreen({super.key, required this.type, this.initialItems});
  final MasterType type;

  /// For tests — lay the screen out without a server.
  final List<MasterItem>? initialItems;

  @override
  State<MasterListScreen> createState() => _MasterListScreenState();
}

class _MasterListScreenState extends State<MasterListScreen> {
  List<MasterItem> _items = [];
  bool _loading = true;
  String? _error;

  bool get _usesEmoji => widget.type.field == 'emoji';

  @override
  void initState() {
    super.initState();
    if (widget.initialItems != null) {
      _items = widget.initialItems!;
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // activeOnly: false — this is the screen where hidden entries have to be
      // visible, or there would be no way to bring one back.
      final list = await context
          .read<Session>()
          .masters
          .load(widget.type.type, activeOnly: false);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  /// Every write goes through here so the cache is dropped exactly once, in one
  /// place. A form opened afterwards re-reads the list rather than offering the
  /// categories as they were before the edit.
  Future<bool> _write(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final session = context.read<Session>();
    try {
      await action();
      session.masters.forget(widget.type.type);
      await _load();
      return true;
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
  }

  Future<void> _toggleActive(MasterItem m) => _write(() async {
        await context.read<Session>().api.put(
            '/api/masters/${m.id}', {'is_active': m.isActive ? 0 : 1});
      });

  Future<void> _delete(MasterItem m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${m.label}”?'),
        content: const Text(
            'Records already filed under it keep the name — it just stops '
            'being offered. Hiding it does the same and can be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _write(() async {
      await context.read<Session>().api.delete('/api/masters/${m.id}');
    });
  }

  Future<void> _edit([MasterItem? existing]) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MasterSheet(type: widget.type, existing: existing),
    );
    if (result == null || !mounted) return;

    await _write(() async {
      final api = context.read<Session>().api;
      if (existing == null) {
        await api.post('/api/masters', {'type': widget.type.type, ...result});
      } else {
        await api.put('/api/masters/${existing.id}', result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.type.label)),
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
          child: Semantics(
            button: true,
            label: 'Add to ${widget.type.label}',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _edit(),
              child: const Icon(Icons.add, size: 30, color: Colors.white),
            ),
          ),
        ),
      ),
      body: _loading
          ? const SkeletonList()
          : _error != null
              ? _Problem(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final m = _items[i];
                      final tint = m.tint ?? kModuleColours['expenses']!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Opacity(
                          // A hidden entry stays legible — it is a state, not a
                          // deletion, and it has to be findable to be undone.
                          opacity: m.isActive ? 1 : 0.55,
                          child: BrandCard(
                            onTap: () => _edit(m),
                            padding:
                                const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _usesEmoji
                                      ? tint.withValues(alpha: 0.14)
                                      : tint,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Center(
                                  child: _usesEmoji
                                      ? Text(m.emoji ?? '🏷️',
                                          style:
                                              const TextStyle(fontSize: 20))
                                      : Text(
                                          m.label.isEmpty
                                              ? '?'
                                              : m.label
                                                  .characters.first
                                                  .toUpperCase(),
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(m.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                      if (!m.isActive) ...[
                                        const SizedBox(height: 6),
                                        const Pill('Hidden',
                                            tone: PillTone.muted,
                                            icon: Icons.visibility_off_outlined),
                                      ],
                                    ]),
                              ),
                              IconButton(
                                tooltip: m.isActive
                                    ? 'Hide from the forms'
                                    : 'Offer it again',
                                icon: Icon(
                                    m.isActive
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: theme.colorScheme.outline),
                                onPressed: () => _toggleActive(m),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline,
                                    color: kDanger),
                                onPressed: () => _delete(m),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// Add or rename one entry. The same sheet for both, as everywhere else here.
class _MasterSheet extends StatefulWidget {
  const _MasterSheet({required this.type, this.existing});
  final MasterType type;
  final MasterItem? existing;

  @override
  State<_MasterSheet> createState() => _MasterSheetState();
}

class _MasterSheetState extends State<_MasterSheet> {
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late String? _emoji = widget.existing?.emoji;
  late String? _colour = widget.existing?.color;
  String? _error;

  bool get _usesEmoji => widget.type.field == 'emoji';

  /// A small set rather than a full picker. An emoji keyboard exists on the
  /// phone, but it is three taps away and these are the glyphs the server
  /// already seeds — offering them is faster than typing one.
  static const _emojis = [
    '🍔', '🛒', '🚕', '🧾', '🛍️', '💊', '🎬', '✈️', '💸', '🏠', '🎁', '📚',
    '💼', '💰', '🏦', '🪪', '💳', '🛡️', '🚗', '🏥', '🎓', '📄', '✉️', '💬',
    '🔑', '🏷️',
  ];

  /// Bank brand colours, the nine the server seeds plus a few neutrals.
  static const _colours = [
    '#004c8f', '#af272f', '#22409a', '#97144d', '#ed1c24', '#a10f2b',
    '#0c4da2', '#9c1d26', '#64748b', '#10b981', '#f59e0b', '#8b5cf6',
  ];

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'label': label,
      if (_usesEmoji) 'emoji': _emoji ?? '',
      if (!_usesEmoji) 'color': _colour ?? '',
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(editing ? 'Rename' : 'Add to ${widget.type.label}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _label,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_usesEmoji ? 'Pick a symbol' : 'Pick a colour',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 10),
          if (_usesEmoji)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in _emojis)
                GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _emoji == e
                          ? kBrand.withValues(alpha: 0.16)
                          : Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _emoji == e
                              ? kBrand
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: 1.5),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 19)),
                  ),
                ),
            ])
          else
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in _colours)
                GestureDetector(
                  onTap: () => setState(() => _colour = c),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Color(
                          0xFF000000 | int.parse(c.substring(1), radix: 16)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _colour == c
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 2.5),
                    ),
                    child: _colour == c
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                ),
            ]),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
          const SizedBox(height: 18),
          BrandButton(
              label: editing ? 'Save changes' : 'Add it',
              block: true,
              onPressed: _save),
        ]),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 40, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: kWarn.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Center(
                  child: Text('📡', style: TextStyle(fontSize: 30))),
            ),
            const SizedBox(height: 16),
            const Text('Can’t load your lists',
                textAlign: TextAlign.center,
                style: TextStyle(
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
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 190),
              child: BrandButton(label: 'Try again', onPressed: onRetry),
            ),
          ]),
        )
      ]);
}
