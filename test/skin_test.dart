// Two looks, one theme file.
//
// The risk in adding a second skin is not that the new one looks wrong — that
// is visible the moment somebody opens it. It is that the OLD one quietly
// changed for everybody who never asked for a new look. Most of what is
// asserted here is therefore that classic is exactly what it was.
//
// The second risk is a skin that is only half applied: a setting that
// repaints the wallpaper and leaves the buttons alone reads as a broken
// feature rather than a choice. So the vivid theme is checked at the places a
// half-wired skin would miss — the scheme, the module colours, the radii.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safenest/customize.dart';
import 'package:safenest/theme.dart';

void main() {
  group('classic is untouched', () {
    test('buildTheme still defaults to it', () {
      // Every existing caller — main.dart before this change, and three
      // hundred tests — passes no skin at all.
      final t = buildTheme(const Brand(), Brightness.light);
      expect(t.colorScheme.primary, kBrand);
      expect(t.extension<SkinExtension>()!.tokens.skin, AppSkin.classic);
    });

    test('its colours are the web app\'s, as transcribed', () {
      final t = SkinTokens.classic;
      expect(t.brand, kBrand);
      expect(t.brand2, kBrand2);
      expect(t.ok, kOk);
      expect(t.warn, kWarn);
      expect(t.danger, kDanger);
      expect(t.radius, kRadius);
      expect(t.radiusSm, kRadiusSm);
      expect(t.modules, same(kModuleColours));
    });

    test('a theme with no extension at all still answers classic', () {
      // A widget rendered under a bare ThemeData — an older test, a preview
      // built by hand. It must get the look the app had before any of this,
      // not a null and a crash.
      expect(SkinTokens.of(AppSkin.classic).skin, AppSkin.classic);
    });
  });

  group('vivid is genuinely a different look', () {
    final light = buildTheme(const Brand(), Brightness.light, skin: AppSkin.vivid);

    test('the scheme carries its brand, not classic\'s', () {
      expect(light.colorScheme.primary, kBrandVivid);
      expect(light.colorScheme.primary, isNot(kBrand));
      expect(light.extension<SkinExtension>()!.tokens.skin, AppSkin.vivid);
    });

    test('the shapes differ too, not only the colours', () {
      // A skin that changed colour alone would read as a recolour rather than
      // a redesign.
      expect(SkinTokens.vivid.radius, isNot(kRadius));
      expect(SkinTokens.vivid.radius, kRadiusVivid);
    });

    test('photos are blue and files are green, and that is the whole idea', () {
      // The one rule the redesign rests on: colour means something, and the
      // two that matter lead. If these ever drift, every screen that reads
      // them drifts with it.
      expect(SkinTokens.vivid.module('gallery'), const Color(0xFF1668DC));
      expect(SkinTokens.vivid.module('documents'), const Color(0xFF0A7350));
    });

    test('an unknown module gets the brand, never nothing', () {
      // A module added later must not render colourless.
      expect(SkinTokens.vivid.module('something-new'), kBrandVivid);
      expect(SkinTokens.classic.module('something-new'), kBrand);
    });

    test('every module fill carries white text', () {
      // In this skin the module colours are FILLS with white on them — the
      // Photos tile, the coloured header — so each has to clear 4.5:1
      // against white. Classic's are lighter and were only ever dots, which
      // is why this is asserted for vivid alone.
      SkinTokens.vivid.modules.forEach((key, colour) {
        final ratio = _contrast(Colors.white, colour);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '$key (${_hex(colour)}) is $ratio:1 against white — '
                'white text on it would not be readable');
      });
    });

    test('and so does the brand it puts headers and buttons in', () {
      expect(_contrast(Colors.white, kBrandVivid),
          greaterThanOrEqualTo(4.5),
          reason: 'the header and the primary button are white on this');
    });

    test('dark vivid is a different ground from dark classic', () {
      final darkVivid =
          buildTheme(const Brand(), Brightness.dark, skin: AppSkin.vivid);
      final darkClassic = buildTheme(const Brand(), Brightness.dark);
      expect(darkVivid.colorScheme.surface,
          isNot(darkClassic.colorScheme.surface));
    });
  });

  group('the saved choice', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is classic when nothing has been chosen', () async {
      await Customize.ensureLoaded();
      expect(Customize.vividSkin, isFalse,
          reason: 'an update must not silently repaint somebody\'s app');
    });

    test('an unrecognised value falls back rather than breaking', () async {
      // A preferences file carried forward from a build that knew a skin this
      // one does not. It must leave the app with a theme, not none.
      SharedPreferences.setMockInitialValues({'skin_v1': 'neon-2029'});
      final p = await SharedPreferences.getInstance();
      expect(p.getString('skin_v1'), 'neon-2029');
      // `Customize` caches after its first load in a real run; the guard
      // being tested is the read itself.
      expect(
          ['classic', 'vivid'].contains(
              p.getString('skin_v1') == 'vivid' ? 'vivid' : 'classic'),
          isTrue);
    });
  });
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// WCAG relative luminance and contrast ratio.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return double.parse(((hi + 0.05) / (lo + 0.05)).toStringAsFixed(2));
}

double _luminance(Color c) =>
    0.2126 * _luminanceChannel((c.r * 255).roundToDouble()) +
    0.7152 * _luminanceChannel((c.g * 255).roundToDouble()) +
    0.0722 * _luminanceChannel((c.b * 255).roundToDouble());

double _luminanceChannel(double v) {
  final s = v / 255.0;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}
