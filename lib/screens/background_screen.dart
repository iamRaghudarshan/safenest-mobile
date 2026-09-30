/// Choosing what the whole app is drawn on.
///
/// Classic's scaffolds are transparent, so this one setting is behind every
/// screen in the app. Two things follow, and both shape this page:
///
///   * the DIM is not decoration. An undimmed photograph puts white cards and
///     grey captions over a bright sky and the app stops being readable, so
///     the slider has a floor and there is a live sample beside it — a number
///     on its own says nothing about whether somebody's own picture can be
///     read over.
///   * the picture is COPIED into the app's own folder, never referenced in
///     the camera roll. See `adoptBackgroundPhoto`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../customize.dart';
import '../theme.dart';
import '../widgets/nature_backdrop.dart';
import '../widgets/photo_backdrop.dart';

class BackgroundScreen extends StatefulWidget {
  const BackgroundScreen({super.key, this.debugRecent});

  /// Stand-in for the camera roll, so the page can be drawn in a test.
  final List<AssetEntity>? debugRecent;

  @override
  State<BackgroundScreen> createState() => _BackgroundScreenState();
}

class _BackgroundScreenState extends State<BackgroundScreen> {
  List<AssetEntity> _recent = const [];
  bool _loading = true;
  bool _denied = false;
  int _dim = Customize.backgroundDim;

  @override
  void initState() {
    super.initState();
    if (widget.debugRecent != null) {
      _recent = widget.debugRecent!;
      _loading = false;
      return;
    }
    _loadRecent();
  }

