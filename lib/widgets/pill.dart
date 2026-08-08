/// `.pill` — the small tinted badge the web app uses everywhere.
///
/// It is the cheapest colour in the whole design system and the phone had none
/// of it. A pill is not a coloured rectangle: it is a 14–16% wash of a status
/// colour with the SAME colour used solid for the text, which keeps it readable
/// in both themes without a second palette. Flat-filling it would either be
/// shouting (solid red row) or invisible (grey on grey).
///
///   .pill        { padding: 4px 10px; border-radius: 999px; font: 700 12px; }
///   .pill.ok     { background: ok 15%;     colour: ok }
///   .pill.warn   { background: warn 16%;   colour: warn }
///   .pill.danger { background: danger 14%; colour: danger }
///   .pill.muted  { background: --bg;       colour: --ink-soft }
library;

import 'package:flutter/material.dart';

import '../theme.dart';

enum PillTone { ok, warn, danger, muted, brand }

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.tone = PillTone.muted, this.icon, this.colour});

  final String label;
  final PillTone tone;
  final IconData? icon;

  /// An explicit colour, for the module accents — the tones above cover status,
  /// but a reminder belonging to Cards should be pink, and that is not a status.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late final Color fg;
    late final Color bg;

    if (colour != null) {
      fg = colour!;
      bg = colour!.withValues(alpha: 0.15);
    } else {
      switch (tone) {
        case PillTone.ok:
          fg = kOk;
          bg = kOk.withValues(alpha: 0.15);
        case PillTone.warn:
          fg = kWarn;
          bg = kWarn.withValues(alpha: 0.16);
        case PillTone.danger:
          fg = kDanger;
          bg = kDanger.withValues(alpha: 0.14);
        case PillTone.brand:
          fg = kBrand;
          bg = kBrand.withValues(alpha: 0.14);
        case PillTone.muted:
          fg = theme.colorScheme.onSurfaceVariant;
          bg = theme.scaffoldBackgroundColor;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
        ],
        // Flexible, for the same reason BrandButton's label is: a bare Text in
        // a Row takes its natural width and OVERFLOWS rather than shrinking.
        // A pill is usually short, so this rarely shows — which is exactly why
        // it went unnoticed until one said "20431 could not be sent" and ran 19
        // pixels off an iPhone SE. One widget, so it was one bug everywhere a
        // pill is used.
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.2)),
        ),
      ]),
    );
  }
}
