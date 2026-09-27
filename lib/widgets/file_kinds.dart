/// What kind of file, as four coloured counts across the top of Files.
///
/// PEOPLE ASK FOR "THE INSURANCE PDF", not "the file in the second folder".
/// The kind is the fastest thing to scan for and the only property of a
/// document that is obvious before you open it, so it gets the colour and the
/// top of the screen. Categories answer a different question — what the
/// document is ABOUT — and they are still there below.
///
/// Every filter here is one the server already applies (`ftype`), so tapping
/// one narrows the real query rather than filtering a page that happens to be
/// loaded.
///
/// Colourful only: Classic is the look people already chose, and a new row
/// across the top of their documents is not a recolour.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The four offered, in the order they are worth scanning.
///
/// Four and not seven. The server knows slides and archives too, but a row of
/// seven on a phone is a row nobody reads — and between them they are a
/// rounding error in a real library, so they live in "Other" where the count
/// still finds them.
const kFileKinds = <({String key, String label})>[
  (key: 'pdf', label: 'PDFs'),
  (key: 'image', label: 'Scans'),
  (key: 'sheet', label: 'Sheets'),
  (key: 'other', label: 'Other'),
];

/// The colour for a kind, from the skin, so Files agrees with everywhere else
/// a file of that kind is drawn.
Color fileKindColour(String key, SkinTokens t) {
  switch (key) {
    case 'pdf':
      return t.danger;
    case 'image':
      return t.brand;
    case 'sheet':
      return t.ok;
    default:
      return t.module('notes');
  }
}

class FileKindBar extends StatelessWidget {
  const FileKindBar({
    super.key,
    required this.counts,
    required this.selected,
    required this.onPick,
  });

  /// Kind key to how many. A key that is absent has not been counted yet and
  /// shows a dash — NOT a zero. "0 PDFs" while the request is in flight is a
  /// lie that corrects itself, and it is the kind that stops somebody looking.
  final Map<String, int> counts;

  /// The kind currently narrowing the list, or '' for all.
  final String selected;

  final void Function(String key) onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.skin;
    return Row(children: [
      for (var i = 0; i < kFileKinds.length; i++) ...[
        if (i > 0) const SizedBox(width: 9),
        Expanded(
          child: _KindTile(
            label: kFileKinds[i].label,
            count: counts[kFileKinds[i].key],
            colour: fileKindColour(kFileKinds[i].key, t),
            on: selected == kFileKinds[i].key,
            // Tapping the one already chosen clears it, so the row is its own
            // way back. A filter you can turn on and not off is a trap.
            onTap: () => onPick(
                selected == kFileKinds[i].key ? '' : kFileKinds[i].key),
          ),
        ),
      ],
    ]);
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.label,
    required this.count,
    required this.colour,
    required this.on,
    required this.onTap,
  });

  final String label;
  final int? count;
  final Color colour;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.skin;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A tint of the kind's colour, not the colour itself: four saturated
    // blocks across the top would out-shout the documents underneath, which
    // are the point of the screen. The selected one fills in.
    final fill = on
        ? colour
        : colour.withValues(alpha: dark ? 0.22 : 0.11);
    final ink = on ? Colors.white : (dark ? Colors.white : colour);

    return Semantics(
      selected: on,
      button: true,
      label: '$label, ${count ?? 'not counted yet'}',
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(t.radiusSm + 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.radiusSm + 2),
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  count == null ? '—' : '$count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: ink,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w700, color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
