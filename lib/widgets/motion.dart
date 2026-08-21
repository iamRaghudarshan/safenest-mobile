/// Shared entrance motion, so screens arrive with one hand.
///
/// Content should not just appear — it should settle in: a short fade with a few
/// pixels of upward travel, staggered a little per item so a list assembles top
/// to bottom rather than blinking into place all at once. This is implicit
/// animation (no controller to own or dispose) and it honours "reduce motion" —
/// under that setting it renders the child immediately, still and complete.
library;

import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Fade + rise the child in. `index` staggers it — item 3 starts a little after
/// item 0 — so a column of cards flows in rather than flashing.
Widget stagger(BuildContext context, int index, Widget child) {
  // Accessibility first: no travel, no fade, just the content.
  if (MediaQuery.of(context).disableAnimations) return child;
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Motion.enter + Duration(milliseconds: 45 * index),
    curve: Motion.curve,
    builder: (_, t, c) => Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: c),
    ),
    child: child,
  );
}
