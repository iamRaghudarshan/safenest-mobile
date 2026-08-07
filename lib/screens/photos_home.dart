/// The Photos section: the grid, plus the three views that are not a grid.
///
/// Four tabs rather than four bottom-bar entries, because the bottom bar already
/// carries Photos, Documents, Records and You — and a phone with eight
/// destinations has none. This is also the arrangement the web app uses, so
/// somebody moving between the two is not learning a second layout.
library;

import 'package:flutter/material.dart';

import 'gallery_screen.dart';
import 'library_tabs.dart';

class PhotosHome extends StatelessWidget {
  const PhotosHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Photos'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Photos'),
              Tab(text: 'Albums'),
              Tab(text: 'People'),
              Tab(text: 'Memories'),
            ],
          ),
        ),
        // The grid keeps its own scroll position and its own paging state while
        // the other tabs are looked at; rebuilding it would mean scrolling back
        // through several thousand photos to get where you were.
        body: const TabBarView(
          children: [
            GalleryScreen(embedded: true),
            AlbumsTab(),
            PeopleTab(),
            MemoriesTab(),
          ],
        ),
      ),
    );
  }
}
