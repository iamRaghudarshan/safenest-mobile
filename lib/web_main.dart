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
/// is the app, talking to the real server.
///
///   flutter build web -t lib/web_main.dart --output build/webapp
///
/// and serve it with `run_app.py`, which proxies /api from the same origin so
/// the browser never asks the CORS question.
///
/// WHAT IS NOT REAL HERE. There is no camera roll and no background service in
/// a browser, so backing up, picking photos and notifications do not work.
/// Everything that comes from the server does. Judge navigation, layout and
/// content here; judge backup on a phone.
library;

import 'package:flutter/material.dart';

import 'customize.dart';
import 'main.dart' show SafeNestApp;
import 'session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Customize.ensureLoaded();

  // EVERY ADDRESS IS THIS PAGE. A browser refuses a cross-origin request, so
  // typing the real domain into the sign-in box fails with "Cannot reach your
  // SafeNest" — a true sentence about a situation nobody should have to
  // understand to look at a screen. The local server proxies /api to the real
  // one, so the app talks to where it was served from and everything works,
  // including photos, which are built from the same base. The caption under
  // the phone says so, because silently ignoring what somebody typed is worse
  // than the error it replaces.
  Session.forcedAddress = Uri.base.origin;

  // `#wide` fills the browser window instead, for looking at the tablet layout.
  runApp(_PhoneFrame(
    framed: !Uri.base.fragment.toLowerCase().contains('wide'),
    child: const SafeNestApp(),
  ));
}

/// A REAL PHONE, not the browser window.
///
/// This matters more than it looks. The defect that made this entry point
/// necessary was a widget answering the wrong question about how tall it was
/// allowed to be — which is to say, a defect in how the app responds to the
/// size it is given. A 1400pt-wide window is not the size the app ships into,
/// and a bar judged there says nothing about the bar on a phone. 390x844 is an
/// iPhone, and close enough to the Android the app is actually used on.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child, required this.framed});

  final Widget child;
  final bool framed;

  static const _size = Size(390, 844);

  @override
  Widget build(BuildContext context) {
    if (!framed) return child;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF1B1F28),
        // Centred, and SCROLLABLE. The phone is a fixed 854pt of content, and a
        // browser window shorter than that would otherwise overflow — which
        // paints a yellow-and-black stripe over the very screen this page
        // exists to let somebody look at. Scrolling is the right answer for a
        // window, where clipping the phone is not.
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _phone(),
                const SizedBox(height: 10),
                const Text(
                  'Local preview — sign in with any address; every request '
                  'goes through this page to the real server.',
                  style: TextStyle(color: Color(0xFF8D96A8), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phone() {
    return SizedBox(
            width: _size.width,
            height: _size.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              // The app reads the ambient MediaQuery, so overriding it here —
              // above the MaterialApp — is what makes the app believe it is on
              // a phone rather than merely being drawn small. The padding is a
              // phone's status bar and home indicator: the bar is laid out
              // inside a SafeArea, so leaving them at zero would hide exactly
              // the inset that decides where the bottom of the screen is.
              child: MediaQuery(
                data: const MediaQueryData(
                  size: _size,
                  devicePixelRatio: 3,
                  padding: EdgeInsets.only(top: 47, bottom: 34),
                  viewPadding: EdgeInsets.only(top: 47, bottom: 34),
                ),
                child: child,
              ),
            ),
          );
  }
}
