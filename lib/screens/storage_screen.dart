/// How much room your records take, and where they are kept.
///
/// Left out of the phone at first, on the rule that things which CONFIGURE the
/// machine are done at the machine. That rule still holds — you cannot move the
/// records folder from here, and should not be able to. But it was applied to
/// the wrong half: reading how much space photos take, and being told which
/// drive they live on, configures nothing. It is exactly what someone wants to
/// know from a phone, usually right before backing up a few hundred more.
///
/// So this screen answers and never changes. Moving the folder stays on the
/// computer, where the app can stop, copy and verify without a phone losing its
/// connection halfway through.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';

String formatBytes(num b) {
  if (b <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  // No decimal on bytes and kilobytes — "1.4 KB" reads as false precision for
  // something that changes every time a thumbnail is written.
  return i <= 1 ? '${v.round()} ${units[i]}' : '${v.toStringAsFixed(1)} ${units[i]}';
}

const _moduleLabels = <String, String>{
  'gallery': 'Photos',
  'documents': 'Documents',
  'avatars': 'Profile pictures',
};

const _moduleIcons = <String, IconData>{
  'gallery': Icons.photo_library_outlined,
  'documents': Icons.description_outlined,
  'avatars': Icons.account_circle_outlined,
};

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key, this.appName = 'the app'});

  /// The brand name, passed in rather than hard-coded. A renamed copy that
  /// still says "SafeNest" in one sentence is exactly the half-rebranding the
  /// branding system exists to prevent.
  final String appName;
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, dynamic>? _storage;
  Map<String, dynamic>? _location;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = _storage == null);
    final api = context.read<Session>().api;
    try {
      // Both at once, and the location is allowed to fail on its own: an
      // installation run from its own folder answers it with an explanation
      // rather than a path, and an older server may not have the endpoint at
      // all. Neither is a reason to show nothing.
      final r = await Future.wait([
        api.get('/api/system/storage'),
        api.get('/api/system/records-location').catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _storage = (r[0] as Map).cast<String, dynamic>();
        _location = (r[1] as Map?)?.cast<String, dynamic>();
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ]),
          ),
        ),
      ]);
    }

    final mine = (_storage?['mine'] as Map?)?.cast<String, dynamic>() ?? {};
    final modules = (mine['modules'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (mine['bytes'] ?? 0) as int;
    final totalFiles = (mine['files'] ?? 0) as int;

    // Largest first. A list in whatever order the server happened to build it
    // buries the one thing worth acting on.
    final entries = modules.entries.toList()
      ..sort((a, b) => (((b.value as Map)['bytes'] ?? 0) as int)
          .compareTo(((a.value as Map)['bytes'] ?? 0) as int));

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _totalCard(total, totalFiles),
        // Sits with storage rather than under settings: "is everything still
        // there?" is the same question as "what is on the disk", and it is
        // where somebody already is when a tile looks broken.
        ReconcileCard(api: context.read<Session>().api),
        _sectionTitle('What is using it'),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
            child: Text('Nothing stored yet.'),
          )
        else
          ...entries.map((e) {
            final m = (e.value as Map).cast<String, dynamic>();
            final bytes = (m['bytes'] ?? 0) as int;
            final files = (m['files'] ?? 0) as int;
            return _moduleRow(e.key, bytes, files, total);
          }),
        _locationSection(),
      ],
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
        child: Text(s,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _totalCard(int total, int files) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kRadius),
          gradient: const LinearGradient(
            colors: [kBrand, kBrand2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your records',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(formatBytes(total),
              style: const TextStyle(
                  color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('$files file${files == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          // The reassuring number, when the server offers it. Percentages below
          // are shares of THIS total, not of the drive, and without the free
          // space somewhere on screen a "100%" invites exactly the wrong
          // conclusion.
          if ((((_location?['free_bytes']) ?? 0) as int) > 0) ...[
            const SizedBox(height: 8),
            Text(
                '${formatBytes((_location!['free_bytes']) as int)} still free '
                'where these are kept',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ]),
      ),
    );
  }

  /// How many kinds of thing actually have anything in them.
  ///
  /// A share is only worth showing when there is something to share WITH. With
  /// photos as the only stored thing the bar sat at 100%, which is true and
  /// reads as "your disk is full" — the one meaning it does not have. It is a
  /// share of your own records, not of the drive.
  int get _kindsWithData {
    final mods = ((_storage?['mine'] as Map?)?['modules'] as Map?) ?? {};
    return mods.values
        .where((m) => (((m as Map)['bytes'] ?? 0) as int) > 0)
        .length;
  }

  Widget _moduleRow(String key, int bytes, int files, int total) {
    final label = _moduleLabels[key] ??
        (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1));
    final icon = _moduleIcons[key] ?? Icons.folder_outlined;
    final share = total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0.0;
    final tint = kModuleColours[key] ?? kBrand;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            height: 30,
            width: 30,
            decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(kRadiusSm)),
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(width: 10),
          // Expanded, or a long label plus a size pushes the row over on a
          // narrow phone — an overflow no analyzer would have caught.
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Text(formatBytes(bytes),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
        ]),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 6,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(tint),
          ),
        ),
        const SizedBox(height: 4),
        Text(
            // "45% of your records" — never a bare percentage. And when this is
            // the only thing stored, say so in words: "100%" of a single
            // category is arithmetic, not information, and it frightens people
            // into thinking their drive is full.
            _kindsWithData <= 1
                ? '$files file${files == 1 ? '' : 's'} · all of your records'
                : '$files file${files == 1 ? '' : 's'} · '
                    '${(share * 100).round()}% of your records',
            style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }

  Widget _locationSection() {
    final loc = _location;
    if (loc == null || loc.isEmpty) return const SizedBox.shrink();
    final path = '${loc['path'] ?? ''}'.trim();
    final reason = '${loc['reason'] ?? ''}'.trim();
    final size = (loc['size_bytes'] ?? 0) as int;
    final free = (loc['free_bytes'] ?? 0) as int;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Where they are kept'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: softShadow(Theme.of(context).brightness == Brightness.dark),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (path.isNotEmpty)
              SelectableText(
                path,
                // Selectable, because the one reason to look at a path on a
                // phone is to say it to somebody or type it somewhere else.
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
              )
            else
              Text(reason.isEmpty ? 'Kept with the app.' : reason,
                  style: Theme.of(context).textTheme.bodyMedium),
            if (size > 0 || free > 0) ...[
              const SizedBox(height: 10),
              Row(children: [
                if (size > 0)
                  Expanded(child: _stat('Folder', formatBytes(size))),
                if (free > 0)
                  Expanded(child: _stat('Free on that drive', formatBytes(free))),
              ]),
            ],
            const SizedBox(height: 10),
            Text(
              // Says plainly that this screen only reads. Someone who finds the
              // path here and expects to change it should learn where that is
              // done before hunting for a button that is deliberately absent.
              'Moving your records to another drive is done on the computer '
              'running ${widget.appName}, where it can be copied and checked '
              'without a phone losing its connection part-way through.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ],
      );
}


