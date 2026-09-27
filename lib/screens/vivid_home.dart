/// Home, in the Colourful skin: a photograph first.
///
/// WHAT THREE EARLIER VERSIONS GOT WRONG. The first led with money. The second
/// led with two counts. The third led with a progress ring. All three were
/// dashboards for a library rather than the library itself — and in a photos
/// app the pictures ARE the design. Every mockup that put a grey rectangle
/// where a photograph goes looked empty for exactly that reason.
///
/// So the page opens on a memory: a place, a date, and the faces of who is in
/// it. Then the people, then the albums, then documents, then everything else.
/// The counts are still here; they are just no longer the point.
///
/// A SEPARATE SCREEN from the classic dashboard, not the same one recoloured —
/// classic opens on money and dues. Both are chosen in one place
/// (`home_screen.dart`) and neither knows the other exists.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../widgets/memory_hero.dart';
import '../widgets/photo_tile.dart' show absoluteMedia;
import 'backup_screen.dart';

class VividHome extends StatefulWidget {
  const VividHome({
    super.key,
    required this.brand,
    this.onOpenPhotos,
    this.onOpenFiles,
    this.onOpen,
    this.debugData,
  });

  final Brand brand;
  final VoidCallback? onOpenPhotos;
  final VoidCallback? onOpenFiles;

  /// Opens any module by key, so the tiles reach Money, Notes and the rest
  /// through the one place that already knows how.
  final void Function(String key)? onOpen;

  /// For tests and for judging the design: render a state without a server.
  final VividHomeData? debugData;

  @override
  State<VividHome> createState() => _VividHomeState();
}

/// One memory, one album, one face — the same shape whichever it came from.
class VividCard {
  const VividCard({
    required this.title,
    this.sub = '',
    this.imageUrl,
    this.count = 0,
  });

  final String title;
  final String sub;
  final String? imageUrl;
  final int count;
}

class VividHomeData {
  const VividHomeData({
    this.name = '',
    this.photos,
    this.videos,
    this.documents,
    this.addedThisMonth,
    this.memory,
    this.memoryFaces = const [],
    this.people = const [],
    this.albums = const [],
    this.kinds = const {},
  });

  final String name;

  /// Null is "not known yet", which is not zero. A zero drawn mid-flight
  /// reads as "you have no photographs" and then corrects itself.
  final int? photos;
  final int? videos;
  final int? documents;
  final int? addedThisMonth;

  final VividCard? memory;
  final List<String> memoryFaces;
  final List<VividCard> people;
  final List<VividCard> albums;
  final Map<String, int> kinds;

  VividHomeData copyWith({
    String? name,
    int? photos,
    int? videos,
    int? documents,
    int? addedThisMonth,
    VividCard? memory,
    List<String>? memoryFaces,
    List<VividCard>? people,
    List<VividCard>? albums,
    Map<String, int>? kinds,
  }) =>
      VividHomeData(
        name: name ?? this.name,
        photos: photos ?? this.photos,
        videos: videos ?? this.videos,
        documents: documents ?? this.documents,
        addedThisMonth: addedThisMonth ?? this.addedThisMonth,
        memory: memory ?? this.memory,
        memoryFaces: memoryFaces ?? this.memoryFaces,
        people: people ?? this.people,
        albums: albums ?? this.albums,
        kinds: kinds ?? this.kinds,
      );
}

/// A count with its thousands grouped, or an em dash when it is not known.
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

