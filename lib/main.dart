/// SafeNest for phones.
///
/// A companion to the copy running on the owner's own computer — not a service.
/// There is no cloud here and no account with us: the app is told an address, it
/// signs in to that machine, and everything it shows comes from there. If the
/// computer is off, the app is honest about it rather than showing a stale copy
/// and calling it a backup.
///
/// WHY THIS EXISTS AT ALL, given the web app already works on a phone:
/// a web page cannot read the photo library. That is not a gap to be coded
/// around — it is the platform refusing, deliberately, and it means the one
/// feature people most want on a phone (back up my whole gallery) could not be
/// built there. Everything else in this app is here to keep that one thing
/// company.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'customize.dart';
import 'offline/store.dart';
import 'offline/sync.dart';
import 'session.dart';
import 'theme.dart';
import 'screens/sign_in_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/licence_notice.dart';
import 'widgets/nature_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the person's appearance choices before the first frame, so a saved
  // "plain background" shows immediately rather than flashing the nature scene.
  await Customize.ensureLoaded();
  runApp(const SafeNestApp());
}

class SafeNestApp extends StatefulWidget {
  const SafeNestApp({super.key});
  @override
  State<SafeNestApp> createState() => _SafeNestAppState();
}

class _SafeNestAppState extends State<SafeNestApp> {
  final _session = Session();

  /// Where records live while the computer is asleep, and the thing that pushes
  /// them back. Made once here and handed down, so every screen reads and
  /// writes the same queue -- two stores would mean two queues, and work
  /// entered on one screen would be invisible to the Sync button on another.
  late final _store = OfflineStore();
  late final _sync = SyncService(store: _store, api: () => _session.api);
  Brand _brand = const Brand();

  /// Light, dark, or follow the phone. Remembered — a theme that resets on every
  /// launch is one nobody bothers to set. Not a secret, so SharedPreferences
  /// rather than the secure store.
  ThemeMode _themeMode = ThemeMode.system;

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme.mode');
    if (!mounted) return;
    setState(() => _themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => ThemeMode.system,
        ));
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme.mode', mode.name);
  }

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _session.restore().then((_) => _loadBrand());
  }

  /// The name and colour come from the customer's own server, because SafeNest
  /// can be renamed and recoloured from its Administration screen. An app that
  /// hard-coded them would show one name on the laptop and another in the hand.
  /// It never blocks startup: a branding lookup that fails must not cost anyone
  /// their app.
  Future<void> _loadBrand() async {
    final url = _session.baseUrl;
    if (url == null) return;
    try {
      final j = await Api(baseUrl: url).get('/api/branding');
      if (j is Map && mounted) {
        setState(() => _brand = Brand.fromJson(Map<String, dynamic>.from(j)));
      }
    } catch (_) {
      // Keep the fallback. Not worth a message; the name is not the point.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: _session),
        Provider<OfflineStore>.value(value: _store),
        ChangeNotifierProvider<SyncService>.value(value: _sync),
      ],
      child: Consumer<Session>(
        builder: (context, session, _) => MaterialApp(
          title: _brand.name,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(_brand, Brightness.light),
          darkTheme: buildTheme(_brand, Brightness.dark),
          themeMode: _themeMode,
          // A single backdrop behind every route. Scaffolds are transparent (see
          // theme.dart) so it shows through the whole app and the sign-in page.
          // The person can swap the nature scene for a plain screen in Profile →
          // Personalise; ValueListenableBuilder rebuilds when they do.
          builder: (context, child) => ValueListenableBuilder<int>(
            valueListenable: Customize.revision,
            builder: (context, _, _) => Stack(
              children: [
                Positioned.fill(
                  child: Customize.natureBackground
                      ? const NatureBackdrop()
                      // An OPAQUE surface, not the transparent scaffold colour, or
                      // there would be nothing behind the transparent scaffolds.
                      : ColoredBox(color: Theme.of(context).colorScheme.surface),
                ),
                if (child != null) Positioned.fill(child: child),
              ],
            ),
          ),
          home: session.loading
              ? const _Splash()
              // A blocked licence takes over the whole app rather than failing
              // screen by screen, because that is how the server treats it: the
              // gate is middleware over everything.
              : session.licenceBlock != null
                  ? Scaffold(
                      appBar: AppBar(title: Text(_brand.name)),
                      body: LicenceNotice(
                        error: session.licenceBlock!,
                        onRetry: () {
                          session.clearLicenceBlock();
                          _loadBrand();
                        },
                      ),
                    )
                  : session.signedIn
                      ? HomeScreen(
                          brand: _brand,
                          themeMode: _themeMode,
                          onThemeChanged: _setThemeMode,
                        )
                      : SignInScreen(brand: _brand, onSignedIn: _loadBrand),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
