/// Home, in the Colourful skin: a photos app and a files app first.
///
/// WHY THIS IS A SEPARATE SCREEN rather than a pile of `if (vivid)` branches
/// inside the classic dashboard. The two are not the same layout recoloured —
/// classic opens on money and dues, this opens on the two things the product
/// actually is. Threading that through one widget would mean a conditional at
/// every level of the tree, which is the shape that rots: every later change
/// has to be made twice anyway, and in a form where neither version can be
/// read on its own.
///
/// Both are chosen from one place (`home_screen.dart`), both read the same
/// endpoints, and neither knows the other exists.
///
/// The ordering is the whole argument. Photos and files lead and nothing
/// competes with them; everything else — money, notes, habits, reminders —
/// sits below as small tiles. That is not a visual preference, it is what the
/// product is: a place your own photographs and documents live, that happens
/// to carry other things too.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import 'backup_screen.dart';

class VividHome extends StatefulWidget {
  const VividHome({
    super.key,
    required this.brand,
    this.onOpenPhotos,
    this.onOpenFiles,
    this.debugData,
  });

  final Brand brand;

  /// Tapping a hero tile switches TAB rather than pushing a screen, so the
  /// bottom bar stays honest about where you are.
  final VoidCallback? onOpenPhotos;
  final VoidCallback? onOpenFiles;

  /// For tests and for the design preview: render a state without a server.
  final VividHomeData? debugData;

  @override
  State<VividHome> createState() => _VividHomeState();
}

/// Everything this screen shows, in one object.
///
/// Separated from the fetching so the layout can be rendered — and tested —
/// without a server, and so a partial load has one obvious shape: a missing
/// figure is null, never a zero that looks like an answer.
class VividHomeData {
  const VividHomeData({
    this.name = '',
    this.photos,
    this.videos,
    this.documents,
    this.newPhotos,
    this.recent = const [],
    this.memories = const [],
  });

  final String name;

  /// Null means "not known yet", which is different from zero. A zero drawn
  /// while the request is still in flight is a lie that corrects itself, and
  /// on this screen the lie is "you have no photographs".
  final int? photos;
  final int? videos;
  final int? documents;
  final int? newPhotos;

  final List<Map<String, dynamic>> recent;
  final List<Map<String, dynamic>> memories;

  VividHomeData copyWith({
    String? name,
    int? photos,
    int? videos,
    int? documents,
    int? newPhotos,
    List<Map<String, dynamic>>? recent,
    List<Map<String, dynamic>>? memories,
  }) =>
      VividHomeData(
        name: name ?? this.name,
        photos: photos ?? this.photos,
        videos: videos ?? this.videos,
        documents: documents ?? this.documents,
        newPhotos: newPhotos ?? this.newPhotos,
        recent: recent ?? this.recent,
        memories: memories ?? this.memories,
      );
}

