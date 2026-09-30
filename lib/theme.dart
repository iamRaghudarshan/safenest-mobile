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
/// #0176D3 → #1B96FF Salesforce-style blue and never changes. Driving the whole
/// UI from the branding colour would have made the phone app a different colour
/// from the web app on the same installation — which is precisely the mismatch
/// this file exists to remove. Kept in step with the web `--brand`/`--brand-2`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';  // SystemUiOverlayStyle on the app bar

/// --brand and --brand-2. Buttons are a gradient of the two, not a flat fill.
const kBrand = Color(0xFF0176D3);
const kBrand2 = Color(0xFF1B96FF);

/// Light — :root
const _lightBg = Color(0xFFF4F5FB);       // --bg
const _lightElev = Color(0xFFFFFFFF);     // --bg-elev / --card
const _lightInk = Color(0xFF12132A);      // --ink
// Darkened so secondary text (dates, captions, hints) reads clearly instead of a
// faint grey. Kept in step with the web --ink-soft / --ink-faint.
const _lightInkSoft = Color(0xFF34364E);  // --ink-soft
const _lightInkFaint = Color(0xFF5A5D78); // --ink-faint
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

// ───────────────────────── the second look ──────────────────────────────
//
// THE APP HAS TWO SKINS NOW, and this is the only file that knows the
// difference. `classic` is everything above: the web app's palette,
// transcribed, so the phone and the browser read as one product. `vivid` is
// the redesign, where colour carries MEANING rather than decoration — one hue
// per module, in the same place every time, so people navigate by colour
// without reading labels.
//
// Classic stays the default. An update that silently repaints somebody's app
// is a shock rather than a feature; this one is reached by choosing it in
// Profile → Personalise.
//
// What a skin may change is deliberately narrow: colour, shape and weight. It
// does NOT change the typeface, because the app bundles no fonts and adding
// one is a few hundred kilobytes in every download — a real cost, and a
// separate decision from picking a palette.

/// Vivid's ground and ink. Cooler and brighter than classic's.
const _vividBg = Color(0xFFF5F7FC);
const _vividElev = Color(0xFFFFFFFF);
const _vividInk = Color(0xFF10131C);
const _vividInkSoft = Color(0xFF3B4254);
const _vividInkFaint = Color(0xFF5A6275);
const _vividLine = Color(0xFFE4E8F0);

const _vividDarkBg = Color(0xFF0B0D11);
const _vividDarkElev = Color(0xFF161A22);
const _vividDarkInk = Color(0xFFF2F4F7);
const _vividDarkInkSoft = Color(0xFFB4BCCA);
const _vividDarkInkFaint = Color(0xFF7A8598);
const _vividDarkLine = Color(0xFF232935);

/// A deeper blue than classic's #0176D3, and the reason is contrast rather
/// than taste: vivid puts white text and white icons ON the brand colour —
/// the home header, the primary button, the Photos tile — and #0176D3 carries
/// white at about 3.4:1, under the 4.5:1 that body-sized text needs. #1559C0
/// clears it.
const kBrandVivid = Color(0xFF1559C0);
const kBrandVivid2 = Color(0xFF1668DC);

const _vividOk = Color(0xFF0A7350);
const _vividWarn = Color(0xFF9A5B08);
const _vividDanger = Color(0xFFB3261E);

/// Vivid's module hues. The two that matter lead: PHOTOS is blue and FILES is
/// green, everywhere, without exception — the tile on Home, the tab, the chip
/// on a search result, the segment of the storage bar.
///
/// Every one of these carries white text at 4.5:1 or better, because in this
/// skin they are used as FILLS and not only as dots. Classic's accents are
/// lighter and were never asked to do that.
const kModuleColoursVivid = <String, Color>{
  'gallery': Color(0xFF1668DC),     // photos — the first of the two
  'documents': Color(0xFF0A7350),   // files — the second
  'expenses': Color(0xFF9A5B08),
  'reminders': Color(0xFFAE1250),
  'notes': Color(0xFF5B2FC4),
  'vault': Color(0xFF10459A),
  'habits': Color(0xFF00676F),
  'todos': Color(0xFF0E7490),
  'loans': Color(0xFF4A24AD),
  'cards': Color(0xFFA81B62),
  'insurance': Color(0xFF0B6CA8),
  'investments': Color(0xFF0A7350),
};

