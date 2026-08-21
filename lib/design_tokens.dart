/// The measurements the UI is built from, in one place.
///
/// Before this, spacing and radii were hand-picked at each call site — a 13 here,
/// a 16 there — and a design system is exactly the promise that they are not. New
/// UI should reach for these, not a number. Colours live in `theme.dart`
/// (kBrand, kModuleColours, the status set); this file is geometry and motion.
library;

import 'package:flutter/animation.dart';

/// 8-pt spacing scale, with a 4 half-step for tight metadata rows.
class Space {
  Space._();
  static const double xs = 4; // between a label and its value
  static const double sm = 8; // between related controls
  static const double md = 14; // screen gutter, card padding
  static const double lg = 18; // between cards / sections
  static const double xl = 24; // major breaks, list end padding
}

/// Corner radii. `card` and `chip` mirror kRadius / kRadiusSm in theme.dart.
class Radii {
  Radii._();
  static const double card = 18;
  static const double chip = 12;
  static const double pill = 999;
  static const double tile = 13; // the rounded accent icon tiles on list rows
}

/// Motion timings and curves. Ambient is the slow background breath; enter is a
/// content card arriving; the curve is the one every transition shares so the app
/// moves with one hand.
class Motion {
  Motion._();
  static const Duration ambient = Duration(seconds: 6);
  static const Duration enter = Duration(milliseconds: 320);
  static const Duration quick = Duration(milliseconds: 180);
  static const Curve curve = Curves.easeOutCubic;
}
