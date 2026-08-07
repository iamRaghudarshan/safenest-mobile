/// The web app's `.btn`, which no Flutter button theme can express.
///
///     background: linear-gradient(135deg, var(--brand), var(--brand-2));
///     border-radius: 14px; font-weight: 700; font-size: 15px;
///     box-shadow: 0 8px 20px rgba(91, 61, 245, 0.32);
///
/// ThemeData takes a single background colour, so a FilledButton can only ever
/// be a flat purple — close, and visibly not the same. This is the actual thing:
/// the gradient, the radius, the weight and the glow beneath it.
///
/// `.btn.ghost` is the quiet variant. Note there is no `.btn.primary` in the CSS
/// — `.btn` is already the filled style, and inventing a third here would put
/// the phone out of step with a stylesheet that deliberately has two.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.ghost = false,
    this.busy = false,
    this.block = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// `.btn.ghost` — the quiet one.
  final bool ghost;
  final bool busy;

  /// `.btn.block` — full width, which is the default on a phone.
  final bool block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null && !busy;

    if (ghost) {
      return SizedBox(
        width: block ? double.infinity : null,
        child: OutlinedButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 19),
          label: Text(label),
        ),
      );
    }

    return Opacity(
      // Dimmed rather than greyed: a gradient has no disabled colour, and going
      // flat grey would make a busy button look like a different control.
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            // 135deg in CSS starts top-left and runs to bottom-right.
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kBrand, kBrand2],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled ? brandGlow() : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: block ? double.infinity : null,
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              child: Row(
                mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  else ...[
                    if (icon != null) ...[
                      Icon(icon, size: 19, color: Colors.white),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The web app's `.card` — 18px radius, soft shadow, 16px padding, no border.
class BrandCard extends StatelessWidget {
  const BrandCard({super.key, required this.child, this.padding, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: softShadow(dark),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The web app's `.seg4` — a pill of segments on a card, the selected one filled
/// with the brand colour and carrying the same glow. Used instead of a Material
/// TabBar where the web app uses segments, so the two look alike.
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // Five segments share the width of four, so the type tightens rather than
    // letting a word wrap or clip — the same rule as `.seg4.five`.
    final tight = labels.length >= 5;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
        boxShadow: softShadow(dark),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(
                      vertical: 9, horizontal: tight ? 2 : 6),
                  decoration: BoxDecoration(
                    color: i == index ? kBrand : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == index
                        ? [
                            BoxShadow(
                              color: kBrand.withValues(alpha: 0.30),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: tight ? 12 : 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: tight ? -0.2 : 0,
                      color: i == index
                          ? Colors.white
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