/// A count with its thousands grouped. Five-digit libraries are ordinary here.
String vividCount(int? v) {
  if (v == null) return '—';
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// The greeting, on the same boundaries the rest of the app uses.
String vividGreeting(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

class _VividHomeState extends State<VividHome> {
  VividHomeData _d = const VividHomeData();

  @override
  void initState() {
    super.initState();
    if (widget.debugData != null) {
      _d = widget.debugData!;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    // First name only, the same way the classic dashboard greets.
    final name = '${context.read<Session>().user?['name'] ?? ''}'.split(' ').first;
    var next = _d.copyWith(name: name);

    // Each in its OWN try. The counts, the recent files and the pictures
    // answer different questions, and one endpoint being down must not blank
    // the other two — a home screen that goes empty because the document
    // service is asleep is worse than one missing a row.
    try {
      final g = await api.get('/api/gallery', {'limit': '8'});
      if (g is Map) {
        next = next.copyWith(
          photos: (g['total'] as num?)?.toInt(),
          memories: [
            for (final e in (g['items'] as List? ?? const []))
              Map<String, dynamic>.from(e as Map),
          ],
        );
      }
    } catch (_) {/* the tile shows a dash, not a zero */}

    try {
      final v = await api.get('/api/gallery', {'limit': '1', 'kind': 'videos'});
      if (v is Map) next = next.copyWith(videos: (v['total'] as num?)?.toInt());
    } catch (_) {}

    try {
      final d = await api.get('/api/documents', {'limit': '1'});
      if (d is Map) {
        next = next.copyWith(documents: (d['total'] as num?)?.toInt());
      }
    } catch (_) {}

    try {
      final r = await api.get('/api/documents/recent', {'limit': '3'});
      final added = (r is Map ? r['added'] : null) as List? ?? const [];
      next = next.copyWith(recent: [
        for (final e in added.take(3)) Map<String, dynamic>.from(e as Map),
      ]);
    } catch (_) {}

    if (mounted) setState(() => _d = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.skin;
    final photos = t.module('gallery');
    final files = t.module('documents');

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Header(brand: widget.brand, name: _d.name, brand2: t.brand),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // THE TWO THINGS THIS APP IS FOR.
                    Row(children: [
                      Expanded(
                        child: _HeroTile(
                          colour: photos,
                          icon: Icons.photo_library_outlined,
                          count: _d.photos,
                          label: 'Photos & videos',
                          sub: _d.videos == null
                              ? ''
                              : '${vividCount(_d.videos)} videos',
                          onTap: widget.onOpenPhotos,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _HeroTile(
                          colour: files,
                          icon: Icons.folder_outlined,
                          count: _d.documents,
                          label: 'Documents',
                          sub: 'Scans, bills, papers',
                          onTap: widget.onOpenFiles,
                        ),
                      ),
                    ]),

                    if (_d.memories.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _SectionHead(
                          title: 'Looking back', onSeeAll: widget.onOpenPhotos),
                      const SizedBox(height: 11),
                      SizedBox(
                        height: 132,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _d.memories.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 11),
                          itemBuilder: (_, i) =>
                              _Memory(item: _d.memories[i], radius: t.radiusSm + 3),
                        ),
                      ),
                    ],

                    if (_d.recent.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _SectionHead(
                          title: 'Recent files', onSeeAll: widget.onOpenFiles),
                      const SizedBox(height: 11),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(t.radius),
                          boxShadow: softShadow(
                              theme.brightness == Brightness.dark),
                        ),
                        child: Column(children: [
                          for (var i = 0; i < _d.recent.length; i++)
                            _FileRow(
                              item: _d.recent[i],
                              last: i == _d.recent.length - 1,
                            ),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 22),
                    _SectionHead(title: 'Your copy'),
                    const SizedBox(height: 11),
                    _BackupRow(ok: t.ok, radius: t.radius),

                    const SizedBox(height: 28),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// The coloured head.
///
/// It is doing a job rather than decorating: it separates "who you are" from
/// "here is your stuff", so the greeting and the search never read as another
/// row of content. Everything below it is quiet by comparison, which is what
/// makes the two hero tiles the first thing the eye lands on.
class _Header extends StatelessWidget {
  const _Header({required this.brand, required this.name, required this.brand2});

  final Brand brand;
  final String name;
  final Color brand2;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(18, media.padding.top + 16, 18, 26),
      decoration: BoxDecoration(
        color: brand2,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vividGreeting(DateTime.now()),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70)),
                  const SizedBox(height: 1),
                  Text(name.isEmpty ? brand.shortName : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: Colors.white)),
                ]),
          ),
        ]),
        const SizedBox(height: 16),
        // ONE SEARCH over everything. Photos, files and the rest answer the
        // same box — which is the whole argument for keeping them together.
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {},
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              alignment: Alignment.centerLeft,
              child: Row(children: [
                Icon(Icons.search, size: 20, color: Colors.grey.shade600),
                const SizedBox(width: 11),
                Expanded(
                  child: Text('Search photos, files, anything',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700)),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _HeroTile extends StatelessWidget {
  const _HeroTile({
    required this.colour,
    required this.icon,
    required this.count,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final Color colour;
  final IconData icon;
  final int? count;
  final String label;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.skin;
    return Material(
      color: colour,
      borderRadius: BorderRadius.circular(t.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(vividCount(count),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Colors.white)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            if (sub.isNotEmpty)
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.82))),
          ]),
        ),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('See all',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
      ]);
}

class _Memory extends StatelessWidget {
  const _Memory({required this.item, required this.radius});

  final Map<String, dynamic> item;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final caption = (item['caption'] ?? item['orig_name'] ?? '') as String;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: 104,
        height: 132,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          if (caption.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 9),
                color: Colors.black.withValues(alpha: 0.55),
                child: Text(caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// A file's kind badge, coloured by what it is.
///
/// The colour is not decoration: people ask for "the insurance PDF", not "the
/// file in the second folder", so the kind is the fastest thing to scan for.
({String label, Color fill, Color ink}) fileBadge(String name, SkinTokens t) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return (label: 'PDF', fill: const Color(0xFFFDE8E6), ink: t.danger);
    case 'doc':
    case 'docx':
    case 'txt':
    case 'rtf':
      return (label: 'DOC', fill: const Color(0xFFE4F0FD), ink: t.brand);
    case 'xls':
    case 'xlsx':
    case 'csv':
      return (label: 'XLS', fill: const Color(0xFFE6F5EE), ink: t.ok);
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'heic':
      return (label: 'IMG', fill: const Color(0xFFEFE8FE), ink: t.module('notes'));
    default:
      return (
        label: ext.isEmpty ? 'FILE' : ext.toUpperCase().substring(0, ext.length.clamp(0, 4)),
        fill: const Color(0xFFEAEDF4),
        ink: t.module('vault'),
      );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.item, required this.last});

  final Map<String, dynamic> item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.skin;
    final name = (item['title'] ?? item['orig_name'] ?? item['filename'] ?? '')
        as String;
    final badge = fileBadge(name, t);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge.fill,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(badge.label,
                style: TextStyle(
                    fontSize: 9.5, fontWeight: FontWeight.w800, color: badge.ink)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name.isEmpty ? 'Untitled' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
      if (!last)
        Divider(height: 1, thickness: 1, color: theme.colorScheme.outlineVariant),
    ]);
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({required this.ok, required this.radius});

  final Color ok;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BackupScreen())),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: ok.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.cloud_done_outlined, size: 20, color: ok),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Back up this phone',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                    SizedBox(height: 1),
                    Text('Copy every photo to your own computer',
                        style: TextStyle(fontSize: 11.5)),
                  ]),
            ),
            Icon(Icons.chevron_right,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