const kRadiusVivid = 20.0;
const kRadiusVividSm = 14.0;

/// Which look the app is wearing.
enum AppSkin { classic, vivid }

/// Everything a skin decides, in one object, so no screen has to ask "which
/// skin am I?" — it asks the theme for a colour and gets the right one.
class SkinTokens {
  const SkinTokens({
    required this.skin,
    required this.brand,
    required this.brand2,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.radius,
    required this.radiusSm,
    required this.modules,
  });

  final AppSkin skin;
  final Color brand;
  final Color brand2;
  final Color ok;
  final Color warn;
  final Color danger;
  final double radius;
  final double radiusSm;
  final Map<String, Color> modules;

  bool get isVivid => skin == AppSkin.vivid;

  /// A module's colour in the current skin, falling back to the brand for a
  /// module neither map names — a new module must never render colourless.
  Color module(String key) => modules[key] ?? brand;

  static const classic = SkinTokens(
    skin: AppSkin.classic,
    brand: kBrand,
    brand2: kBrand2,
    ok: kOk,
    warn: kWarn,
    danger: kDanger,
    radius: kRadius,
    radiusSm: kRadiusSm,
    modules: kModuleColours,
  );

  static const vivid = SkinTokens(
    skin: AppSkin.vivid,
    brand: kBrandVivid,
    brand2: kBrandVivid2,
    ok: _vividOk,
    warn: _vividWarn,
    danger: _vividDanger,
    radius: kRadiusVivid,
    radiusSm: kRadiusVividSm,
    modules: kModuleColoursVivid,
  );

  static SkinTokens of(AppSkin skin) =>
      skin == AppSkin.vivid ? vivid : classic;
}

/// The skin a widget is being built under.
///
/// Carried as a ThemeExtension rather than read from `Customize` at the point
/// of use, and that is the whole point: a widget asks the THEME it was handed,
/// so a test can render either look without touching global state, and a
/// preview of one skin inside a screen drawn in the other is a plain
/// `Theme(data: ...)` wrapper instead of a special case.
class SkinExtension extends ThemeExtension<SkinExtension> {
  const SkinExtension(this.tokens);

  final SkinTokens tokens;

  @override
  SkinExtension copyWith({SkinTokens? tokens}) =>
      SkinExtension(tokens ?? this.tokens);

  /// Skins do not cross-fade: a half-classic, half-vivid frame is not a look
  /// anybody chose. It flips at the midpoint.
  @override
  SkinExtension lerp(ThemeExtension<SkinExtension>? other, double t) {
    if (other is! SkinExtension) return this;
    return t < 0.5 ? this : other;
  }
}

