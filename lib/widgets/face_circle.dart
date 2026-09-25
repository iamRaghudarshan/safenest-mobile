/// A person's face, cropped out of the photo it was found in.
///
/// THE BUG THIS EXISTS FOR. The People row showed each person as a circle
/// containing the MIDDLE of a whole photograph. On a group shot that is
/// somebody's shoulder; on a landscape it is scenery. It looked like the
/// feature had not worked at all, and the complaint — fairly — was that this
/// is not what Google Photos does.
///
/// The server knows where the face is and now sends it with the person, as
/// FRACTIONS of the cover photo. Fractions rather than pixels because what is
/// being cropped is a thumbnail of unknown size: a pixel rectangle measured
/// against the original lands somewhere else entirely once the picture has
/// been scaled down.
///
/// WHEN THERE IS NO BOX it shows the whole picture, exactly as before. An
/// older server does not send one, and a face whose position was never
/// recorded has none — guessing a crop would be worse than showing the photo.
library;

import 'package:flutter/material.dart';

class FaceCircle extends StatelessWidget {
  const FaceCircle({
    super.key,
    required this.imageUrl,
    required this.box,
    this.size = 64,
    this.placeholder,
  });

  final String? imageUrl;

  /// {x, y, w, h} as fractions of the photo, or null.
  final Map<String, dynamic>? box;
  final double size;
  final Widget? placeholder;

  double? _f(String k) {
    final v = box?[k];
    return v is num ? v.toDouble() : null;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = placeholder ??
        Icon(Icons.person, color: Theme.of(context).colorScheme.outline);

    if (imageUrl == null || imageUrl!.isEmpty) {
      return SizedBox(width: size, height: size, child: Center(child: fallback));
    }

    final image = Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      // The crop enlarges part of a thumbnail, so it needs more pixels than
      // the circle is wide or the face comes out soft.
      cacheWidth: (size * 4).round(),
      errorBuilder: (_, _, _) => Center(child: fallback),
    );

    final x = _f('x'), y = _f('y'), w = _f('w'), h = _f('h');
    if (x == null || y == null || w == null || h == null || w <= 0 || h <= 0) {
      return SizedBox(width: size, height: size, child: image);
    }

    // The face is a fraction of the picture, so the PICTURE is scaled up by
    // the inverse of that fraction and then shifted so the face lands in the
    // middle. FractionalTranslation moves by a fraction of the child's own
    // size, which is why the offsets are divided by w and h.
    final scale = 1 / (w < h ? w : h);
    final cx = x + w / 2;
    final cy = y + h / 2;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Transform.scale(
            scale: scale,
            child: FractionalTranslation(
              translation: Offset(0.5 - cx, 0.5 - cy),
              child: SizedBox(width: size, height: size, child: image),
            ),
          ),
        ),
      ),
    );
  }
}
