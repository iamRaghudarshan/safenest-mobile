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

import '../widgets/brand_button.dart';
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

  /// So switching to Collections re-reads its counts. It is kept alive in an
  /// IndexedStack, so without this it would show whatever was true when the
  /// screen first opened — and the most common reason to look at it is having
  /// just backed up new photos.
  final _collections = GlobalKey<CollectionsHomeState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
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
}
