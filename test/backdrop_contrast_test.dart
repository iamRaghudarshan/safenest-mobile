// Can the app still be read over somebody's own photograph?
//
// This is the test the first version of the background needed and did not
// have. The veil's strength was chosen by eye, it darkened the picture toward
// BLACK while every word in Classic is dark ink meant for a near-white page,
// and the result was reported as "words and font not visible properly" — which
// is exactly what it was.
//
// Legibility over an arbitrary picture is arithmetic, not taste: a photograph
// can be any colour, so the floor has to hold for the worst one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/customize.dart';
import 'package:safenest/theme.dart';

void main() {
  // Classic's body ink on its page colour.
  final light = buildTheme(const Brand(), Brightness.light);
  final dark = buildTheme(const Brand(), Brightness.dark);

  // The floor the BACKDROP enforces, which is per theme — not the absolute
  // bound on what may be saved.
  double atFloor(ThemeData t) => backdropContrast(
        ink: t.colorScheme.onSurface,
        surface: t.colorScheme.surface,
        alpha: readableVeil(
            ink: t.colorScheme.onSurface, surface: t.colorScheme.surface),
      );

  test('at the lowest veil allowed, body text is still readable', () {
    // 4.5:1 is the readable threshold for body text. The floor exists to
    // guarantee it against the worst photograph somebody could choose, not
    // against a pleasant one.
    final c = atFloor(light);
    expect(c, greaterThanOrEqualTo(4.5),
        reason: 'worst-case contrast at the light floor is '
            '${c.toStringAsFixed(2)}:1');
  });

  test('and in the dark theme too', () {
    // The veil is the SURFACE colour rather than black, so dark mode needs no
    // second rule — but that is a claim, and this is the check of it.
    final c = atFloor(dark);
    expect(c, greaterThanOrEqualTo(4.5),
        reason: 'dark mode worst case is ${c.toStringAsFixed(2)}:1');
  });

  test('the dark page needs more veil than the light one', () {
    // Not a curiosity — it is why the floor cannot be one number. A single
    // floor covering dark mode would wash the photograph out in light mode for
    // a reason that does not exist there.
    expect(readableVeilPercent(dark), greaterThan(readableVeilPercent(light)));
    expect(readableVeilPercent(light), lessThan(60));
  });

  test('a setting saved in one theme cannot break the other', () {
    // Somebody sets the least veil the light page allows, then switches to
    // dark. Enforcing the floor where the paint happens is what stops them
    // being left with an app they cannot read.
    final asked = readableVeil(
        ink: light.colorScheme.onSurface, surface: light.colorScheme.surface);
    final darkFloor = readableVeil(
        ink: dark.colorScheme.onSurface, surface: dark.colorScheme.surface);
    expect(asked, lessThan(darkFloor),
        reason: 'the case only exists if the light floor is the lower one');
    expect(
        backdropContrast(
            ink: dark.colorScheme.onSurface,
            surface: dark.colorScheme.surface,
            alpha: asked < darkFloor ? darkFloor : asked),
        greaterThanOrEqualTo(4.5));
  });

  test('the default is comfortably above the floor, not on it', () {
    final c = backdropContrast(
      ink: light.colorScheme.onSurface,
      surface: light.colorScheme.surface,
      alpha: Customize.dimDefault / 100,
    );
    expect(c, greaterThanOrEqualTo(atFloor(light)));
    expect(Customize.dimDefault / 100,
        greaterThan(readableVeil(
            ink: light.colorScheme.onSurface,
            surface: light.colorScheme.surface)));
  });

  test('a darkening veil would have failed this', () {
    // THE BUG, WRITTEN DOWN. Veiling toward black moves the ground away from
    // what dark ink needs. At the same strength it is unreadable, which is
    // why the direction — not the number — was the fault.
    final wrong = backdropContrast(
      ink: light.colorScheme.onSurface,
      surface: const Color(0xFF000000),
      alpha: Customize.dimDefault / 100,
    );
    expect(wrong, lessThan(4.5),
        reason: 'if this passes, the old version was not the problem');
  });

  test('turning the veil up cannot make things worse', () {
    // Monotonic: more veil is always more of the page colour, so contrast only
    // improves. If this ever fails the model is wrong somewhere.
    var previous = 0.0;
    for (var a = Customize.dimMin; a <= Customize.dimMax; a += 4) {
      final c = backdropContrast(
        ink: light.colorScheme.onSurface,
        surface: light.colorScheme.surface,
        alpha: a / 100,
      );
      expect(c, greaterThanOrEqualTo(previous - 0.001), reason: 'at $a%');
      previous = c;
    }
  });
}
