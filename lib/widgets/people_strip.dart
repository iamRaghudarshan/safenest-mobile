/// The faces, along the top of the photo grid.
///
/// A FACE IS HOW PEOPLE LOOK FOR A PHOTOGRAPH. Not a date, not a folder, not
/// a filename — "the one of Anita at the beach". The app already knows who is
/// in each picture; until now that knowledge was three taps down, behind a
/// menu and a bottom sheet, which is the same as not having it. Somebody who
/// has never opened that menu does not know the feature exists.
///
/// Inline, it is also a statement about what this screen is: a library of
/// people and days, rather than a folder of files that happen to be images.
///
/// Shown in the Colourful skin only — not because Classic could not have it,
/// but because Classic is the look people already chose and adding a row to
/// the top of their photo grid is not a recolour.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class PeopleStrip extends StatelessWidget {
  const PeopleStrip({
    super.key,
    required this.people,
    required this.selected,
    required this.onToggle,
    this.onSeeAll,
    this.thumbUrl,
  });

  /// Everyone worth offering, already filtered by the caller — named people
  /// with a usable portrait. A strip full of "Person 12" is worse than no
  /// strip: it asks somebody to identify a stranger before it will help them.
  final List<Map<String, dynamic>> people;

  /// Which are currently narrowing the grid.
  final Set<int> selected;

  final void Function(Map<String, dynamic> person) onToggle;
  final VoidCallback? onSeeAll;

  /// Where a person's portrait comes from. Injected so this widget needs no
  /// session, no api and no knowledge of how URLs are signed — which is what
  /// lets it be rendered in a test with no server behind it.
  final String? Function(Map<String, dynamic> person)? thumbUrl;

  static const _max = 12;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final t = context.skin;
    final shown = people.take(_max).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
        child: Row(children: [
          Expanded(
            child: Text(
              // The heading says what a selection DOES, because the one thing
              // that surprises people is that picking a second face shows
              // fewer photographs, not more.
              selected.isEmpty
                  ? 'People'
                  : selected.length == 1
                      ? 'Photos of 1 person'
                      : 'Only photos with all ${selected.length} of them',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('See all',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: shown.length,
          separatorBuilder: (_, _) => const SizedBox(width: 13),
          itemBuilder: (_, i) {
            final person = shown[i];
            final id = (person['id'] as num?)?.toInt() ?? 0;
            final on = selected.contains(id);
            final name = '${person['name'] ?? ''}'.trim();
            final url = thumbUrl?.call(person);

            return Semantics(
              selected: on,
              button: true,
              label: name.isEmpty ? 'A person' : name,
              child: GestureDetector(
                onTap: () => onToggle(person),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 60,
                  child: Column(children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surfaceContainerHighest,
                        // The ring is the selected state, and it is drawn
                        // OUTSIDE the portrait rather than over it: a border
                        // on the circle itself eats into the face, which is
                        // the one part of this row that has to stay legible.
                        border: on
                            ? Border.all(color: t.brand, width: 2.5)
                            : null,
                      ),
                      child: ClipOval(
                        child: Padding(
                          padding: EdgeInsets.all(on ? 2.5 : 0),
                          child: ClipOval(
                            child: url == null || url.isEmpty
                                ? Icon(Icons.person,
                                    size: 26,
                                    color: theme.colorScheme.outline)
                                : Image.network(url,
                                    fit: BoxFit.cover,
                                    width: 56,
                                    height: 56,
                                    errorBuilder: (_, _, _) => Icon(
                                        Icons.person,
                                        size: 26,
                                        color: theme.colorScheme.outline)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      name.isEmpty ? 'Unnamed' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                        color: on ? t.brand : theme.colorScheme.onSurface,
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// Which people belong in the strip.
///
/// Named only, and with a portrait. Pure so the rule can be tested: it is the
/// difference between a row that helps and a row of strangers labelled
/// "Person 12", and it is easy to get subtly wrong when the server starts
/// returning a new shape.
List<Map<String, dynamic>> stripPeople(List<Map<String, dynamic>> all) {
  final unnamed = RegExp(r'^person\s*\d+$', caseSensitive: false);
  return [
    for (final p in all)
      if ('${p['name'] ?? ''}'.trim().isNotEmpty &&
          !unnamed.hasMatch('${p['name']}'.trim()) &&
          ((p['photo_count'] as num?)?.toInt() ?? 0) > 0)
        p,
  ];
}