String vividGreeting(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// "2 years ago", "8 months ago", "Last week". Null when there is no date.
///
/// Rounded the way somebody would say it rather than precisely: "1 year, 3
/// months ago" is an accurate answer to a question nobody asked.
String? vividWhen(DateTime? taken, DateTime now) {
  if (taken == null) return null;
  final days = now.difference(taken).inDays;
  if (days < 2) return null;              // today and yesterday say nothing
  if (days < 14) return 'Last week';
  if (days < 60) return '${(days / 7).round()} weeks ago';
  if (days < 365) return '${(days / 30).round()} months ago';
  final years = (days / 365).round();
  return years <= 1 ? 'A year ago' : '$years years ago';
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
    final session = context.read<Session>();
    final api = session.api;
    final base = session.baseUrl ?? '';
    String? url(Object? raw) {
      final s = '${raw ?? ''}';
      return s.isEmpty ? null : absoluteMedia(s, base);
    }

    var next = _d.copyWith(
        name: '${session.user?['name'] ?? ''}'.split(' ').first);

    // Each in its own try. These answer different questions and one endpoint
    // being down must not blank the others — a home screen that goes empty
    // because the album service is asleep is worse than one missing a row.
    try {
      final g = await api.get('/api/gallery', {'limit': '1'});
      if (g is Map) next = next.copyWith(photos: (g['total'] as num?)?.toInt());
    } catch (_) {}

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

    // ALBUMS ARE THE MEMORIES. An album is a thing somebody already decided
    // was worth keeping together, which is a better memory than any rule this
    // app could invent — and it comes with a name, a count and a cover.
    try {
      final a = await api.get('/api/gallery/albums');
      final list = (a is Map ? a['albums'] : null) as List? ?? const [];
      final albums = [
        for (final e in list)
          if (e is Map)
            VividCard(
              title: '${e['name'] ?? ''}',
              sub: '${(e['count'] as num?)?.toInt() ?? 0} photos',
              imageUrl: url(e['cover_url']),
              count: (e['count'] as num?)?.toInt() ?? 0,
            ),
      ]..sort((x, y) => y.count.compareTo(x.count));
      if (albums.isNotEmpty) {
        next = next.copyWith(
          albums: albums,
          // The biggest album leads, because the one with the most photographs
          // in it is the one somebody spent the most of a day on.
          memory: albums.first,
        );
      }
    } catch (_) {}

    // Nothing worth leading with? Fall back to the newest photograph, which
    // is never wrong and is always something of theirs.
    if (next.memory == null) {
      try {
        final g = await api.get('/api/gallery', {'limit': '1'});
        final items = (g is Map ? g['items'] : null) as List? ?? const [];
        if (items.isNotEmpty && items.first is Map) {
          final p = items.first as Map;
          next = next.copyWith(
            memory: VividCard(
              title: 'Your newest',
              sub: '${p['caption'] ?? p['orig_name'] ?? 'Just added'}',
              imageUrl: url(p['thumb_url']),
            ),
          );
        }
      } catch (_) {}
    }

    try {
      final r = await api.get('/api/people',
          {'limit': '12', 'min_photos': '2', 'quality': '1'});
      final list = (r is Map ? r['people'] : null) as List? ?? const [];
      final unnamed = RegExp(r'^person\s*\d+$', caseSensitive: false);
      next = next.copyWith(people: [
        for (final e in list)
          if (e is Map && '${e['name'] ?? ''}'.trim().isNotEmpty &&
              !unnamed.hasMatch('${e['name']}'.trim()))
            VividCard(
              title: '${e['name']}',
              imageUrl: url(e['cover_url']),
              count: (e['count'] as num?)?.toInt() ??
                  (e['photo_count'] as num?)?.toInt() ??
                  0,
            ),
      ]);
    } catch (_) {}

    // The document kinds, for the four counts inside the Files card. Asked of
    // the server rather than tallied from a page, which would change as you
    // scrolled.
    final kinds = <String, int>{};
    for (final k in const ['pdf', 'image', 'sheet', 'other']) {
      try {
        final r = await api.get('/api/documents', {'ftype': k, 'limit': '1'});
        final total = (r is Map ? r['total'] : null) as num?;
        if (total != null) kinds[k] = total.toInt();
      } catch (_) {}
    }
    if (kinds.isNotEmpty) next = next.copyWith(kinds: kinds);

    if (mounted) setState(() => _d = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.skin;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.zero, children: [
          _Header(brand: widget.brand, name: _d.name, colour: t.brand),

          // ── THE PHOTOGRAPH ────────────────────────────────────────────
          if (_d.memory != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: MemoryHero(
                title: _d.memory!.title,
                subtitle: _d.memory!.sub,
                imageUrl: _d.memory!.imageUrl,
                faceUrls: _d.memoryFaces,
                pips: _d.memory!.count > 1 ? 4 : 0,
                onTap: widget.onOpenPhotos,
              ),
            ),

          // ── the figures, now underneath the picture ───────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: _Counts(
              photos: _d.photos,
              videos: _d.videos,
              documents: _d.documents,
              onPhotos: widget.onOpenPhotos,
              onFiles: widget.onOpenFiles,
            ),
          ),

          if (_d.people.isNotEmpty) ...[
            _SectionHead(
                title: 'People',
                trailing: 'See all ${_d.people.length}',
                onTap: widget.onOpenPhotos),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: _d.people.length,
                separatorBuilder: (_, _) => const SizedBox(width: 13),
                itemBuilder: (_, i) => _Face(card: _d.people[i]),
              ),
            ),
          ],

          if (_d.albums.isNotEmpty) ...[
            _SectionHead(
                title: 'Places & days',
                trailing: 'See all',
                onTap: widget.onOpenPhotos),
            SizedBox(
              height: 158,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: _d.albums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _Album(card: _d.albums[i]),
              ),
            ),
          ],

          // ── files, as one wide card rather than a second grid ─────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
            child: _FilesCard(
              total: _d.documents,
              kinds: _d.kinds,
              colour: t.module('documents'),
              onTap: widget.onOpenFiles,
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: _Tiles(onOpen: widget.onOpen),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            child: _BackupRow(ok: t.ok, radius: t.radius),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.brand, required this.name, required this.colour});

  final Brand brand;
  final String name;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(18, media.padding.top + 14, 18, 20),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Row(children: [
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
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: Colors.white)),
              ]),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.search, color: Colors.white),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.16),
            minimumSize: const Size(44, 44),
          ),
        ),
      ]),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({
    required this.photos,
    required this.videos,
    required this.documents,
    this.onPhotos,
    this.onFiles,
  });

  final int? photos;
  final int? videos;
  final int? documents;
  final VoidCallback? onPhotos;
  final VoidCallback? onFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.skin;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        _One(
            value: photos,
            label: 'Photos',
            colour: t.module('gallery'),
            icon: Icons.photo_outlined,
            onTap: onPhotos),
        _Rule(colour: theme.colorScheme.outlineVariant),
        _One(
            value: videos,
            label: 'Videos',
            colour: t.module('notes'),
            icon: Icons.videocam_outlined,
            onTap: onPhotos),
        _Rule(colour: theme.colorScheme.outlineVariant),
        _One(
            value: documents,
            label: 'Files',
            colour: t.module('documents'),
            icon: Icons.folder_outlined,
            onTap: onFiles),
      ]),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.colour});
  final Color colour;
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 44, color: colour);
}