/// Does the computer's database still agree with its disk?
///
/// WHY ANYBODY WOULD WANT THIS. A photo can vanish from the disk — a failed
/// copy, a drive swapped out, a tidy-up by somebody who did not know — while
/// its row, its thumbnail, its face embeddings and its search text all carry
/// on as though nothing happened. The gallery then shows a broken tile and
/// nobody is told. Every part of the app that could have noticed is written
/// to look away, because a missing file must never take a screen down.
///
/// So the check has to be asked for. It is READ-ONLY: it reports, and it
/// repairs nothing. The repair that exists on the computer only clears
/// derived rows — embeddings and faces for photos that are gone — and never
/// deletes a photograph.
class ReconcileCard extends StatefulWidget {
  const ReconcileCard({super.key, required this.api});

  final Api api;

  @override
  State<ReconcileCard> createState() => _ReconcileCardState();
}

class _ReconcileCardState extends State<ReconcileCard> {
  Map<String, dynamic>? _result;
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.api.get('/api/system/reconcile');
      if (!mounted) return;
      setState(() {
        _result = (r as Map).cast<String, dynamic>();
        _busy = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.status == 404
            ? 'Your computer needs its SafeNest updated for this.'
            : e.message;
        _busy = false;
      });
    }
  }

  int _n(Map<String, dynamic>? m, String key) =>
      ((m?[key]) as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final gallery = (_result?['gallery'] as Map?)?.cast<String, dynamic>();
    final docs = (_result?['documents'] as Map?)?.cast<String, dynamic>();
    final missing = _n(gallery, 'missing_file') + _n(docs, 'missing_file');
    final strays = _n(gallery, 'stray_file') + _n(docs, 'stray_file');

    return Card(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Check the files are all there',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: _busy ? null : _run,
                  child: Text(_busy
                      ? 'Checking…'
                      : (_result == null ? 'Check' : 'Again')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Compares your computer\'s records against the files on its '
              'disk. It only looks — nothing is changed or deleted.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(fontSize: 12.5)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              // The good answer is stated as plainly as the bad one. "0
              // problems" read out of a table of numbers is not reassurance.
              if (missing == 0 && strays == 0)
                const Row(children: [
                  Icon(Icons.check_circle_outline, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('Everything matches.',
                          style: TextStyle(fontSize: 13))),
                ])
              else ...[
                if (missing > 0)
                  _line(context, Icons.error_outline,
                      '$missing ${missing == 1 ? 'item is' : 'items are'} '
                      'recorded but the file is missing from the disk.'),
                if (strays > 0)
                  _line(context, Icons.help_outline,
                      '$strays ${strays == 1 ? 'file' : 'files'} on the disk '
                      'that nothing points at.'),
                const SizedBox(height: 6),
                const Text(
                  'Missing files usually mean a copy that did not finish, or '
                  'a drive that changed. Your photographs are not deleted by '
                  'this check.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static Widget _line(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
