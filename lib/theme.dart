/// The web app's design system, transcribed.
///
/// The first version of this file invented a Material 3 theme from a seed colour
/// and looked nothing like SafeNest. These values are taken from
/// frontend/src/index.css rather than chosen — same purple, same radii, same
/// shadows, same per-module accents — so the two halves read as one product.
///
/// ONE THING WORTH KNOWING ABOUT THE BRAND COLOUR
/// `theme_color` from /api/branding is NOT the interface colour. It sets the
/// browser tab and the phone status bar; the CSS `--brand` is a fixed
/// #5b3df5 → #7c5cff purple and never changes. Driving the whole UI from the
/// branding colour would have made the phone app a different colour from the web
/// app on the same installation — which is precisely the mismatch this file
/// exists to remove.
library;

import 'package:flutter/material.dart';

/// --brand and --brand-2. Buttons are a gradient of the two, not a flat fill.
const kBrand = Color(0xFF5B3DF5);
const kBrand2 = Color(0xFF7C5CFF);

/// Light — :root
const _lightBg = Color(0xFFF4F5FB);       // --bg
const _lightElev = Color(0xFFFFFFFF);     // --bg-elev / --card
const _lightInk = Color(0xFF12132A);      // --ink
const _lightInkSoft = Color(0xFF5A5D78);  // --ink-soft
const _lightInkFaint = Color(0xFF9A9DB5); // --ink-faint
const _lightLine = Color(0xFFE7E8F2);     // --line

/// Dark — :root[data-theme='dark']
const _darkBg = Color(0xFF0D0E16);
const _darkElev = Color(0xFF171826);
const _darkInk = Color(0xFFF2F3FB);
const _darkInkSoft = Color(0xFFA7ABC7);
const _darkInkFaint = Color(0xFF6B6F8C);
const _darkLine = Color(0xFF262838);

const kOk = Color(0xFF16A06A);      // --ok
const kWarn = Color(0xFFE8A413);    // --warn
const kDanger = Color(0xFFE5484D);  // --danger

/// --radius and --radius-sm
const kRadius = 18.0;
const kRadiusSm = 12.0;

/// The per-module accents, exactly as the web app assigns them. These are what
/// make a list of modules recognisable at a glance, and inventing a second set
/// of colours for the phone would undo that.
const kModuleColours = <String, Color>{
  'loans': Color(0xFF6366F1),
  'cards': Color(0xFFEC4899),
  'insurance': Color(0xFF0EA5E9),
  'investments': Color(0xFF10B981),
  'expenses': Color(0xFFF59E0B),
  'reminders': Color(0xFF8B5CF6),
  'todos': Color(0xFF14B8A6),
  'gallery': Color(0xFFF43F5E),
  'vault': Color(0xFF64748B),
  'documents': Color(0xFF0D9488),
};

/// --shadow, as a Flutter box shadow.
List<BoxShadow> softShadow(bool dark) => [
      BoxShadow(
        color: dark
            ? Colors.black.withValues(alpha: 0.40)
            : const Color(0xFF18163C).withValues(alpha: 0.08),
        blurRadius: 24,
        offset: const Offset(0, 6),
      ),
    ];

/// The glow under a filled button — rgba(91, 61, 245, 0.32).
List<BoxShadow> brandGlow() => [
      BoxShadow(
        color: kBrand.withValues(alpha: 0.32),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];

class Brand {
  const Brand({
    this.name = 'SafeNest',
    this.shortName = 'SafeNest',
    this.tagline = '',
    this.iconUrl = '',
  });

  final String name;
  final String shortName;
  final String tagline;

  /// The icon the owner uploaded, served from their own machine. Used in-app;
  /// the launcher icon is baked in at build time and cannot follow it.
  final String iconUrl;

  static Brand fromJson(Map<String, dynamic> j) => Brand(
        name: (j['name'] ?? j['app_name'] ?? 'SafeNest') as String,
        shortName: (j['short_name'] ?? j['name'] ?? 'SafeNest') as String,
        tagline: (j['tagline'] ?? '') as String,
        iconUrl: (j['icon_url'] ?? '/branding/icon-192.png') as String,
      );
}

ThemeData buildTheme(Brand brand, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? _darkBg : _lightBg;
  final elev = dark ? _darkElev : _lightElev;
  final ink = dark ? _darkInk : _lightInk;
  final inkSoft = dark ? _darkInkSoft : _lightInkSoft;
  final inkFaint = dark ? _darkInkFaint : _lightInkFaint;
  final line = dark ? _darkLine : _lightLine;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: kBrand,
    onPrimary: Colors.white,
    primaryContainer: kBrand.withValues(alpha: dark ? 0.24 : 0.12),
    onPrimaryContainer: dark ? Colors.white : kBrand,
    secondary: kBrand2,
    onSecondary: Colors.white,
    error: kDanger,
    onError: Colors.white,
    surface: elev,
    onSurface: ink,
    surfaceContainerHighest: dark ? const Color(0xFF1F2133) : const Color(0xFFEDEEF6),
    onSurfaceVariant: inkSoft,
    outline: inkFaint,
    outlineVariant: line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,

    // -apple-system on iOS, Roboto on Android — which is what the CSS asks for
    // by naming the system stack. Flutter uses each platform's default already,
    // so naming a font here would make it LESS like the web app, not more.
    fontFamily: null,

    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: bg,          // the web top bar sits on the page, not on a card
      foregroundColor: ink,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),

    cardTheme: CardThemeData(
      color: elev,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
      clipBehavior: Clip.antiAlias,
    ),

    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),

    listTileTheme: ListTileThemeData(
      // .set-row: 52px min-height, 11px/14px padding, 15px type.
      minVerticalPadding: 11,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      titleTextStyle: TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w500),
      subtitleTextStyle: TextStyle(fontSize: 13, color: inkSoft),
      iconColor: inkSoft,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: elev,
      // .searchbar — 13px radius, a real 1px line, not Material's underline.
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: kBrand, width: 1.6),
      ),
      hintStyle: TextStyle(color: inkFaint, fontSize: 15),
      labelStyle: TextStyle(color: inkSoft, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),

    // .btn is a GRADIENT, which ThemeData cannot express — see BrandButton in
    // widgets/brand_button.dart. This styles the plain and outlined variants so
    // anything not using that widget is still the right shape and weight.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kBrand,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    // .seg4 button.on — brand fill, white text, and the same glow.
    tabBarTheme: TabBarThemeData(
      labelColor: kBrand,
      unselectedLabelColor: inkSoft,
      labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      indicator: UnderlineTabIndicator(
        borderSide: const BorderSide(color: kBrand, width: 2.5),
        borderRadius: BorderRadius.circular(2),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      height: 62,
      backgroundColor: elev,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: kBrand.withValues(alpha: dark ? 0.26 : 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? kBrand : inkFaint,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? kBrand : inkFaint,
          )),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kBrand,
      foregroundColor: Colors.white,
      elevation: 6,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: elev,
      selectedColor: kBrand,
      side: BorderSide(color: line),
      labelStyle: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(
          fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: elev,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: elev,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
    ),

    textTheme: TextTheme(
      headlineSmall: TextStyle(
          color: ink, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleMedium: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700),
      titleSmall: TextStyle(color: ink, fontSize: 14.5, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: ink, fontSize: 15),
      bodySmall: TextStyle(color: inkSoft, fontSize: 13, height: 1.45),
      labelSmall: TextStyle(color: inkFaint, fontSize: 12),
    ),
  );
}