class _One extends StatelessWidget {
  const _One({
    required this.value,
    required this.label,
    required this.colour,
    required this.icon,
    this.onTap,
  });

  final int? value;
  final String label;
  final Color colour;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: colour),
              ),
              const SizedBox(height: 7),
              Text(vividCount(value),
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()])),
              Text(label,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      );
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, this.trailing, this.onTap});

  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 10, 10),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3)),
          ),
          if (trailing != null)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(trailing!,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
        ]),
      );
}

/// A face with its count under the name.
///
/// The count is not decoration: it is what tells somebody whether tapping is
/// worth it, and it is the difference between a row of portraits and a row of
/// ways in.
class _Face extends StatelessWidget {
  const _Face({required this.card});
  final VividCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 62,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: ClipOval(
            child: card.imageUrl == null
                ? Icon(Icons.person,
                    size: 26, color: theme.colorScheme.outline)
                : Image.network(card.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(Icons.person,
                        size: 26, color: theme.colorScheme.outline)),
          ),
        ),
        const SizedBox(height: 6),
        Text(card.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        if (card.count > 0)
          Text('${card.count}',
              style: TextStyle(
                  fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Album extends StatelessWidget {
  const _Album({required this.card});
  final VividCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.skin;
    return SizedBox(
      width: 150,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(t.radius),
              child: SizedBox(
                height: 110,
                width: 150,
                child: card.imageUrl == null
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest)
                    : Image.network(card.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest)),
              ),
            ),
            const SizedBox(height: 8),
            Text(card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            Text(card.sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          ]),
    );
  }
}

/// Documents, as ONE card carrying its own breakdown.
///
/// Four separate tiles would put files on equal footing with the four smaller
/// modules below, and they are not equal: this is the second of the two things
/// the product is for.
class _FilesCard extends StatelessWidget {
  const _FilesCard({
    required this.total,
    required this.kinds,
    required this.colour,
    this.onTap,
  });

  final int? total;
  final Map<String, int> kinds;
  final Color colour;
  final VoidCallback? onTap;

  static const _labels = <String, String>{
    'pdf': 'PDFs',
    'image': 'Scans',
    'sheet': 'Sheets',
    'other': 'Other',
  };

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
          child: Column(children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.folder_outlined,
                    size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Documents',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      Text('${vividCount(total)} files',
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.white70)),
                    ]),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.white70),
            ]),
            if (kinds.isNotEmpty) ...[
              const SizedBox(height: 13),
              Row(children: [
                for (final entry in _labels.entries) ...[
                  if (entry.key != 'pdf') const SizedBox(width: 7),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Column(children: [
                        Text('${kinds[entry.key] ?? 0}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        Text(entry.value,
                            style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70)),
                      ]),
                    ),
                  ),
                ],
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({this.onOpen});
  final void Function(String key)? onOpen;

  static const _items = <({String key, String label, IconData icon})>[
    (key: 'expenses', label: 'Money', icon: Icons.account_balance_wallet_outlined),
    (key: 'notes', label: 'Notes', icon: Icons.lightbulb_outline),
    (key: 'vault', label: 'Vault', icon: Icons.lock_outline),
    (key: 'reminders', label: 'Reminders', icon: Icons.notifications_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.skin;
    return Row(children: [
      for (var i = 0; i < _items.length; i++) ...[
        if (i > 0) const SizedBox(width: 11),
        Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              // STRETCH, or the tile is only as wide as the icon inside it.
              // A Column centres by default, so the Material took its child's
              // width and four rounded squares rendered as four narrow pills —
              // visible in a render, invisible to every assertion.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Material(
              color: t.module(_items[i].key),
              borderRadius: BorderRadius.circular(t.radius),
              child: InkWell(
                onTap: () => onOpen?.call(_items[i].key),
                borderRadius: BorderRadius.circular(t.radius),
                child: SizedBox(
                  height: 58,
                  child: Icon(_items[i].icon, size: 22, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(_items[i].label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
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
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
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
