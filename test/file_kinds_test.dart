// The kind row across the top of Files.
//
// It is four server-side filters made visible. What matters is that it stays
// four (a row of seven on a phone is a row nobody reads), that an uncounted
// kind shows a dash rather than a zero, and that tapping the chosen one
// clears it — a filter you can turn on and not off is a trap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/theme.dart';
import 'package:safenest/widgets/file_kinds.dart';

void main() {
  test('the four offered are all real server filters', () {
    // `ftype` on /api/documents knows pdf, image, doc, sheet, slides, archive
    // and the special "other". Offering a key the server does not know would
    // silently return everything, which looks like the filter did nothing.
    const serverKnows = {'pdf', 'image', 'doc', 'sheet', 'slides', 'archive', 'other'};
    for (final k in kFileKinds) {
      expect(serverKnows, contains(k.key));
    }
    expect(kFileKinds.length, 4,
        reason: 'four fit a phone; seven is a row nobody reads');
  });

  test('each kind has its own colour, and they differ', () {
    final t = SkinTokens.vivid;
    final seen = <int>{};
    for (final k in kFileKinds) {
      final c = fileKindColour(k.key, t);
      expect(seen.add(c.toARGB32()), isTrue,
          reason: '${k.key} shares a colour with another kind, so the row '
              'cannot be read at a glance');
    }
  });

  testWidgets('an uncounted kind shows a dash, never a zero', (tester) async {
    // "0 PDFs" while the request is in flight is a lie that corrects itself,
    // and it is the kind that stops somebody looking.
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
      home: Scaffold(
        body: FileKindBar(
          counts: const {'pdf': 86},
          selected: '',
          onPick: (_) {},
        ),
      ),
    ));
    expect(find.text('86'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('tapping the chosen one clears it', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
      home: Scaffold(
        body: FileKindBar(
          counts: const {'pdf': 86, 'image': 54, 'sheet': 31, 'other': 43},
          selected: 'pdf',
          onPick: (k) => picked = k,
        ),
      ),
    ));
    await tester.tap(find.text('PDFs'));
    expect(picked, '',
        reason: 'the row has to be its own way back out of a filter');
  });

  testWidgets('tapping another one switches to it', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid),
      home: Scaffold(
        body: FileKindBar(
          counts: const {'pdf': 86, 'sheet': 31},
          selected: 'pdf',
          onPick: (k) => picked = k,
        ),
      ),
    ));
    await tester.tap(find.text('Sheets'));
    expect(picked, 'sheet');
  });
}
