// Does "Your computer" fit on the screen?
//
// It did not, and the way it failed is worth keeping: the old code clamped
// the label's X POSITION and never touched its size. That keeps the LEFT edge
// on the canvas and does nothing at all about the right one — once the text
// is wider than the space, the clamp bottoms out at x=2 and the rest runs off
// the edge. On a 390pt phone it cleared the edge by about four pixels, which
// is not fitting, it is luck, and any narrower phone spent it.
//
// Asserted numerically rather than by screenshot on purpose. `flutter test`
// ships no font, so these labels render as filled boxes whose widths are
// nothing like a real phone's — a render would have shown this "passing"
// either way. What is checked here is the RULE: whatever the font, the laid
// out width ends up inside its budget.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/widgets/backup_flight.dart';

/// Load a real system face, so one test can measure what a PHONE will do
/// rather than what the empty test font does. Returns false where no such
/// font exists, and that test then skips rather than asserting something
/// about a machine it is not running on.
Future<bool> useRealFont() async {
  for (final path in [
    r'C:\Windows\Fonts\segoeui.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    await (FontLoader('RealFace')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    return true;
  }
  return false;
}

/// The budget the painter gives each label: half the canvas, less a gutter.
/// Half, so the two labels can never meet in the middle either — the old
/// version let both grow towards each other and the only thing keeping them
/// apart was that English happens to make them short.
double budgetFor(double canvasWidth) => canvasWidth / 2 - 6;

/// The logical canvas width for a phone of [dp] points wide.
///
/// The scene is drawn against a 128pt design height and scaled to the 176pt
/// box, so every logical coordinate is divided by that factor — which is why
/// the label has far less room than the phone's width suggests, and why this
/// went wrong in the first place.
double canvasFor(double dp) {
  const padding = 36.0;   // the screen's 18pt gutters
  const heroPad = 36.0;   // the hero card's own 18pt gutters
  const k = 176.0 / 128.0;
  return (dp - padding - heroPad) / k;
}

void main() {
  const colour = Colors.white70;

  group('the device labels fit', () {
    // Every phone this app realistically runs on, narrowest first. The 320
    // is an iPhone SE in its smallest form and the one that used to overflow.
    for (final dp in <double>[320, 360, 375, 390, 414, 430]) {
      test('on a ${dp.toInt()}pt phone', () {
        final budget = budgetFor(canvasFor(dp));
        for (final text in ['This phone', 'Your computer']) {
          final pt = fitLabelPt(text, colour, budget);
          final w = layOutLabel(text, colour, pt).width;
          // EITHER it fits, OR it is already as small as it is allowed to
          // get. Both are correct outcomes and the second is deliberate:
          // unreadable type that fits is worse than readable type that is
          // tight, and the position clamp still keeps it on the canvas.
          //
          // Stated as a disjunction because the test font forces the second
          // branch. `flutter test` ships no real face, so every glyph is a
          // full em — around double a real font's average — and a string
          // that measures 68pt on a phone measures 136 here. Asserting the
          // width alone would be asserting a property of the test harness.
          expect(w <= budget + 0.01 || pt == kFlightLabelMinPt, isTrue,
              reason: '"$text" is ${w.toStringAsFixed(1)} wide at '
                  '${pt}pt in a ${budget.toStringAsFixed(1)} budget '
                  '(${dp.toInt()}pt phone)');
          expect(pt, lessThanOrEqualTo(kFlightLabelPt));
          expect(pt, greaterThanOrEqualTo(kFlightLabelMinPt));
        }
      });
    }

    test('a label that already fits is NOT shrunk', () {
      // The fix must not cost every phone a size it did not need to lose.
      // Given room to spare, the answer is the preferred size exactly.
      final pt = fitLabelPt('This phone', colour, 10000);
      expect(pt, kFlightLabelPt);
    });

    test('a much longer translation still fits', () {
      // "Your computer" is two words in English and can be five elsewhere.
      // Nothing here is English-specific, so this has to hold for any string.
      const long = 'Az Ön számítógépe otthon';
      final budget = budgetFor(canvasFor(360));
      final pt = fitLabelPt(long, colour, budget);
      final w = layOutLabel(long, colour, pt).width;
      expect(pt, lessThan(kFlightLabelPt), reason: 'it should have shrunk');
      expect(w <= budget + 0.01 || pt == kFlightLabelMinPt, isTrue);
    });

    test('it stops shrinking at the readable floor', () {
      // A string long enough that fitting it would make it illegible. The
      // label is allowed to touch the gutter instead — unreadable type that
      // fits is worse than readable type that is tight, and the position
      // clamp still keeps it on the canvas.
      final pt = fitLabelPt('x' * 400, colour, 20);
      expect(pt, kFlightLabelMinPt);
    });

    testWidgets('with a REAL font, the narrowest phone needs no shrinking',
        (tester) async {
      // The one measurement that answers the actual complaint. Everything
      // above proves the rule holds whatever the metrics; this asks what
      // happens with a face shaped like the one on the phone.
      //
      // It is the check that was missing: the old code cleared the edge of a
      // 390pt phone by about four pixels and nothing measured it, so "it
      // fits" was a look at a screenshot rather than a number.
      if (!await useRealFont()) {
        markTestSkipped('no system font on this machine to measure with');
        return;
      }
      TextPainter real(String s, double pt) => TextPainter(
            text: TextSpan(
                text: s,
                style: TextStyle(
                    fontFamily: 'RealFace',
                    fontSize: pt,
                    fontWeight: FontWeight.w700)),
            textDirection: TextDirection.ltr,
          )..layout();

      for (final dp in <double>[320, 360, 390]) {
        final budget = budgetFor(canvasFor(dp));
        for (final text in ['This phone', 'Your computer']) {
          final w = real(text, kFlightLabelPt).width;
          expect(w, lessThanOrEqualTo(budget),
              reason: '"$text" needs ${w.toStringAsFixed(1)} of a '
                  '${budget.toStringAsFixed(1)} budget on a ${dp.toInt()}pt '
                  'phone — it would have to shrink, which is allowed but '
                  'means the layout is tighter than intended');
        }
      }
    });

    test('a zero or negative budget does not divide by it', () {
      // Reachable during layout, when the canvas has no width yet. It must
      // return a size rather than a NaN that propagates into a paint call.
      for (final b in <double>[0, -1, -500]) {
        final pt = fitLabelPt('This phone', colour, b);
        expect(pt.isFinite, isTrue);
        expect(pt, kFlightLabelMinPt);
      }
    });
  });
}
