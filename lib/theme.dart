/// The look, taken from the web app so the two do not feel like different
/// products bought from different people.
///
/// The brand colour is fetched from the customer's own server at startup, not
/// hard-coded: SafeNest can be renamed and recoloured from its Administration
/// screen, and a phone app that ignored that would show one name on the laptop
/// and another in the hand. `/api/branding` is public and unauthenticated for
/// exactly this reason — the sign-in screen needs the name before anyone has
/// signed in.
library;

import 'package:flutter/material.dart';

class Brand {
  const Brand({
    this.name = 'SafeNest',
    this.shortName = 'SafeNest',
    this.tagline = '',
    this.seed = const Color(0xFF1656C6),
  });

  final String name;
  final String shortName;
  final String tagline;
  final Color seed;

  static Brand fromJson(Map<String, dynamic> j) {
    Color parse(String? hex) {
      if (hex == null || !hex.startsWith('#') || hex.length < 7) {
        return const Color(0xFF1656C6);
      }
      return Color(int.parse('FF${hex.substring(1, 7)}', radix: 16));
    }

    return Brand(
      name: (j['name'] ?? j['app_name'] ?? 'SafeNest') as String,
      shortName: (j['short_name'] ?? j['name'] ?? 'SafeNest') as String,
      tagline: (j['tagline'] ?? '') as String,
      seed: parse(j['theme_color'] as String?),
    );
  }
}

ThemeData buildTheme(Brand brand, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brand.seed,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        brightness == Brightness.dark ? const Color(0xFF0E1116) : const Color(0xFFF6F7F9),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
    ),
  );
}