/// The skin in force, for any widget with a BuildContext.
///
/// Never null: a theme built without the extension (an older test, a widget
/// rendered under a bare ThemeData) answers classic, which is what the app
/// looked like before any of this existed.
extension SkinAccess on BuildContext {
  SkinTokens get skin =>
      Theme.of(this).extension<SkinExtension>()?.tokens ?? SkinTokens.classic;
}

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
  'habits': Color(0xFFF97316),
  'gallery': Color(0xFFF43F5E),
  'vault': Color(0xFF64748B),
  'documents': Color(0xFF0D9488),
  'notes': Color(0xFFF5B301),
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
///
/// Takes the colour rather than reading the constant, so the glow under a
/// button matches the button. Defaults to classic's, which is what every
/// existing caller meant.
List<BoxShadow> brandGlow([Color colour = kBrand]) => [
      BoxShadow(
        color: colour.withValues(alpha: 0.32),
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

/// [skin] defaults to classic so every existing caller — and every one of the
/// three hundred tests that builds a theme — keeps the app it already had.
/// Only main.dart passes the other one, from the saved preference.
/// The worst contrast body text can have over a veiled photograph.
///
/// WHY THIS IS ARITHMETIC AND NOT A JUDGEMENT. The background setting lets
/// somebody put ANY picture behind the whole app — a black-and-white night
/// shot, a white wall — and Classic's words are dark ink drawn for a
/// near-white page. Whether they can still be read is a number, and picking
/// the veil's floor by eye is how the first version shipped unreadable.
///
/// The veil is [surface] at [alpha], so the ground under the text is
///   result = alpha * surface + (1 - alpha) * photo
/// and the worst case is whichever of black or white the photograph could be.
/// Returns the smaller of the two contrast ratios; 4.5 is the readable
/// threshold for body text.
double backdropContrast({
  required Color ink,
  required Color surface,
  required double alpha,
}) {
  double ratio(Color photo) {
    final ground = Color.lerp(photo, surface, alpha)!;
    final a = ink.computeLuminance();
    final b = ground.computeLuminance();
    final hi = a > b ? a : b;
    final lo = a > b ? b : a;
    return (hi + 0.05) / (lo + 0.05);
  }

  final dark = ratio(const Color(0xFF000000));
  final light = ratio(const Color(0xFFFFFFFF));
  return dark < light ? dark : light;
}

/// The least veil that still lets body text be read over ANY photograph.
///
/// Computed rather than chosen, and computed PER THEME rather than once: the
/// light page needs 50% to reach 4.5:1 against a black picture, the dark page
/// needs 63% against a white one. A single floor covering both would wash the
/// photograph out in light mode for a reason that only exists in dark mode.
///
/// Memoised because it is asked for on every build of the app shell, and the
/// answer only changes when the theme does.
final Map<int, double> _veilCache = {};

double readableVeil({required Color ink, required Color surface}) {
  final key = Object.hash(ink.toARGB32(), surface.toARGB32());
  final had = _veilCache[key];
  if (had != null) return had;
  var a = 0.30;
  while (a < 0.96) {
    if (backdropContrast(ink: ink, surface: surface, alpha: a) >= 4.5) break;
    a += 0.01;
  }
  // Rounded up to the nearest whole percent so it lines up with a slider that
  // moves in percents — a floor of 0.503 that the slider cannot express is a
  // floor that is silently crossed.
  final out = (a * 100).ceilToDouble() / 100;
  _veilCache[key] = out;
  return out;
}

/// The same, as the percentage the settings screen shows.
int readableVeilPercent(ThemeData theme) => (readableVeil(
              ink: theme.colorScheme.onSurface,
              surface: theme.colorScheme.surface,
            ) *
            100)
        .round();

/// A button that may sit in a Row: as wide as its label and no wider.
///
/// The button themes above set a minimum width of infinity so that buttons
/// fill the page, which is right in a Column and fatal in a Row — see the note
/// beside `filledButtonTheme`. This cancels it, and it is the whole fix.
///
/// Use it for any FilledButton or OutlinedButton whose parent is a Row.
final ButtonStyle compactButtonStyle = ButtonStyle(
  minimumSize: WidgetStateProperty.all(const Size(0, 38)),
  padding:
      WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)),
);

