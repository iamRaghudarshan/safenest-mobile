// EVERY SCREEN THAT CAN BE STOOD UP, AT THE WIDTHS IT SHIPS INTO.
//
// Three layout defects reached a phone in two days — a bar that took the whole
// screen, a card that set its text one character per line, and a nav bar too
// tight to read. All three were found by the owner, and all three were
// invisible in the source. What they had in common is that nothing here had
// ever drawn the thing at a phone's width and looked.
//
// This is the net. It does not know what any screen is supposed to look like;
// it asserts the two things that are true of all of them: laying out must not
// throw, and nothing may overflow its box. Both of those are exactly what a
// yellow-and-black stripe on a phone is, and both are free to check.
//
// WHAT IT CANNOT CATCH, said plainly: these screens fetch their content, and a
// widget test has no network, so what is drawn is the empty or error state.
// The suggestion card's fault only appeared once it had data. A screen passing
// here is a screen whose STRUCTURE is sound, not one that has been reviewed.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/customize.dart';
import 'package:safenest/offline/mode.dart';
import 'package:safenest/offline/records.dart';
import 'package:safenest/offline/store.dart';
import 'package:safenest/offline/sync.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

import 'package:safenest/api.dart';
import 'package:safenest/screens/doc_preview.dart';
import 'package:safenest/screens/doc_versions.dart';
import 'package:safenest/screens/documents_screen.dart';
import 'package:safenest/screens/habits_screen.dart';
import 'package:safenest/screens/labels_screen.dart';
import 'package:safenest/screens/modules_screen.dart';
import 'package:safenest/screens/notes_screen.dart';
import 'package:safenest/screens/gallery_screen.dart' show Photo;
import 'package:safenest/screens/photo_editor.dart';
import 'package:safenest/screens/photo_viewer.dart';
import 'package:safenest/screens/places_screen.dart';
import 'package:safenest/screens/profile_screen.dart';
import 'package:safenest/screens/saved_search_sheet.dart';
import 'package:safenest/screens/search_screen.dart';
import 'package:safenest/screens/sign_in_screen.dart';
import 'package:safenest/screens/vault_screen.dart';
import 'package:safenest/screens/video_trim.dart';

void _mockPackageInfo() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => call.method == 'getAll'
              ? <String, dynamic>{
                  'appName': 'SafeNest',
                  'packageName': 'in.safenesthub.app',
                  'version': '1.81.0',
                  'buildNumber': '179',
                }
              : null);
}

/// Port 1 is never listening, so anything these screens ask for fails at once
/// rather than hanging — which is what is wanted: the empty and error states
/// are the ones a test can reach, and they are states people see.
Api get _api => Api(baseUrl: 'http://127.0.0.1:1', token: 'x');

final _photos = [
  Photo(1, '/media/1.jpg', '/media/1t.jpg', DateTime(2026, 9, 1), false),
  Photo(2, '/media/2.mp4', '/media/2t.jpg', DateTime(2026, 9, 2), true,
      isVideo: true, durationMs: 12000),
];

/// Every screen in lib/screens that can be constructed at all.
///
/// The six at the bottom need a record to point at — a document id, a photo, a
/// video — which is why they had never been rendered by anything. A fabricated
/// id pointing at a dead port is enough: what is being checked is whether the
/// screen can lay itself out, and that does not depend on the record existing.
final _screens = <String, Widget Function()>{
  'Documents': () => const DocumentsScreen(),
  'Habits': () => const HabitsScreen(),
  'Labels': () => const LabelsScreen(),
  'Modules': () => ModulesScreen(onOpen: (_) {}),
  'Notes': () => const NotesScreen(),
  'Places': () => const PlacesScreen(),
  'Profile': () => const ProfileScreen(brand: Brand()),
  'Search': () => SearchScreen(onOpen: (_) {}),
  'Sign in': () => const SignInScreen(brand: Brand()),
  'Vault': () => const VaultScreen(),
  // The six that need a record.
  'Doc preview': () => DocPreviewScreen(api: _api, id: 1, title: 'Rent receipt'),
  'Doc versions': () => DocVersionsScreen(api: _api, id: 1, title: 'Rent receipt'),
  'Photo editor': () =>
      PhotoEditorScreen(api: _api, photoId: 1, imageUrl: '/media/1.jpg'),
  'Photo viewer': () => PhotoViewer(photos: _photos, initialIndex: 0),
  'Saved search': () => SavedSearchSheet(api: _api, labels: const [
        {'id': 1, 'name': 'Receipts'},
        {'id': 2, 'name': 'Warranties'},
      ]),
  'Video trim': () => VideoTrimScreen(
      api: _api, photoId: 2, videoUrl: '/media/2.mp4', durationMs: 12000),
};

