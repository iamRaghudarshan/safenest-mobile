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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarms.dart';
import 'api.dart';
import 'customize.dart';
import 'memory/reminders.dart';
import 'offline/autosync.dart';
import 'track/recorder.dart';
import 'offline/mode.dart';
import 'offline/records.dart';
import 'offline/store.dart';
import 'offline/sync.dart';
import 'session.dart';
import 'theme.dart';
import 'screens/sign_in_screen.dart';
import 'background.dart';
import 'screens/home_screen.dart';
import 'widgets/licence_notice.dart';
import 'widgets/nature_backdrop.dart';
import 'widgets/photo_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the person's appearance choices before the first frame, so a saved
  // "plain background" shows immediately rather than flashing the nature scene.
  await Customize.ensureLoaded();
  // Claims the background entry point. Cheap, schedules nothing on its own —
  // a phone with automatic backup switched off registers a callback the OS
  // never calls. Before runApp because iOS requires every BGTask identifier to
  // be registered during launch, not after the first frame.
  await BackgroundBackup.initialise();
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
  late final _mode = OfflineMode();
  late final _records = OfflineRecords(store: _store, mode: _mode);
  late final _sync = SyncService(
      store: _store, api: () => _session.api, records: _records);

  /// Sends what the phone is holding without being asked — on resume, shortly
  /// after something is queued, and on a backed-off retry. Before this there
  /// was no automatic sync at all: anything typed with the computer away sat in
  /// the queue until somebody opened the Sync screen and pressed the button.
  /// Track Me. Constructed always, recording never — the switch is off in a
  /// fresh install and `restore()` only resumes what the person had already
  /// turned on. Nothing here asks for a permission: a location prompt at launch,
  /// before anybody has seen what the app does, is the one most often refused,
  /// and this app says so in three other places already.
  late final _recorder = Recorder(store: _store);

  late final _autoSync = AutoSync(
      sync: _sync, store: _store, mode: _mode,
      signedIn: () => _session.signedIn);
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
    // The saved choice, and how much is waiting. Both read before the first
    // screen so the offline banner is right on the first frame rather than
    // appearing a second later.
    _mode.load();
    // The session decides whether the first screen is sign-in or the app, so it
    // stays on the launch path. The pending count only feeds a banner, and
    // reading it opens the database — which is the single most expensive thing
    // a cold start can do before it has drawn anything.
    _session.restore().then((_) => _loadBrand());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _sync.refreshPending());

    // LIFE MEMORY'S WARRANTY WARNINGS, put back every launch.
    //
    // Two reasons it has to happen here and not where a memory is saved. An
    // alarm set two years out does not survive the phone being replaced, a
    // system update or a force-stop, so something has to re-assert it; and
    // `Alarms.syncFrom` — which the Reminders screen calls — cancels every
    // alarm in the app before re-scheduling the server's, which would silently
    // take these with it. The hook is how it puts them back in the same breath.
    // Ids are stable, so re-scheduling moves a warning and never duplicates it.
    _autoSync.start();
    Alarms.instance.alsoSchedule = () => scheduleMemoryReminders(_store);
    _afterTheAppIsUp();
  }

  /// Everything that does not have to happen before the first frame.
  ///
  /// IT ALL USED TO RUN IN initState, and between them these cost most of a
  /// cold start. Scheduling the warranty warnings alone parses the whole
  /// timezone database, initialises the notification plugin, opens the SQLite
  /// file and then crosses the platform channel once per alarm — none of which
  /// anybody is waiting for, and all of which was happening while the person
  /// stared at a blank screen.
  ///
  /// A post-frame callback AND a short delay, not just the callback. The first
  /// frame is the splash; the frame that matters is the one with the home
  /// screen's own content on it, and that is still being built when the
  /// post-frame callback fires. Two seconds is past it on a slow phone and
  /// unnoticeable on a fast one — nothing here is time-critical, and an alarm
  /// set two seconds later than it might have been is set two years early
  /// either way.
  Timer? _settling;

  void _afterTheAppIsUp() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // HELD AND CANCELLED, not a bare Future.delayed. A timer that outlives
      // the widget fires into a disposed state — the same fault NetworkService
      // and BatteryService carry a note about — and a test tears the tree down
      // long before two seconds have passed, which is how this was caught.
      _settling = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        unawaited(_recorder.restore());
        unawaited(scheduleMemoryReminders(_store).catchError((e) {
          debugPrint('[memory] launch scheduling failed: $e');
          return 0;
        }));
      });
    });
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
  void dispose() {
    // The timer and the lifecycle observer both outlive this object otherwise,
    // and the observer would keep firing into a disposed state.
    _settling?.cancel();
    _autoSync.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: _session),
        Provider<OfflineStore>.value(value: _store),
        ChangeNotifierProvider<SyncService>.value(value: _sync),
        ChangeNotifierProvider<OfflineMode>.value(value: _mode),
        // So a screen that has just queued something can say so, and the retry
        // starts from twenty seconds rather than wherever the backoff had got
        // to. A queue that waits five minutes because the phone was idle
        // beforehand is the shape of "it did not sync".
        Provider<AutoSync>.value(value: _autoSync),
        ChangeNotifierProvider<Recorder>.value(value: _recorder),
        Provider<OfflineRecords>.value(value: _records),
      ],
      child: Consumer<Session>(
        // THE SKIN IS PART OF THE THEME, so the listener has to be ABOVE the
        // MaterialApp rather than inside its `builder`.
        //
        // There was already a ValueListenableBuilder on the same revision
        // down in `builder:` below, and it would not have worked for this:
        // `builder` wraps the app's CHILD, so it rebuilds the backdrop and
        // leaves `theme:` exactly as it was. Switching skins would have
        // repainted the wallpaper and nothing else — which looks like a
        // setting that half works, the worst kind to ship.
        builder: (context, session, _) => ValueListenableBuilder<int>(
          valueListenable: Customize.revision,
          builder: (context, _, _) {
            final skin =
                Customize.vividSkin ? AppSkin.vivid : AppSkin.classic;
            return MaterialApp(
          title: _brand.name,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(_brand, Brightness.light, skin: skin),
          darkTheme: buildTheme(_brand, Brightness.dark, skin: skin),
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
                      : Customize.photoBackground
                          // The person's own picture, dimmed enough that the
                          // app can still be read over it.
                          ? const PhotoBackdrop()
                          // An OPAQUE surface, not the transparent scaffold
                          // colour, or there would be nothing behind the
                          // transparent scaffolds.
                          : ColoredBox(
                              color: Theme.of(context).colorScheme.surface),
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
            );
          },
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