ThemeData buildTheme(Brand brand, Brightness brightness,
    {AppSkin skin = AppSkin.classic}) {
  final dark = brightness == Brightness.dark;
  final t = SkinTokens.of(skin);
  final vivid = t.isVivid;

  final bg = vivid
      ? (dark ? _vividDarkBg : _vividBg)
      : (dark ? _darkBg : _lightBg);
  final elev = vivid
      ? (dark ? _vividDarkElev : _vividElev)
      : (dark ? _darkElev : _lightElev);
  final ink = vivid
      ? (dark ? _vividDarkInk : _vividInk)
      : (dark ? _darkInk : _lightInk);
  final inkSoft = vivid
      ? (dark ? _vividDarkInkSoft : _vividInkSoft)
      : (dark ? _darkInkSoft : _lightInkSoft);
  final inkFaint = vivid
      ? (dark ? _vividDarkInkFaint : _vividInkFaint)
      : (dark ? _darkInkFaint : _lightInkFaint);
  final line = vivid
      ? (dark ? _vividDarkLine : _vividLine)
      : (dark ? _darkLine : _lightLine);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.brand,
    onPrimary: Colors.white,
    primaryContainer: t.brand.withValues(alpha: dark ? 0.24 : 0.12),
    onPrimaryContainer: dark ? Colors.white : t.brand,
    secondary: t.brand2,
    onSecondary: Colors.white,
    error: t.danger,
    onError: Colors.white,
    surface: elev,
    onSurface: ink,
    surfaceContainerHighest: vivid
        ? (dark ? const Color(0xFF212733) : const Color(0xFFEBEEF5))
        : (dark ? const Color(0xFF1F2133) : const Color(0xFFEDEEF6)),
    onSurfaceVariant: inkSoft,
    outline: inkFaint,
    outlineVariant: line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    // The skin travels WITH the theme, so `context.skin` answers correctly
    // anywhere below a MaterialApp — including inside a Theme() override,
    // which is how one skin gets previewed while the app wears the other.
    extensions: <ThemeExtension<dynamic>>[SkinExtension(t)],
    // Transparent so the app-wide NatureBackdrop (mounted in main.dart via
    // MaterialApp.builder) shows behind every screen. Cards, app bars and sheets
    // keep their own opaque surfaces, so content stays legible over the scene.
    // COLOURFUL HAS A GROUND OF ITS OWN.
    //
    // Classic is transparent so the app-wide backdrop — the nature scene,
    // mounted in main.dart — shows through every screen. Colourful is built
    // on a flat, cool, near-white page with saturated blocks on it, and a
    // photograph behind that fights every one of them: the coloured header
    // stops reading as a header and starts reading as another picture.
    //
    // So this skin paints its own page. The backdrop setting still exists and
    // still applies to Classic; it simply has nothing to show through here.
    scaffoldBackgroundColor: vivid ? bg : Colors.transparent,

    // -apple-system on iOS, Roboto on Android — which is what the CSS asks for
    // by naming the system stack. Flutter uses each platform's default already,
    // so naming a font here would make it LESS like the web app, not more.
    fontFamily: null,

    // THE APP BAR IS WHAT MAKES A SKIN REACH EVERY SCREEN.
    //
    // The redesign was hand-built on six screens and the other thirty kept
    // Classic's plain bar, which is worse than not having a skin at all: an
    // app that changes appearance depending on which page you are on reads as
    // broken rather than as themed. Almost every screen in this app has an
    // AppBar and almost none of them style it, so one entry here is the
    // difference between six screens and all of them.
    //
    // Filled with the brand colour, white on it, no elevation. That is the
    // coloured head from the design, applied by inheritance.
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: vivid ? t.brand : bg,
      foregroundColor: vivid ? Colors.white : ink,
      iconTheme: IconThemeData(color: vivid ? Colors.white : ink),
      actionsIconTheme: IconThemeData(color: vivid ? Colors.white : ink),
      titleTextStyle: TextStyle(
        color: vivid ? Colors.white : ink,
        fontSize: vivid ? 20 : 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      systemOverlayStyle:
          vivid ? SystemUiOverlayStyle.light : null,
      shape: vivid
          ? const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(22)))
          : null,
    ),

    cardTheme: CardThemeData(
      color: elev,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        // A hairline in Colourful, because its cards sit on a light cool
        // ground where a white card with no edge simply disappears. Classic's
        // ground is warmer and its cards carry a shadow instead.
        side: vivid
            ? BorderSide(color: line)
            : BorderSide.none,
      ),
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
      // WHITE, WITH A HAIRLINE — in both skins.
      //
      // The first attempt filled Colourful's fields with the page colour,
      // reasoning that a white field on a white card needs an outline to
      // exist. It does, but that is the rare case: most screens put a search
      // box straight onto the PAGE, and there a page-coloured field with no
      // border is invisible. Rendering an ordinary screen showed a search box
      // that simply was not there.
      //
      // A raised fill with a hairline reads on both — on the page it lifts,
      // on a card the line holds it.
      fillColor: elev,
      // .searchbar — 13px radius, a real 1px line, not Material's underline.
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(vivid ? 15 : 13),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(vivid ? 15 : 13),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(vivid ? 15 : 13),
        borderSide: BorderSide(color: t.brand, width: vivid ? 1.8 : 1.6),
      ),
      hintStyle: TextStyle(color: inkFaint, fontSize: 15),
      labelStyle: TextStyle(color: inkSoft, fontSize: 14),
      contentPadding: EdgeInsets.symmetric(
          horizontal: vivid ? 16 : 14, vertical: vivid ? 16 : 14),
    ),

    // .btn is a GRADIENT, which ThemeData cannot express — see BrandButton in
    // widgets/brand_button.dart. This styles the plain and outlined variants so
    // anything not using that widget is still the right shape and weight.
    //
    // ⚠ `Size.fromHeight(h)` IS `Size(double.infinity, h)` — A MINIMUM WIDTH OF
    // INFINITY. That is deliberate: it makes every button a block button that
    // fills the page, which is what nearly every screen here wants and relies
    // on. But a Row lays its non-flexible children out with UNBOUNDED width, so
    // a button dropped into a Row asks for infinity. In debug that throws
    // "BoxConstraints forces an infinite width"; in a release build there is no
    // message at all — the Expanded beside it is simply starved to nothing, and
    // what ships is a card with its text set one character per line.
    //
    // That shipped. A button in a Row must pass `compactButtonStyle`.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.brand,
        foregroundColor: Colors.white,
        minimumSize: Size.fromHeight(vivid ? 54 : 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(vivid ? 16 : 14)),
        textStyle:
            TextStyle(fontSize: vivid ? 15.5 : 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: vivid ? elev : null,
        minimumSize: Size.fromHeight(vivid ? 52 : 48),
        side: BorderSide(color: line, width: vivid ? 1.5 : 1),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(vivid ? 16 : 14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.brand,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    // .seg4 button.on — brand fill, white text, and the same glow.
    tabBarTheme: TabBarThemeData(
      labelColor: t.brand,
      unselectedLabelColor: inkSoft,
      labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: t.brand, width: 2.5),
        borderRadius: BorderRadius.circular(2),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      height: 62,
      backgroundColor: elev,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: t.brand.withValues(alpha: dark ? 0.26 : 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? t.brand : inkFaint,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? t.brand : inkFaint,
          )),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.brand,
      foregroundColor: Colors.white,
      elevation: 6,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: elev,
      selectedColor: t.brand,
      side: BorderSide(color: line),
      labelStyle: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(
          fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(vivid ? 999 : 10)),
      padding: vivid
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 8)
          : null,
    ),

    // Sheets and dialogs are where a skin is most often forgotten, and they
    // are half the app: every picker, every confirm, every "why did this
    // fail" lives in one. Left at Classic's radius they are the seam where
    // Colourful visibly stops.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: elev,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(vivid ? 26 : 20)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: elev,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius)),
    ),

    // THE WHOLE SCALE, not six of fifteen.
    //
    // Only headlineSmall, titleMedium, titleSmall, bodyMedium, bodySmall and
    // labelSmall were set. Everything else fell through to Material 3's own
    // type scale, which is a different design: it puts letterSpacing of +0.5 on
    // bodyLarge and the label styles, and uses w400 where this app's headings
    // are bold. So a screen built from titleMedium looked like this app and the
    // one beside it, built from titleLarge or labelLarge, looked like a stock
    // Material demo — loosely spaced and a shade too light.
    //
    // Mixed type is the kind of wrong that is obvious and hard to name, which
    // is why it reads as "the fonts look bad" rather than as any one bug.
    //
    // No font FAMILY is named, deliberately — see fontFamily above. This is
    // about size, weight and spacing, which is where the difference actually
    // was. Headings tighten (negative spacing) the way the web app's do; body
    // and labels sit at 0 rather than Material's +0.5.
    textTheme: TextTheme(
      displayLarge: TextStyle(
          color: ink, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8),
      displayMedium: TextStyle(
          color: ink, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.7),
      displaySmall: TextStyle(
          color: ink, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineLarge: TextStyle(
          color: ink, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineMedium: TextStyle(
          color: ink, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.45),
      headlineSmall: TextStyle(
          color: ink, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: TextStyle(
          color: ink, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: TextStyle(
          color: ink, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleSmall: TextStyle(
          color: ink, fontSize: 14.5, fontWeight: FontWeight.w600, letterSpacing: -0.1),
      bodyLarge: TextStyle(
          color: ink, fontSize: 16, height: 1.45, letterSpacing: 0),
      bodyMedium: TextStyle(
          color: ink, fontSize: 15, height: 1.45, letterSpacing: 0),
      bodySmall: TextStyle(
          color: inkSoft, fontSize: 13, height: 1.45, letterSpacing: 0),
      labelLarge: TextStyle(
          color: ink, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0),
      labelMedium: TextStyle(
          color: inkSoft, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0),
      labelSmall: TextStyle(
          color: inkFaint, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0),
    ),
  );
}
