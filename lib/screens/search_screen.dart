/// Search everything at once — the one thing this app had no way of doing.
///
/// `/api/search` has existed since the beginning, answers across every module,
/// and the phone NEVER CALLED IT. The only search here was inside the gallery,
/// so looking for "HDFC" found photographs and could not find the card, the
/// loan, the insurance policy or the document with it written on.
///
/// The response is already grouped by the server:
///
///   {query, total, groups: [{kind, label, count, items:[{id,title,sub,...}]}]}
///
/// so this screen does not decide what a result is or which module it belongs
/// to — it renders what it is told, in the server's own order. Anything the
/// server learns to search later appears here without a change.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../modules.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import '../widgets/pill.dart';
import 'library_tabs.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.onOpen, this.initialResults});

  /// Opens a module by key, so a result can be followed.
  final void Function(String key) onOpen;

  /// For tests — render results without a server.
  final Map<String, dynamic>? initialResults;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  Map<String, dynamic>? _results;

  /// Faces whose name matches. `/api/people?q=` has always supported this and
  /// nothing used it — and `/api/search` covers no people at all, so searching
  /// somebody's name found photographs that merely mentioned it and not the
  /// person. Google Photos puts matching faces at the TOP of a search, because
  /// a name is far more often a person than a word.
  List<Map<String, dynamic>> _people = const [];

  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialResults != null) {
      _results = widget.initialResults;
      _query = '${_results!['query'] ?? ''}';
      return;
    }
    // Straight to the keyboard. Somebody who opened search is going to type.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String v) {
    _debounce?.cancel();
    // A request per keystroke would search five times for "HDFC". The same
    // 350ms the gallery uses, so the two feel like one app.
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(v.trim()));
  }

  Future<void> _run(String q) async {
    if (q == _query) return;
    setState(() {
      _query = q;
      _error = null;
    });
    if (q.isEmpty) {
      setState(() {
        _results = null;
        _people = const [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final api = context.read<Session>().api;
      // Both at once. People is a small query and waiting for it serially would
      // add a round trip to every keystroke that survives the debounce.
      final both = await Future.wait([
        api.get('/api/search', {'q': q}),
        api.get('/api/people', {'q': q, 'limit': '12'})
            .catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final ppl = both[1];
      setState(() {
        _results = both[0] is Map ? Map<String, dynamic>.from(both[0] as Map) : null;
        _people = ppl is Map
            ? [
                for (final p in (ppl['people'] as List? ?? const []))
                  Map<String, dynamic>.from(p as Map)
              ]
            : const [];
        _loading = false;
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

  /// The module a group belongs to, so a result carries its module's colour.
  ///
  /// `kind` is the server's word — "photos", "expenses", "cards" and so on.
  /// Anything unrecognised still renders, in the brand colour, rather than
  /// being dropped: a group this app has not heard of is new, not wrong.
  ({Color colour, IconData icon, String? module}) _lookOf(String kind) {
    final k = kind.toLowerCase();
    if (k.startsWith('photo')) {
      return (
        colour: kModuleColours['gallery']!,
        icon: Icons.photo_outlined,
        module: 'gallery'
      );
    }
    if (k.startsWith('doc')) {
      return (
        colour: kModuleColours['documents']!,
        icon: Icons.description_outlined,
        module: 'documents'
      );
    }
    if (k.startsWith('vault') || k.startsWith('password')) {
      return (
        colour: kModuleColours['vault']!,
        icon: Icons.lock_outline,
        module: 'vault'
      );
    }
    for (final m in kModules) {
      if (k.startsWith(m.key.substring(0, m.key.length - 1))) {
        return (colour: m.colour, icon: m.icon, module: m.key);
      }
    }
    return (colour: kBrand, icon: Icons.search, module: null);
  }

  /// Matching faces, as circles — the same shape as the People tab, because a
  /// face is a person in both places and two shapes for one thing is how an app
  /// stops feeling like one app.
  Widget _peopleRow() {
    final base = context.read<Session>().baseUrl ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: kBrand, borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.person_outline, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Text('People',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Pill('${_people.length}', colour: kBrand),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _people.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (ctx, i) {
              final p = _people[i];
              final cover = '${p['cover_url'] ?? ''}';
              final n = '${p['name'] ?? 'Someone'}';
              return GestureDetector(
                onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => CollectionScreen(
                    title: n,
                    path: '/api/people/${p['id']}/photos',
                  ),
                )),
                child: SizedBox(
                  width: 66,
                  child: Column(children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: cover.isEmpty
                          ? Icon(Icons.person,
                              color: Theme.of(ctx).colorScheme.outline)
                          : Image.network(
                              cover.startsWith('http') ? cover : '$base$cover',
                              fit: BoxFit.cover,
                              cacheWidth: 180,
                              errorBuilder: (_, _, _) => Icon(Icons.person,
                                  color: Theme.of(ctx).colorScheme.outline)),
                    ),
                    const SizedBox(height: 5),
                    Text(n,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final res = _results;
    final groups = (res?['groups'] as List?) ?? const [];
    final total = (res?['total'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _field,
          focusNode: _focus,
          onChanged: _typed,
          onSubmitted: (v) => _run(v.trim()),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search everything',
            border: InputBorder.none,
            isDense: true,
            suffixIcon: _field.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      _field.clear();
                      _run('');
                    },
                  ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Message(
                  icon: '📡',
                  title: 'Can’t search right now',
                  note: _error!,
                  onRetry: () => _run(_query))
              : res == null
                  ? const _Prompt()
                  : (groups.isEmpty && _people.isEmpty)
                      ? _Message(
                          icon: '🔍',
                          title: 'Nothing found',
                          note: 'No records, photos or people match “$_query”. '
                              'Try a shorter word.')
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                          children: [
                            // FACES FIRST. A name is far more often a person
                            // than a word, so somebody typing "Meera" wants her
                            // photos before they want a document mentioning her.
                            if (_people.isNotEmpty) _peopleRow(),
                            if (groups.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                              child: Text(
                                  '$total ${total == 1 ? "result" : "results"} '
                                  'across ${groups.length} '
                                  '${groups.length == 1 ? "place" : "places"}',
                                  style: theme.textTheme.bodySmall),
                            ),
                            for (final raw in groups)
                              _GroupBlock(
                                group: Map<String, dynamic>.from(raw as Map),
                                look: _lookOf('${(raw)['kind'] ?? ''}'),
                                onOpenModule: widget.onOpen,
                              ),
                          ],
                        ),
    );
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock(
      {required this.group, required this.look, required this.onOpenModule});
  final Map<String, dynamic> group;
  final ({Color colour, IconData icon, String? module}) look;
  final void Function(String key) onOpenModule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = (group['items'] as List?) ?? const [];
    final count = (group['count'] as num?)?.toInt() ?? items.length;
    final label = '${group['label'] ?? group['kind'] ?? 'Results'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: look.colour,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(look.icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Pill('$count', colour: look.colour),
          const Spacer(),
          // Only offered when the module is one this app can open. A group the
          // server invented later still renders, it just has nowhere to go yet.
          if (look.module != null)
            TextButton(
              onPressed: () => onOpenModule(look.module!),
              child: const Text('Open'),
            ),
        ]),
        const SizedBox(height: 8),
        for (final raw in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BrandCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              onTap: look.module == null ? null : () => onOpenModule(look.module!),
              child: Row(children: [
                _Thumb(item: Map<String, dynamic>.from(raw as Map), look: look),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${(raw)['title'] ?? 'Untitled'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w700)),
                        if ('${(raw)['sub'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('${(raw)['sub']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall),
                        ],
                      ]),
                ),
              ]),
            ),
          ),
        if (count > items.length)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text('and ${count - items.length} more',
                style: theme.textTheme.bodySmall),
          ),
      ]),
    );
  }
}

