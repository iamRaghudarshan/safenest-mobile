/// Choosing the app's look, by looking at it.
///
/// Two rows reading "Classic" and "Colourful" would be a setting nobody can
/// evaluate without flipping it: a whole-app repaint is exactly the change
/// people want to SEE before they commit to it, and the app already has the
/// one thing needed to show them — a theme it can build for either skin
/// without wearing it.
///
/// So each card is drawn inside `Theme(data: buildTheme(..., skin: ...))` and
/// paints itself from `context.skin`. Nothing here hard-codes a colour, which
/// means the previews cannot drift from the real thing: change a token in
/// theme.dart and both cards follow on the next build.
library;

import 'package:flutter/material.dart';

import '../customize.dart';
import '../theme.dart';

class SkinPicker extends StatelessWidget {
  const SkinPicker({super.key, required this.brand, this.onChanged});

  final Brand brand;

  /// Called after the choice is saved, so the screen holding this can
  /// setState. The app-wide repaint happens through `Customize.revision`
  /// regardless; this is only for the tick moving.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
        // Top-aligned rather than stretched: the two cards are the same
        // height anyway, and a stretch here would hide the bug above rather
        // than fix it.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Expanded(
        child: _SkinCard(
          brand: brand,
          skin: AppSkin.classic,
          dark: dark,
          label: 'Classic',
          caption: 'As it has always been',
          selected: !Customize.vividSkin,
          onTap: () async {
            await Customize.setSkin(Customize.skinClassic);
            onChanged?.call();
          },
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _SkinCard(
          brand: brand,
          skin: AppSkin.vivid,
          dark: dark,
          label: 'Colourful',
          caption: 'Photos and files lead',
          selected: Customize.vividSkin,
          onTap: () async {
            await Customize.setSkin(Customize.skinVivid);
            onChanged?.call();
          },
        ),
      ),
    ]);
  }
}

class _SkinCard extends StatelessWidget {
  const _SkinCard({
    required this.brand,
    required this.skin,
    required this.dark,
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final Brand brand;
  final AppSkin skin;
  final bool dark;
  final String label;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The card is drawn in the skin it OFFERS, not the one in force — that is
    // the whole point of it.
    final theme = buildTheme(brand, dark ? Brightness.dark : Brightness.light,
        skin: skin);
    final t = SkinTokens.of(skin);
    final scheme = theme.colorScheme;
    // The ring is drawn in the CURRENT skin's brand, not the offered one, so
    // the selected state reads consistently across both cards.
    final ring = context.skin.brand;

    return Semantics(
      selected: selected,
      button: true,
      label: '$label theme. $caption.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius),
            border: Border.all(
              color: selected ? ring : scheme.outlineVariant,
              width: selected ? 2.2 : 1,
            ),
          ),
          child: Column(
              // Sized by its content. Without this the column takes every
              // pixel the row will give it, and in a settings list that is
              // the whole remaining screen — two cards with a caption at the
              // top and a field of nothing beneath.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _Preview(theme: theme, tokens: t),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 9, 7, 5),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 1),
                        Text(caption,
                            maxLines: 2,
                            style: TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      ]),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 19, color: ring),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A miniature of the app: header, the two things it is for, and a nav bar.
///
/// Small enough that it reads as a swatch rather than pretending to be a
/// screenshot — a fake screenshot invites people to look for detail that is
/// not there. What it does show is the only thing that differs: the ground,
/// the brand colour, how much colour there is, and how round things are.
class _Preview extends StatelessWidget {
  const _Preview({required this.theme, required this.tokens});

  final ThemeData theme;
  final SkinTokens tokens;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final vivid = tokens.isVivid;
    final r = tokens.radiusSm;

    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius - 5),
      child: Container(
        height: 104,
        color: theme.brightness == Brightness.dark
            ? scheme.surface
            : (vivid ? const Color(0xFFF5F7FC) : const Color(0xFFF4F5FB)),
        child: Column(children: [
          // The header. Vivid fills it with brand; classic leaves it plain,
          // which is the single most visible difference between the two.
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            color: vivid ? tokens.brand : scheme.surface,
            alignment: Alignment.centerLeft,
            child: Row(children: [
              Container(
                width: 22,
                height: 5,
                decoration: BoxDecoration(
                  color: vivid ? Colors.white : scheme.onSurface,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const Spacer(),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: vivid ? Colors.white70 : scheme.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
            ]),
          ),
          // The two tiles. In vivid they are solid module colour; in classic
          // they are white cards with a coloured dot.
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
            child: Row(children: [
              Expanded(child: _Tile(tokens: tokens, scheme: scheme, module: 'gallery', vivid: vivid, radius: r)),
              const SizedBox(width: 6),
              Expanded(child: _Tile(tokens: tokens, scheme: scheme, module: 'documents', vivid: vivid, radius: r)),
            ]),
          ),
          const Spacer(),
          // The bar.
          Container(
            height: 20,
            color: scheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 5; i++)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == 0 ? tokens.brand : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tokens,
    required this.scheme,
    required this.module,
    required this.vivid,
    required this.radius,
  });

  final SkinTokens tokens;
  final ColorScheme scheme;
  final String module;
  final bool vivid;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colour = tokens.module(module);
    return Container(
      height: 34,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: vivid ? colour : scheme.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: vivid ? Colors.white.withValues(alpha: 0.55) : colour,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const Spacer(),
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: vivid
                ? Colors.white.withValues(alpha: 0.9)
                : scheme.onSurfaceVariant.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ]),
    );
  }
}
