/// The person's own photograph, behind the whole app.
///
/// Classic draws every page on a transparent scaffold, so whatever is here
/// shows through all of it. That is what makes this worth having and also what
/// makes it dangerous: an undimmed picture puts white cards and grey captions
/// over a bright sky, and nothing on the page can be read. The dim is not a
/// decoration — it is the thing that keeps the app usable, which is why it has
/// a floor and cannot be turned off.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../customize.dart';
import '../theme.dart';

class PhotoBackdrop extends StatelessWidget {
  const PhotoBackdrop({super.key, this.path, this.dim});

  /// Defaults to whatever is saved, so `main.dart` needs no wiring.
  final String? path;
  final int? dim;

  @override
  Widget build(BuildContext context) {
    final file = path ?? Customize.backgroundImagePath;
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    // RAISED TO WHAT IS LEGIBLE, whatever was saved. The floor depends on the
    // theme — a dark page needs more veil than a light one — so somebody who
    // set 50% in light mode and then switched to dark must not be left with an
    // app they cannot read. Enforced here rather than at the slider, because
    // this is the only place that knows which theme is actually painting.
    final floor = readableVeil(ink: theme.colorScheme.onSurface,
        surface: surface);
    final asked = ((dim ?? Customize.backgroundDim)
            .clamp(Customize.dimMin, Customize.dimMax)) /
        100;
    final shade = asked < floor ? floor : asked;

    if (file.isEmpty) return ColoredBox(color: surface);

    return Stack(
      fit: StackFit.expand,
      children: [
        // An opaque colour UNDER the picture, not merely behind the app. The
        // image is decoded asynchronously, so for the first frames there is
        // nothing here at all — and a transparent scaffold over nothing is a
        // black flash on every cold start.
        ColoredBox(color: surface),
        Image.file(
          File(file),
          fit: BoxFit.cover,
          // The file is a copy we made and never changes, so decoding it once
          // is right. Without this every rebuild of the app shell — and there
          // is one on each settings change — decodes a camera photograph again.
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => ColoredBox(color: surface),
        ),
        // THE VEIL IS THE PAGE COLOUR, NOT BLACK — and getting this wrong is
        // what made the first version unreadable.
        //
        // Every word in Classic is dark ink chosen to be read on a near-white
        // page. Darkening the photograph moved the ground the WRONG WAY: dark
        // text on a darkened picture is worse than dark text on the picture
        // itself. What the text needs is its own ground back, so the veil is
        // `surface` — the colour the app was drawn for. In dark mode that is
        // a dark surface and light text, and the same reasoning holds without
        // a second branch.
        //
        // Flat colour rather than a blur, still: a blur is a per-frame GPU
        // pass behind every screen in the app, on a phone that is also
        // decoding a camera roll, and it buys nothing a rectangle does not.
        ColoredBox(color: surface.withValues(alpha: shade)),
      ],
    );
  }
}

/// Copy [asset] into the app's own folder and make it the background.
///
/// COPIED, NOT REFERENCED, and this is the whole reason this function exists
/// rather than a one-line setter. A path into the camera roll is not a
/// promise: the person may delete the photograph, and on iOS a library path is
/// not readable again after a restart at all — the app would come back with a
/// blank screen and nothing to say why. A copy is a few megabytes and it is
/// ours.
///
/// Returns the stored path, or null if the phone could not produce the file —
/// a picture still in iCloud, most often, which is the same reason a photo
/// sometimes cannot be backed up.
Future<String?> adoptBackgroundPhoto(AssetEntity asset) async {
  final src = await asset.file;
  if (src == null) return null;

  final dir = await getApplicationDocumentsDirectory();
  final into = Directory(p.join(dir.path, 'background'));
  await into.create(recursive: true);

  // A NEW NAME EVERY TIME, and the old one deleted afterwards. Writing over
  // the same filename leaves Flutter's image cache holding the previous
  // picture under that key, so the setting appears not to have worked until
  // the app is restarted.
  final ext = p.extension(src.path).toLowerCase();
  final name = 'bg_${DateTime.now().millisecondsSinceEpoch}'
      '${ext.isEmpty ? '.jpg' : ext}';
  final dest = File(p.join(into.path, name));
  await src.copy(dest.path);

  final previous = Customize.backgroundImagePath;
  await Customize.setBackgroundPhoto(dest.path);

  if (previous.isNotEmpty && previous != dest.path) {
    // Best effort. A leftover file wastes a few megabytes; failing here would
    // throw away a background the person has just successfully chosen.
    try {
      await File(previous).delete();
    } catch (_) {}
  }
  return dest.path;
}
