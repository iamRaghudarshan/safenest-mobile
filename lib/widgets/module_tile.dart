/// The coloured icon tile.
///
/// One widget, used by the Modules grid and by the Gallery's "what is backed
/// up" panel, because they are the same object: a square of colour, a white
/// glyph, a name, and how much is in it. Two implementations drifting apart is
/// how a product stops looking like one product.
///
/// WHAT MAKES IT LOOK LIKE THE REFERENCE, in order of how much each contributes:
///
///   1. A SHADOW IN THE TILE'S OWN HUE, not a grey one. This is the whole
///      effect. A grey shadow under a blue square reads as a sticker on paper;
///      a blue shadow reads as a lit object. Everything else here is ordinary.
///   2. A gradient from a lighter top-left to a deeper bottom-right, about two
///      steps apart in lightness. Flat fills look printed.
///   3. A generous corner radius — nearly a third of the side — so the square
///      reads as soft rather than as a rounded rectangle.
///
/// THE TWO COLOURS ARE DERIVED, not listed. `kModuleColours` already holds one
/// colour per module and a second table would be one more place for a new
/// module to be forgotten — which this codebase has a documented history of.
/// Lightening and darkening the one colour gives a pair that is always
/// consistent with it, including for the vivid skin's different palette.
library;

import 'package:flutter/material.dart';

/// How far apart the two ends of the gradient sit, in HSL lightness.
///
/// Small on purpose. A wide gradient on a 46-point square looks like a button
/// from a different decade; the reference's tiles are nearly flat and get their
/// depth from the shadow instead.
const _lift = 0.10;

/// How far the glyph is inset. The reference's icons sit well inside their
/// tile — roughly half the side — which is what stops a row of them looking
/// like a toolbar.
const _glyphRatio = 0.48;

@immutable
class ModuleTile extends StatelessWidget {
  const ModuleTile({
    super.key,
    required this.icon,
    required this.colour,
    required this.label,
    this.count,
    this.onTap,
    this.size = 46,
  });

  final IconData icon;
  final Color colour;
  final String label;

  /// "1,780", "₹0", "today". A string rather than a number because not every
  /// module counts the same kind of thing, and "today" is a truer answer for a
  /// location history than a row count would be.
  final String? count;

  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (light, deep) = gradientFor(colour);

    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, deep],
        ),
        boxShadow: [
          // THE WHOLE EFFECT. See the note at the top of the file.
          BoxShadow(
            color: deep.withValues(alpha: 0.34),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.09),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * _glyphRatio),
    );

    // ONE NODE, NOT THREE. A label on a Semantics wrapper does not replace the
    // labels of the Text widgets inside it — without the exclusion a reader
    // announces the tile, then the name, then the count, as three separate
    // things to swipe through, and a grid of fifteen becomes forty-five stops.
    // The combined label is also the only place the count is spoken as
    // belonging to the name rather than as a loose number.
    return Semantics(
      button: onTap != null,
      container: true,
      label: count == null ? label : '$label, $count',
      child: ExcludeSemantics(
          child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile,
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, height: 1.2),
            ),
            if (count != null) ...[
              const SizedBox(height: 1),
              Text(
                count!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ]),
        ),
      )),
    );
  }
}

/// The two ends of a tile's gradient, from the one colour a module declares.
///
/// Clamped at both ends. A module colour that is already very light would
/// otherwise produce a near-white top and a glyph nobody can read, and one that
/// is already very dark would produce two identical blacks and lose the
/// gradient entirely.
///
/// Public because the Modules grid draws its own tile — it carries a drag
/// handle and an attention badge that nothing else needs — and the two must
/// agree about colour or the same module looks like two different modules on
/// two screens.
(Color, Color) gradientFor(Color base) {
  final hsl = HSLColor.fromColor(base);
  final light = hsl.withLightness((hsl.lightness + _lift).clamp(0.30, 0.78));
  final deep = hsl.withLightness((hsl.lightness - _lift).clamp(0.22, 0.60));
  return (light.toColor(), deep.toColor());
}
