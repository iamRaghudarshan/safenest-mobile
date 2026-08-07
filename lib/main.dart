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
import 'session.dart';
import 'theme.dart';
import 'screens/sign_in_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/licence_notice.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SafeNestApp());
}

class SafeNestApp extends StatefulWidget {
  const SafeNestApp({super.key});
  @override
  State<SafeNestApp> createState() => _SafeNestAppState();
}

class _SafeNestAppState extends State<SafeNestApp> {
  final _session = Session();
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
    return ChangeNotifierProvider.value(
      value: _session,
      child: Consumer<Session>(
        builder: (context, session, _) => MaterialApp(
          title: _brand.name,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(_brand, Brightness.light),
          darkTheme: buildTheme(_brand, Brightness.dark),
          themeMode: _themeMode,
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
