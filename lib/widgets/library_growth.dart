/// How the library is growing — the one place the app says so.
///
/// COUNTED FROM THE PHONE, not asked of the server, and that is the honest
/// source rather than a shortcut. The server has no photos-per-month endpoint,
/// and adding one would not help: it is the computer's copy, which lags a
/// backup. What somebody means by "added this month" is what they TOOK, and
/// that is exactly what the phone's own library knows.
///
/// The twelve bars are a shape, not a chart. There are no axes and no
/// gridlines because nobody reads a value off this — it answers "is my library
/// growing, and was this month busy" in one glance, and anything more precise
/// would be precision nobody asked for.
library;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';

/// Count the phone's photographs for each of the last [count] months, oldest
/// first.
///
/// One cheap count per month rather than one listing: `assetCountAsync` on a
/// filtered album asks the platform for a number and never materialises the
/// assets, which matters when the answer for one month can be four thousand
/// objects.
///
/// Returns an empty list when the library cannot be read — no permission, a
/// desktop, a test. An empty list hides the card, which is better than a row
/// of zeroes claiming somebody has taken no photographs in a year.
Future<List<int>> countByMonth({int count = 12, DateTime? now}) async {
  final end = now ?? DateTime.now();
  final out = <int>[];
  try {
    for (var i = count - 1; i >= 0; i--) {
      final from = DateTime(end.year, end.month - i, 1);
      final to = DateTime(end.year, end.month - i + 1, 1);
      final albums = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.common,
        filterOption: FilterOptionGroup(
          createTimeCond: DateTimeCond(min: from, max: to),
        ),
      );
      out.add(albums.isEmpty ? 0 : await albums.first.assetCountAsync);
    }
  } catch (_) {
    // A phone that will not answer is not a reason to fail the screen.
    return const [];
  }
  return out;
}

/// The change from last month, as a percentage. Null when there is nothing to
/// compare against — a first month has no trend, and "+100%" against zero is
/// arithmetic rather than information.
int? monthTrend(List<int> months) {
  if (months.length < 2) return null;
  final now = months.last;
  final before = months[months.length - 2];
  if (before == 0) return null;
  return (((now - before) / before) * 100).round();
}

class LibraryGrowth extends StatelessWidget {
  const LibraryGrowth({super.key, required this.months, this.storage});

  /// Oldest first. Fewer than two months hides the bars but keeps the figure.
  final List<int> months;

  /// "48.2 GB of 120 GB", where it is known.
  final String? storage;

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final t = context.skin;
    final thisMonth = months.last;
    final trend = monthTrend(months);
    // The tallest bar sets the scale. A fixed ceiling would flatten a quiet
    // year into nothing and clip a busy one.
    final peak = months.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ADDED THIS MONTH',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 3),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$thisMonth',
                        style: const TextStyle(
                            fontSize: 28,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    if (trend != null) ...[
                      const SizedBox(width: 8),
                      _Trend(percent: trend, ok: t.ok, down: t.module('reminders')),
                    ],
                  ]),
                ]),
          ),
          if (storage != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(storage!,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
        ]),
        if (months.length >= 2) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 46,
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < months.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(
                      child: FractionallySizedBox(
                        // A floor, so a month with nothing in it is still a
                        // mark on the chart rather than a gap that reads as
                        // missing data.
                        heightFactor: peak == 0
                            ? 0.06
                            : (months[i] / peak).clamp(0.06, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            // The newest month is the brand; the rest fade
                            // back, so the eye lands on now.
                            color: i == months.length - 1
                                ? t.brand
                                : t.brand.withValues(
                                    alpha: 0.18 + 0.22 * (i / months.length)),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                                bottom: Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ]),
          ),
          const SizedBox(height: 7),
          Text('the last ${months.length} months',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.outline)),
        ],
      ]),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.percent, required this.ok, required this.down});

  final int percent;
  final Color ok;
  final Color down;

  @override
  Widget build(BuildContext context) {
    // Up is not automatically good — this is a count of photographs, not a
    // score — so the colours say DIRECTION rather than approval, and a flat
    // month gets neither.
    final rising = percent > 0;
    final colour = percent == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (rising ? ok : down);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (percent != 0)
          Icon(rising ? Icons.arrow_upward : Icons.arrow_downward,
              size: 11, color: colour),
        if (percent != 0) const SizedBox(width: 3),
        Text('${percent.abs()}%',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: colour)),
      ]),
    );
  }
}
