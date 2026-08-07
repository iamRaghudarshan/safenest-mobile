/// The person's own face, or their initials — `.avatar` and `.avatar-btn`.
///
/// The Dashboard header had a search button and nothing else. The web app has
/// this beside it, and it is the only thing on the screen that belongs to the
/// person rather than to their money: 40px, circular, their photo if they have
/// uploaded one and their initials on the brand gradient if not.
///
/// The initials fallback matters more than it looks. A grey silhouette is what
/// every app shows for somebody it knows nothing about, and this app knows their
/// name — using it is the difference between "your account" and "a user".
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.size = 40, this.onTap});
  final double size;
  final VoidCallback? onTap;

  /// First letters of the first two words — "Snehal Vasava" becomes SV. The web
  /// app computes the same thing server-side and calls it `initials`; this is
  /// the fallback for when that field is not in the payload.
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    final base = session.baseUrl ?? '';
    final name = '${user?['name'] ?? ''}';
    final initials = '${user?['initials'] ?? ''}'.isNotEmpty
        ? '${user!['initials']}'
        : _initials(name);
    final avatarUrl = '${user?['avatar_url'] ?? ''}';

    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // The same 135° brand gradient as a filled button, so the two read as
        // parts of one system rather than two purples that nearly match.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kBrand, kBrand2],
        ),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.35,
        ),
      ),
    );

    final content = avatarUrl.isEmpty
        ? fallback
        : ClipOval(
            child: Image.network(
              avatarUrl.startsWith('http') ? avatarUrl : '$base$avatarUrl',
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              // An unreachable computer should cost the photo, not the header.
              errorBuilder: (_, e, s) => fallback,
              loadingBuilder: (_, child, p) => p == null ? child : fallback,
            ),
          );

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: softShadow(Theme.of(context).brightness == Brightness.dark),
        ),
        child: content,
      ),
    );
  }
}
