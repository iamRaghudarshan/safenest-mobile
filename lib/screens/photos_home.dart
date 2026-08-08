/// The Photos section — the grid, plus the three views that are not a grid.
///
/// A SEGMENTED CONTROL, not a Material TabBar. The web app uses `.seg4`: a pill
/// of segments on a card, the selected one filled with the brand colour and
/// carrying its glow. An underlined tab bar is a different control from a
/// different design language, and using it here was a large part of why the two
/// halves did not look like one product.
library;

import 'package:flutter/material.dart';

import '../widgets/brand_button.dart';
import 'gallery_screen.dart';
import 'library_tabs.dart';
import 'trash_screen.dart';

class PhotosHome extends StatefulWidget {
  const PhotosHome({super.key});
  @override
  State<PhotosHome> createState() => _PhotosHomeState();
}

class _PhotosHomeState extends State<PhotosHome> {
  int _tab = 0;

  static const _labels = ['Photos', 'Albums', 'People', 'Memories'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          // The only way to reach a deleted photo. Delete is soft on the
          // server, so without this the phone could put photos somewhere it
          // could not then look.
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
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        Expanded(
          // IndexedStack, so the grid keeps its scroll position and its paging
          // while the other views are looked at. Rebuilding it would mean
          // scrolling back through several thousand photos to get where you were.
          child: IndexedStack(
            index: _tab,
            children: const [
              GalleryScreen(embedded: true),
              AlbumsTab(),
              PeopleTab(),
              MemoriesTab(),
            ],
          ),
        ),
      ]),
    );
  }
}