/// A photo result shows the photo; everything else shows its module's mark.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.look});
  final Map<String, dynamic> item;
  final ({Color colour, IconData icon, String? module}) look;

  @override
  Widget build(BuildContext context) {
    final base = context.read<Session>().baseUrl ?? '';
    final t = '${item['thumb_url'] ?? ''}';
    if (t.isEmpty) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: look.colour.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(look.icon, size: 20, color: look.colour),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        t.startsWith('http') ? t : '$base$t',
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        cacheWidth: 120,
        errorBuilder: (_, _, _) => Container(
          width: 42,
          height: 42,
          color: look.colour.withValues(alpha: 0.15),
          child: Icon(look.icon, size: 20, color: look.colour),
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt();

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 48, 22, 20),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kBrand, kBrand2],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: brandGlow(),
              ),
              child: const Icon(Icons.search, size: 30, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('Search everything',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                  'One box for all of it — expenses, cards, loans, policies, '
                  'documents, photos and passwords. The text read off your '
                  'scanned paperwork is searched too.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ]),
        )
      ]);
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon,
      required this.title,
      required this.note,
      this.onRetry});
  final String icon;
  final String title;
  final String note;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 48, 22, 20),
          child: Column(children: [
            Text(icon, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.38)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(note,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            if (onRetry != null) ...[
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
