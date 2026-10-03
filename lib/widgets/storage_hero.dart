/// What is on the computer, said as a number.
///
/// The owner sent a reference where the storage figure leads the screen, and
/// this is that panel. It is worth being clear about one difference, because it
/// changes what the number MEANS.
///
/// THE REFERENCE IS SELLING STORAGE. Its "100 GB free, upgrade to 2 TB" is a
/// plan somebody is being asked to buy, and the bar is how close they are to
/// paying. SafeNest sells nothing: the figure is the owner's own disk, the
/// remainder is the room actually left on it, and "Get more space" would be
/// advice to buy a drive rather than a button. So the bar is honest about a
/// different thing — how much of your own machine your library has taken — and
/// it turns red when the disk is genuinely filling, because that is the one
/// time this number needs to be acted on.
///
/// IT NEVER SHOWS A FIGURE IT HAS NOT GOT. An unreachable computer leaves the
/// panel saying so rather than drawing an empty bar at zero, which reads as
/// "nothing is backed up" — the most alarming possible wrong answer on this
/// screen.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Above this share of the disk, the bar stops being decorative.
const _tight = 0.90;

/// Below this share, the bar is not drawn at all.
///
/// A library of 954 KB on a 287 GB disk fills nothing: the bar renders as an
/// empty track, the legend reads "Used 0% · Free 100%", and the three of them
/// take about a hundred and ten points to say "there is plenty of room". One
/// sentence says it better and leaves that space to the photographs, which are
/// what this screen is for. The bar earns its place once the number can
/// actually move.
const _worthABar = 0.01;

@immutable
class StorageHero extends StatelessWidget {
  const StorageHero({
    super.key,
    required this.usedBytes,
    required this.freeBytes,
    required this.caption,
    this.loading = false,
    this.unreachable = false,
    this.onTap,
  });

  /// What SafeNest is holding for this account.
  final int usedBytes;

  /// What is left on the computer's disk. Zero when the server did not say —
  /// an older build has no such endpoint — and the panel then shows the used
  /// figure alone rather than inventing a total.
  final int freeBytes;

  /// "1,780 photos · 75 videos · 171 documents".
  final String caption;

  final bool loading;
  final bool unreachable;
  final VoidCallback? onTap;

  /// Used over the whole disk, or null when the free figure is unknown.
  double? get _share {
    if (freeBytes <= 0) return null;
    final total = usedBytes + freeBytes;
    return total <= 0 ? null : usedBytes / total;
  }

  /// Whether the bar is worth the space it costs. See [_worthABar].
  bool get _drawBar {
    final s = _share;
    return s != null && s >= _worthABar;
  }

  @override
  Widget build(BuildContext context) {
    final share = _share;
    final tight = share != null && share >= _tight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tight
                    ? [const Color(0xFFE05A3A), const Color(0xFFB02A12)]
                    : [kBrand, const Color(0xFF1E36C9)],
              ),
              boxShadow: [
                BoxShadow(
                  color: (tight ? const Color(0xFFB02A12) : kBrand)
                      .withValues(alpha: 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.cloud_done_outlined,
                          size: 15, color: Colors.white70),
                      const SizedBox(width: 7),
                      Text(
                        unreachable
                            ? 'LAST SEEN ON YOUR COMPUTER'
                            : 'ON YOUR COMPUTER',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Colors.white70),
                      ),
                    ]),
                    const SizedBox(height: 7),
                    if (loading)
                      const SizedBox(
                        height: 34,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white70),
                          ),
                        ),
                      )
                    else
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            // BOTH HALVES GIVE WAY. A thirty-point figure beside
                            // a total is the one row here that can outgrow a
                            // narrow phone — a terabyte library on a 320dp
                            // screen in a large accessibility font — and an
                            // overflowing headline paints over its own rounded
                            // edge, which looks like a broken card rather than
                            // a long number.
                            Flexible(
                              child: Text(
                                _short(usedBytes),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    height: 1.05,
                                    letterSpacing: -0.5,
                                    color: Colors.white),
                              ),
                            ),
                            if (freeBytes > 0) ...[
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  'of ${_short(usedBytes + freeBytes)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70),
                                ),
                              ),
                            ],
                          ]),
                    if (caption.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, height: 1.35, color: Colors.white70)),
                    ],
                    if (share != null && !_drawBar) ...[
                      const SizedBox(height: 7),
                      // What the bar would have said, in the space of a line.
                      Text('Plenty of room — ${_short(freeBytes)} free',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70)),
                    ],
                    if (_drawBar) ...[
                      const SizedBox(height: 13),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: share!.clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(children: [
                        _Legend(
                            filled: true,
                            text: 'Used ${(share * 100).round()}%'),
                        const SizedBox(width: 16),
                        _Legend(
                            filled: false,
                            text: 'Free ${(100 - share * 100).round()}%'),
                      ]),
                      if (tight) ...[
                        const SizedBox(height: 9),
                        // THE ONE TIME THIS NUMBER NEEDS ACTING ON. A bar that
                        // only ever decorates is a bar nobody reads when it
                        // matters.
                        Text(
                            'Your computer is nearly full — ${_short(freeBytes)} '
                            'left. New backups will start failing.',
                            style: const TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ],
                    ],
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.filled, required this.text});
  final bool filled;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: filled ? Colors.white : Colors.white38,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(text,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70)),
          ]);
}

/// "148 GB", "1.4 TB". Short enough to be a headline.
///
/// Deliberately coarser than the Storage screen's own formatter: this is a
/// thirty-point number read at a glance, and "147.83 GB" at that size is a
/// precision nobody asked for and a width that pushes "of 2 TB" off the row.
String _short(num bytes) {
  const step = 1024.0;
  if (bytes < step) return '$bytes B';
  var value = bytes / step;
  for (final unit in ['KB', 'MB', 'GB', 'TB', 'PB']) {
    if (value < step) {
      // One decimal below ten, none above — "9.4 GB" is useful, "94.2 GB" is
      // noise.
      final text =
          value < 10 ? value.toStringAsFixed(1) : value.round().toString();
      return '$text $unit';
    }
    value /= step;
  }
  return '${value.round()} PB';
}