  /// The last two dozen photographs, offered inline.
  ///
  /// Rather than only a "choose a picture" button: the picture somebody wants
  /// behind their app is very often one they took recently, and a grid they
  /// can tap is two taps shorter than a system picker.
  Future<void> _loadRecent() async {
    try {
      final ok = await PhotoManager.requestPermissionExtend();
      if (!ok.hasAccess) {
        if (mounted) {
          setState(() {
            _denied = true;
            _loading = false;
          });
        }
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
          onlyAll: true, type: RequestType.image);
      final items = albums.isEmpty
          ? <AssetEntity>[]
          : await albums.first.getAssetListRange(start: 0, end: 24);
      if (mounted) {
        setState(() {
          _recent = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose(AssetEntity asset) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await adoptBackgroundPhoto(asset);
    if (!mounted) return;
    if (path == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('This phone could not produce that picture. If it is in '
            'iCloud it may still be downloading.'),
      ));
      return;
    }
    setState(() {});
  }

  Future<void> _pick(String which) async {
    await Customize.setBackground(which);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The floor the backdrop will actually enforce, which depends on the theme
    // — so the slider has to ask rather than name a number of its own. A
    // control that lets somebody choose a value that is then quietly raised is
    // worse than one that does not offer it.
    final floor = readableVeilPercent(theme);
    final shown = _dim < floor ? floor : _dim;

    return Scaffold(
      appBar: AppBar(title: const Text('App background')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Text(
              'Classic draws every page on top of this, so it shows through '
              'the whole app.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),

          Row(children: [
            Expanded(
              child: _Choice(
                label: 'Nature',
                selected: Customize.natureBackground,
                onTap: () => _pick(Customize.backgroundNature),
                preview: const IgnorePointer(child: NatureBackdrop()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                label: 'Plain',
                selected: Customize.background == Customize.backgroundPlain,
                onTap: () => _pick(Customize.backgroundPlain),
                // WHAT "PLAIN" ACTUALLY LOOKS LIKE is the page colour, and a
                // swatch of the page colour on the page is an empty rectangle
                // — rendered, this tile simply was not there. The band along
                // the bottom is the surface a card sits on, which is the
                // honest difference between this and nothing at all.
                preview: Column(children: [
                  Expanded(child: ColoredBox(color: theme.colorScheme.surface)),
                  Container(
                    height: 34,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                label: 'Your photo',
                selected: Customize.photoBackground,
                // Selecting it without one chosen would leave the app on a
                // blank screen, so the tile picks a picture instead.
                onTap: Customize.backgroundImagePath.isEmpty
                    ? null
                    : () => _pick(Customize.backgroundPhoto),
                preview: Customize.backgroundImagePath.isEmpty
                    ? Center(
                        child: Icon(Icons.image_outlined,
                            size: 22,
                            color: theme.colorScheme.onSurfaceVariant),
                      )
                    : Image.file(File(Customize.backgroundImagePath),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          ]),

          const SizedBox(height: 22),
          Text('FROM YOUR PHOTOS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_denied)
            Text(
                'SafeNest has not been allowed to see your photos, so there is '
                'nothing to show here. You can change that in the phone’s '
                'settings.',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant))
          else if (_recent.isEmpty)
            Text('No photographs on this phone yet.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
          else
            SizedBox(
              height: 86,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _Thumb(
                  asset: _recent[i],
                  onTap: () => _choose(_recent[i]),
                ),
              ),
            ),

          const SizedBox(height: 24),
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: Text('Dim it',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text('$shown%',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: kBrand)),
          ]),
          const SizedBox(height: 2),
          Text(
              'Your pages sit on top of the picture. This fades it back '
              'towards the page colour so the words stay readable.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: theme.colorScheme.onSurfaceVariant)),

          Slider(
            value: shown.toDouble(),
            min: floor.toDouble(),
            max: Customize.dimMax.toDouble(),
            divisions: (Customize.dimMax - floor) ~/ 2,
            label: '$shown%',
            // Live while dragging, saved when it stops: writing to disk and
            // rebuilding the whole app on every pixel of a drag is what makes
            // a slider stutter.
            onChanged: (v) => setState(() => _dim = v.round()),
            onChangeEnd: (v) => Customize.setBackgroundDim(v.round()),
          ),

          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _DimSample(dim: shown),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'A live sample, because a number on its own says '
                        'nothing about whether your own picture can be read '
                        'over.',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.55,
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 7),
                      decoration: BoxDecoration(
                        color: kWarn.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                          'It will not go below $floor%: that is the least '
                          'that keeps the words readable over any picture. '
                          'The dark theme needs a little more.',
                          style: const TextStyle(fontSize: 11, height: 1.45)),
                    ),
                  ]),
            ),
          ]),
        ],
      ),
    );
  }
}

/// One of the three big choices.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 104,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              // `outlineVariant` is a hairline meant to separate rows inside a
              // card. Around a choice on a near-white page it is invisible,
              // and an invisible choice is not offered at all.
              color: selected ? kBrand : theme.colorScheme.outline,
              width: selected ? 2.5 : 1.2,
            ),
          ),
          child: preview,
        ),
      ),
      const SizedBox(height: 6),
      Text(label,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
    ]);
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.asset, required this.onTap});

  final AssetEntity asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 70,
            height: 86,
            child: FutureBuilder<dynamic>(
              future:
                  asset.thumbnailDataWithSize(const ThumbnailSize(200, 250)),
              builder: (ctx, snap) => snap.data == null
                  ? ColoredBox(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest)
                  : Image.memory(snap.data, fit: BoxFit.cover),
            ),
          ),
        ),
      );
}

/// The dim, shown on something with words over it.
class _DimSample extends StatelessWidget {
  const _DimSample({required this.dim});

  final int dim;

  @override
  Widget build(BuildContext context) {
    final has = Customize.backgroundImagePath.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(fit: StackFit.expand, children: [
          // Their own picture where there is one — the whole point is to judge
          // THIS photograph, not a stand-in that is easier to read over.
          if (has)
            PhotoBackdrop(path: Customize.backgroundImagePath, dim: dim)
          else ...[
            const IgnorePointer(child: NatureBackdrop()),
            ColoredBox(color: Colors.black.withValues(alpha: dim / 100)),
          ],
          Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Welcome',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('All clear',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.88))),
                ]),
          ),
        ]),
      ),
    );
  }
}