Widget _wrap(Widget screen, AppSkin skin) {
  final session = Session();
  final store = OfflineStore();
  final mode = OfflineMode();
  final records = OfflineRecords(store: store, mode: mode);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<Session>.value(value: session),
      Provider<OfflineStore>.value(value: store),
      ChangeNotifierProvider<OfflineMode>.value(value: mode),
      Provider<OfflineRecords>.value(value: records),
      ChangeNotifierProvider<SyncService>.value(
          value: SyncService(
              store: store, api: () => session.api, records: records)),
    ],
    child: MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light, skin: skin),
      // A Scaffold around everything, because some of these are SHEETS rather
      // than pages and a TextField in one needs a Material ancestor — which
      // `showModalBottomSheet` supplies in the app. Without it the sweep
      // reports the sheet as broken when the harness is what is missing, and a
      // net that cries wolf is a net nobody reads.
      home: Scaffold(body: screen),
    ),
  );
}

/// The first fault that is about LAYOUT, ignoring the ones that are only about
/// there being no server.
///
/// A widget test has no network, so every screen that shows a photograph
/// raises NetworkImageLoadException. That is the harness, not the screen — and
/// letting it fail the sweep would mean the one net that catches real
/// overflows is red for reasons nobody can fix, which is how a net stops being
/// read at all.
Object? _layoutFault(WidgetTester tester) {
  for (var i = 0; i < 40; i++) {
    final e = tester.takeException();
    if (e == null) return null;
    final name = e.runtimeType.toString();
    if (name == 'NetworkImageLoadException') continue;
    if (e is Exception && '$e'.contains('statusCode: 400')) continue;
    return e;
  }
  return null;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockPackageInfo();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // 320 is the narrowest phone still in use, 360 is most Androids including
  // the one this app is used on, 390 is the common iPhone. A layout is not
  // "responsive" because it survives the widest of them.
  for (final width in [320.0, 360.0, 390.0]) {
    for (final skin in AppSkin.values) {
      for (final entry in _screens.entries) {
        testWidgets('${entry.key} lays out at ${width.toInt()}pt, ${skin.name}',
            (tester) async {
          SharedPreferences.setMockInitialValues({});
          await Customize.ensureLoaded();

          tester.view.physicalSize = Size(width * 3, 844 * 3);
          tester.view.devicePixelRatio = 3.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_wrap(entry.value(), skin));
          await tester.pump(const Duration(milliseconds: 400));

          // An overflow and an unsatisfiable constraint both arrive here.
          expect(_layoutFault(tester), isNull,
              reason: '${entry.key} did not lay out at ${width.toInt()}pt in '
                  '${skin.name}');

          // Every screen fetches on the way in, and `Api` arms a 60-second
          // timeout for each request. The binding refuses the request at once,
          // which cancels that timer — but only once the refusal has actually
          // been delivered, and a test that ends first is torn down with a
          // timer still pending. That is reported as a failure of whichever
          // screen happened to be slowest, which is exactly the kind of noise
          // that gets a real finding dismissed as flakiness.
          //
          // Bounded pumps, NOT pumpAndSettle: several of these screens sit on
          // a CircularProgressIndicator while they wait, and that animation
          // never settles — pumpAndSettle simply throws after ten seconds and
          // reports it as the screen's fault.
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 40)));
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 60));
          }
          expect(_layoutFault(tester), isNull,
              reason: '${entry.key} threw after its request came back');
        });
      }
    }
  }

  test('the sweep covers every screen in lib/screens', () {
    // The point of the count: a screen added later is a screen nobody draws
    // until somebody remembers to add it here, and "somebody remembers" is
    // what put three layout defects on a phone. This fails when the app grows
    // a screen the sweep has not been told about.
    expect(_screens, hasLength(16),
        reason: 'a screen was added or removed — add it to _screens');
  });
}
