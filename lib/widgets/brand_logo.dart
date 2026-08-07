/// The owner's own icon, wherever a logo belongs.
///
/// TWO SOURCES, IN THIS ORDER
///   1. Live, from their machine — /branding/icon-192.png. The desktop app lets
///      an admin rename and re-upload the icon, and a phone showing a stale one
///      would be the same half-rebranded result the web app was fixed for: the
///      login screen saying one thing and a notification an hour later saying
///      another.
///   2. The bundled copy, for the moment before anyone has signed in — the sign
///      -in screen needs a logo when there is no server to ask yet.
///
/// It never shows a generic placeholder. A shield icon from the Material set is
/// what this screen had before, and it made the app look like somebody else's.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 64, this.rounded = true});

  final double size;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final base = context.select<Session, String?>((s) => s.baseUrl);
    // A squircle, the way iOS and the web app both present it. A square icon
    // dropped on a screen reads as an asset that has not been styled.
    final radius = BorderRadius.circular(rounded ? size * 0.235 : 0);

    final bundled = Image.asset(
      'assets/icon-512.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: base == null || base.isEmpty
            ? bundled
            : Image.network(
                '$base/branding/icon-192.png',
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                // Falls back rather than showing a broken image. An unreachable
                // computer is common and ordinary; it should cost the live icon,
                // not the logo.
                errorBuilder: (_, e, s) => bundled,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : bundled,
              ),
      ),
    );
  }
}

/// Logo, name and tagline stacked — the sign-in screen's masthead.
class BrandMasthead extends StatelessWidget {
  const BrandMasthead({super.key, required this.brand, this.logoSize = 72});
  final Brand brand;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(logoSize * 0.235),
            boxShadow: brandGlow(),
          ),
          child: BrandLogo(size: logoSize),
        ),
        const SizedBox(height: 16),
        Text(brand.name,
            textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        if (brand.tagline.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(brand.tagline,
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
