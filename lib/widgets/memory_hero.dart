/// The photograph at the top of Home.
///
/// EVERY EARLIER VERSION OF THIS SCREEN LED WITH A NUMBER, and that was the
/// thing wrong with it: a photos app whose first screen is counts and a
/// progress ring reads as a dashboard for a library rather than as the
/// library. The hero is a picture now — a place, a date, and the faces of who
/// is in it — because that is the card that makes somebody open the app when
/// they have nothing particular to do.
///
/// It is also the only element here that cannot be judged from a mockup: a
/// grey rectangle where the photograph goes is exactly what made the earlier
/// designs look empty, and the real one will not.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class MemoryHero extends StatelessWidget {
  const MemoryHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.when = '',
    this.imageUrl,
    this.faceUrls = const [],
    this.pips = 0,
    this.onTap,
  });

  /// What this memory is — an album name, a place, a day.
  final String title;

  /// Underneath: how many photographs, and where.
  final String subtitle;

  /// "2 years ago". Empty hides the badge rather than showing an empty one.
  final String when;

  final String? imageUrl;

  /// Whose faces are in it. Capped at three by the layout; a fourth adds
  /// nothing but width.
  final List<String> faceUrls;

  /// How many photographs this memory pages through. Drawn as the story pips
  /// along the top, the shape people already read as "there is more here".
  /// Zero hides them, because a single pip is a progress bar for one item.
  final int pips;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.skin;
    final theme = Theme.of(context);
    final shown = pips.clamp(0, 5);

    return Semantics(
      button: true,
      label: '$title. $subtitle.',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.radius + 6),
          child: SizedBox(
            height: 216,
            child: Stack(fit: StackFit.expand, children: [
              // The picture. A flat surface underneath rather than nothing, so
              // the card has its shape before the image arrives and does not
              // pop into existence.
              ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
              if (imageUrl != null && imageUrl!.isNotEmpty)
                Image.network(imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink()),

              // The scrim. Only over the bottom third: a wash across the whole
              // picture to make text readable is how a photograph gets ruined
              // to carry two lines of type.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 116,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00080C1A), Color(0xD1080C1A)],
                    ),
                  ),
                ),
              ),

              if (shown > 1)
                Positioned(
                  left: 14,
                  right: 14,
                  top: 13,
                  child: Row(children: [
                    for (var i = 0; i < shown; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: i == 0
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),

              if (when.isNotEmpty)
                Positioned(
                  right: 13,
                  top: shown > 1 ? 26 : 13,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(when,
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),

              Positioned(
                left: 16,
                right: 16,
                bottom: 15,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: Colors.white)),
                      const SizedBox(height: 6),
                      Row(children: [
                        if (faceUrls.isNotEmpty) ...[
                          _FaceStack(urls: faceUrls.take(3).toList()),
                          const SizedBox(width: 9),
                        ],
                        Expanded(
                          child: Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFD8DEEC))),
                        ),
                      ]),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Overlapping faces, the way a group is shown everywhere.
///
/// Each carries a rim in the scrim's own colour rather than white: a white
/// ring over a dark photograph reads as a sticker, and the point is that these
/// people are IN the picture.
class _FaceStack extends StatelessWidget {
  const _FaceStack({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 22,
        width: 22 + (urls.length - 1) * 15,
        child: Stack(children: [
          for (var i = 0; i < urls.length; i++)
            Positioned(
              left: i * 15,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF3A4458),
                  border: Border.all(color: const Color(0xFF12162A), width: 1.5),
                ),
                child: ClipOval(
                  child: Image.network(urls[i],
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              ),
            ),
        ]),
      );
}
