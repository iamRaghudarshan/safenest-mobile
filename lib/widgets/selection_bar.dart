/// The bar that appears once photos are selected, and the album picker it opens.
///
/// AT THE BOTTOM, not the top. On a phone the top of the screen is out of thumb
/// reach, and these are actions taken repeatedly while scrolling with the same
/// hand. The count is stated in words as well as shown in ticks — "3 selected"
/// is checkable at a glance, where counting ticks across a grid of thumbnails
/// is not.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'brand_button.dart';

class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.busy,
    required this.onClear,
    required this.onSelectAll,
    required this.onDelete,
    required this.onAlbum,
    required this.onFavourite,
    required this.onShare,
  });

  final int count;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onAlbum;
  final VoidCallback onFavourite;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border:
              Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            IconButton(
              tooltip: 'Cancel',
              onPressed: busy ? null : onClear,
              icon: const Icon(Icons.close),
            ),
            Expanded(
              child: Text('$count selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: busy ? null : onSelectAll,
              child: const Text('Select all'),
            ),
          ]),
          // A determinate-looking bar would be a lie — the actions are one
          // request per photo. This only says "something is happening", which
          // is all it knows.
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Row(children: [
            _Action(
                icon: Icons.ios_share,
                label: 'Share',
                onTap: busy ? null : onShare),
            _Action(
                icon: Icons.photo_album_outlined,
                label: 'Album',
                onTap: busy ? null : onAlbum),
            _Action(
                icon: Icons.star_outline,
                label: 'Star',
                onTap: busy ? null : onFavourite),
            _Action(
                icon: Icons.delete_outline,
                label: 'Delete',
                tint: kDanger,
                onTap: busy ? null : onDelete),
          ]),
        ]),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(
      {required this.icon, required this.label, this.onTap, this.tint});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final base = tint ?? Theme.of(context).colorScheme.onSurface;
    final c = onTap == null ? base.withValues(alpha: 0.4) : base;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 21, color: c),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
          ]),
        ),
      ),
    );
  }
}

/// Pick an album for the selection, or name a new one.
///
/// "New album" sits first because the common case is a set of photos that do
/// not belong anywhere yet — which is exactly what the server's own comment on
/// album creation says, and why that endpoint takes photo_ids.
class AlbumPicker extends StatefulWidget {
  const AlbumPicker({super.key, required this.albums, required this.count});
  final List<Map<String, dynamic>> albums;
  final int count;

  @override
  State<AlbumPicker> createState() => _AlbumPickerState();
}

class _AlbumPickerState extends State<AlbumPicker> {
  final _name = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final v = _name.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, {'new': true, 'name': v});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.count;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Add $n ${n == 1 ? "photo" : "photos"} to…',
              style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 14),
        if (_creating) ...[
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name of the album'),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 14),
          BrandButton(label: 'Create and add', block: true, onPressed: _create),
          const SizedBox(height: 4),
          TextButton(
              onPressed: () => setState(() => _creating = false),
              child: const Text('Choose an existing album instead')),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kModuleColours['gallery'],
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.add, color: Colors.white),
            ),
            title: const Text('New album',
                style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => setState(() => _creating = true),
          ),
          if (widget.albums.isNotEmpty) ...[
            const Divider(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.albums.length,
                itemBuilder: (ctx, i) {
                  final a = widget.albums[i];
                  final c = a['count'] ?? a['photos'] ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color:
                            kModuleColours['gallery']!.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(Icons.photo_album_outlined,
                          color: kModuleColours['gallery']),
                    ),
                    title: Text('${a['name'] ?? 'Album'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('$c ${c == 1 ? "photo" : "photos"}'),
                    onTap: () =>
                        Navigator.pop(ctx, {'new': false, 'id': a['id']}),
                  );
                },
              ),
            ),
          ],
        ],
      ]),
    );
  }
}
