/// The REAL app, in a browser — shell, navigation and all.
///
/// `preview_main.dart` renders individual screens from fixed data, which is
/// good for judging a layout and useless for the class of bug that only
/// appears once the app assembles itself: a blank Home under a nav bar
/// floating in the middle of the screen is not visible in any screen rendered
/// on its own, and that is exactly what shipped.
///
/// This is `SafeNestApp` itself. The ONE thing it skips is
/// `BackgroundBackup.initialise()`, which has no web implementation and which
/// `main.dart` awaits before `runApp` — correctly, because iOS requires the
/// background entry point to be claimed during launch. Everything after that
/// is the app.
///
///   flutter run -d chrome -t lib/web_main.dart
library;

import 'package:flutter/material.dart';

import 'customize.dart';
import 'main.dart' show SafeNestApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Customize.ensureLoaded();
  runApp(const SafeNestApp());
}
