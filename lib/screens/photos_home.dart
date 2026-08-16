/// The Photos section — the one big grid, and everything that is not a grid.
///
/// TWO SEGMENTS, NOT FOUR. It was Photos | Albums | People | Memories, and that
/// shape had two faults. Three of the four were tabs you had to open to find
/// out whether they held anything, and — worse — it was full: favourites, the
/// bin, places and recently-added had nowhere left to go and so could not be
/// reached from this screen at all. Collections holds all of them and says how
/// much is in each before you tap. It is the shape Google Photos settled on and
/// it is settled on for this reason.
///
/// A SEGMENTED CONTROL, not a Material TabBar. The web app uses `.seg4`: a pill
/// of segments on a card, the selected one filled with the brand colour and
/// carrying its glow. An underlined tab bar is a different control from a
/// different design language, and using it here was a large part of why the two
/// halves did not look like one product.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../backup.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/brand_button.dart';
import 'backup_screen.dart';
import 'collections_home.dart';
import 'gallery_screen.dart';
import 'cleanup_screen.dart';
import 'trash_screen.dart';

class PhotosHome extends StatefulWidget {
  const PhotosHome({super.key});
  @override
  State<PhotosHome> createState() => _PhotosHomeState();
}

class _PhotosHomeState extends State<PhotosHome> {
  int _tab = 0;

  static const _labels = ['Photos', 'Collections'];

  /// The backup service is OWNED here, not by the backup screen, so the status
  /// strip below the tabs and the full screen show one and the same run. Created
  /// once dependencies are available (it needs the signed-in server).
  BackupService? _backup;

  /// So switching to Collections re-reads its counts. It is kept alive in an
  /// IndexedStack, so without this it would show whatever was true when the
  /// screen first opened — and the most common reason to look at it is having
  /// just backed up new photos.
  final _collections = GlobalKey<CollectionsHomeState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backup ??= (BackupService(context.read<Session>().api)..load());
  }

  @override
  void dispose() {
    _backup?.stop();
    _backup?.dispose();
    super.dispose();
  }

  void _openBackup() {
    final s = _backup;
    if (s == null) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BackupScreen(service: s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          IconButton(
            tooltip: 'Back up this phone',
            icon: const Icon(Icons.backup_outlined),
            onPressed: _openBackup,
          ),
          IconButton(
            tooltip: 'Free up space',
            icon: const Icon(Icons.auto_delete_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CleanupScreen())),
          ),
          // Delete is soft on the server, so without a way in the phone could
          // put photos somewhere it could not then look. Also a tile in
          // Collections; kept here because this is where you are standing when
          // you have just deleted something.
          IconButton(
            tooltip: 'Recently deleted',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrashScreen())),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Segmented(
            labels: _labels,
            index: _tab,
            onChanged: (i) {
              setState(() => _tab = i);
              if (i == 1) _collections.currentState?.load();
            },
          ),
        ),
        // A live backup status + entry, right here on the gallery, so you can see
        // it running and start it without hunting for a separate screen.
        if (_tab == 0 && _backup != null)
          ListenableBuilder(
            listenable: _backup!,
            builder: (context, _) => _backupStrip(context, _backup!.progress),
          ),
        Expanded(
          // IndexedStack, so the grid keeps its scroll position and its paging
          // while the other views are looked at. Rebuilding it would mean
          // scrolling back through several thousand photos to get where you were.
          child: IndexedStack(
            index: _tab,
            children: [
              const GalleryScreen(embedded: true),
              CollectionsHome(key: _collections),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _backupStrip(BuildContext context, BackupProgress p) {
    final theme = Theme.of(context);
    final accent = kModuleColours['gallery']!;
    final running =
        p.state == BackupState.running || p.state == BackupState.scanning;
    final failed = p.state == BackupState.failed;
    final done = p.state == BackupState.done;
    final seen = p.done + p.skipped;

    final String text;
    if (running) {
      text = p.total > 0 ? 'Backing up… $seen of ${p.total}' : 'Backing up…';
    } else if (failed) {
      text = 'Backup needs attention';
    } else if (done) {
      text = p.done > 0 ? 'Backed up · ${p.done} new' : 'Everything is backed up';
    } else {
      text = 'Back up this phone';
    }
    final icon = running
        ? Icons.cloud_sync_outlined
        : failed
            ? Icons.cloud_off_outlined
            : done
                ? Icons.cloud_done_outlined
                : Icons.backup_outlined;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Material(
        color: (failed ? kDanger : accent).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openBackup,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, color: failed ? kDanger : accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (running && p.total > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (seen / p.total).clamp(0.0, 1.0),
                            minHeight: 4,
                            color: accent,
                            backgroundColor: accent.withValues(alpha: 0.20),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}
