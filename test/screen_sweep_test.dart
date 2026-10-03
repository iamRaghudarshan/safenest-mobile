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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safenest/customize.dart';
import 'package:safenest/memory/dictation.dart';
import 'package:safenest/offline/mode.dart';
import 'package:safenest/offline/records.dart';
import 'package:safenest/offline/store.dart';
import 'package:safenest/offline/sync.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

import 'package:safenest/api.dart';
import 'package:safenest/screens/doc_preview.dart';
import 'package:safenest/screens/doc_versions.dart';
import 'package:safenest/screens/background_screen.dart';
import 'package:safenest/screens/documents_screen.dart';
import 'package:safenest/screens/habits_screen.dart';
import 'package:safenest/screens/labels_screen.dart';
import 'package:safenest/screens/life_memory_screen.dart';
import 'package:safenest/screens/memory_ask_screen.dart';
import 'package:safenest/screens/memory_search_screen.dart';
import 'package:safenest/screens/people_photos_screen.dart';
import 'package:safenest/screens/track_screen.dart';
import 'package:safenest/track/day.dart';
import 'package:safenest/track/story.dart';
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

/// Every file in lib/screens, and where each one is covered.
///
/// The ones NOT in `_screens` above are here with the reason, because
/// "it is not in the list" and "it cannot be stood up" look identical from the
/// outside and only one of them is acceptable.
const _accountedFor = {
  // Drawn by the sweep.
  'background_screen.dart', 'documents_screen.dart', 'habits_screen.dart',
  'labels_screen.dart', 'life_memory_screen.dart', 'memory_ask_screen.dart',
  'memory_search_screen.dart', 'people_photos_screen.dart',
  'track_screen.dart',
  'modules_screen.dart', 'notes_screen.dart', 'places_screen.dart',
  'profile_screen.dart', 'search_screen.dart', 'sign_in_screen.dart',
  'vault_screen.dart', 'doc_preview.dart', 'doc_versions.dart',
  'photo_editor.dart', 'photo_viewer.dart', 'saved_search_sheet.dart',
  'video_trim.dart',

  // Needs a signed-in session and a reachable server before it will build
  // anything at all, so standing it up here draws a spinner and asserts
  // nothing. Covered by its own test where it has one.
  'activity_screen.dart', 'backup_screen.dart', 'cleanup_screen.dart',
  'dashboard_screen.dart', 'doc_recent.dart', 'doc_trash.dart',
  'gallery_screen.dart', 'masters_screen.dart', 'module_list_screen.dart',
  'notifications_screen.dart', 'offline_screen.dart', 'person_faces.dart',
  'photos_home.dart', 'scan_screen.dart', 'storage_screen.dart',
  'sync_screen.dart', 'trash_screen.dart', 'two_factor_screen.dart',

  // Not a screen: a shell, a tab host or a strip that only exists inside one.
  // The thing that contains it is what has a width.
  'collections_home.dart', 'home_screen.dart', 'library_tabs.dart',
  'suggestions_strip.dart', 'vivid_home.dart',
};

/// screen can lay itself out, and that does not depend on the record existing.
final _screens = <String, Widget Function()>{
  'App background': () => const BackgroundScreen(debugRecent: []),
  'Documents': () => const DocumentsScreen(),
  'Habits': () => const HabitsScreen(),
  'Labels': () => const LabelsScreen(),
  'Life Memory': () =>
      LifeMemoryScreen(dictation: FakeDictation(), debugRows: const []),
  'Ask memories': () => MemoryAskScreen(
        debugNow: DateTime(2026, 10, 2),
        look: (_) async => const [],
      ),
  // AND THE ANSWERED STATE, which is where the risk actually is. The empty
  // screen is a text field and a paragraph; the answer carries a badge, a
  // sentence, numbered evidence and a row of chips, and every one of those is
  // a Row that can overflow at 320pt. A sweep that only ever draws empty
  // screens is the gap this file's own header warns about.
  'Ask memories answered': () => MemoryAskScreen(
        debugNow: DateTime(2026, 10, 2),
        debugQuestion: 'where did I buy the washing machine',
        look: (_) async => [
          {
            'id': 1,
            'body': 'Bought the washing machine from Vijay Sales for ₹32,400 '
                'with a two year warranty, and the delivery people left the '
                'old one on the landing.',
            'said_at': DateTime(2026, 9, 26).toIso8601String(),
            'spoken': 1,
            'server_id': null,
            'facts': [
              {
                'kind': 'expiry',
                'value': 'Warranty ends 26 Sep 2028',
                'at': DateTime(2028, 9, 26).toIso8601String(),
              },
              {'kind': 'amount', 'value': '₹32,400', 'at': null},
              {'kind': 'shop', 'value': 'Vijay Sales', 'at': null},
            ],
          }
        ],
      ),
  'Find memories': () => MemorySearchScreen(
        debugNow: DateTime(2026, 10, 3),
        debugRecent: const ['croma', 'warranty'],
        look: (_) async => [
          {
            'id': 1,
            'body': 'Bought the washing machine from Vijay Sales for '
                '₹32,400 with a two year warranty on the motor.',
            'said_at': DateTime(2026, 9, 26).toIso8601String(),
            'spoken': 1,
            'server_id': null,
            'photo_path': null,
            'facts': [
              {'kind': 'amount', 'value': '₹32,400', 'at': null},
              {'kind': 'shop', 'value': 'Vijay Sales', 'at': null},
            ],
          }
        ],
      ),
  'People together': () => PeoplePhotosScreen(
        startWith: 1,
        people: const [
          {'id': 1, 'name': 'Amma', 'cover_url': null, 'box': null},
          {'id': 2, 'name': 'Appa', 'cover_url': null, 'box': null},
        ],
        debugPhotos: const [],
      ),
  'Track Me': () => TrackScreen(
        debugFixes: const [],
        debugNow: DateTime(2026, 10, 3, 20),
      ),
  // AND A DAY WITH SOMETHING IN IT. The entry above draws the empty state; the
  // timeline, with its map, its sentences and its "name this place" buttons, is
  // where a narrow phone actually runs out of room.
  'Track Me, a day': () => TrackScreen(
        debugNow: DateTime(2026, 10, 3, 20),
        debugPlaces: [
          const Named(name: 'Home', lat: 12.9279, lon: 77.6271),
        ],
        debugFixes: [
          for (var m = 0; m <= 150; m += 10)
            Fix(
                at: DateTime(2026, 10, 3, 6).add(Duration(minutes: m)),
                lat: 12.9279,
                lon: 77.6271,
                accuracy: 10),
          for (var i = 0; i <= 8; i++)
            Fix(
                at: DateTime(2026, 10, 3, 8, 30).add(Duration(minutes: i * 5)),
                lat: 12.9279 + (12.9716 - 12.9279) * (i / 8),
                lon: 77.6271 + (77.5946 - 77.6271) * (i / 8),
                accuracy: 12),
          for (var m = 0; m <= 420; m += 15)
            Fix(
                at: DateTime(2026, 10, 3, 9, 20).add(Duration(minutes: m)),
                lat: 12.9716,
                lon: 77.5946,
                accuracy: 10),
        ],
      ),
  'Modules': () => ModulesScreen(onOpen: (_) {}),
  'Notes': () => const NotesScreen(),
  // AND NOTES WITH CARDS IN IT. The entry above stands the screen up without a
  // server, so it only ever drew the spinner — which is how a Material built
  // with both `shape` and `borderRadius` sat in the card for the life of the
  // screen without any test touching it. It asserts on the first frame in
  // debug and is silently ignored in release, so it reached nobody and could
  // not be found.
  'Notes with cards': () => NotesScreen(debugNotes: [
        {
          'id': 1,
          'title': 'Weekly shop',
          'body': '',
          'kind': 'checklist',
          'color': 'teal',
          'labels': ['Home', 'Food'],
          'items': [
            {'text': 'Rice', 'checked': false},
            {'text': 'Dal', 'checked': true},
          ],
          'pinned': true,
          'archived': false,
          'reminder_at': null,
        },
        {
          'id': 2,
          'title': 'Call the plumber about the kitchen tap',
          'body': 'He said any morning before ten, and to ring twice.',
          'kind': 'note',
          'color': 'default',
          'labels': <String>[],
          'items': <Map<String, dynamic>>[],
          'pinned': false,
          'archived': false,
          'reminder_at': '2030-01-01T09:00:00.000',
        },
      ]),
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

  test('every file in lib/screens is accounted for', () {
    // A screen added later is a screen nobody draws until somebody remembers to
    // add it here, and "somebody remembers" is what put three layout defects on
    // a phone.
    //
    // THIS USED TO BE A COUNT OF _screens, and the count did not do its job: a
    // change that adds a screen and bumps the number passes, and one did — the
    // Ask screen went in and the sweep stayed green. So it reads the directory
    // and names what it has never heard of. A new file here fails this test
    // until it is either drawn above or listed below with a reason.
    final onDisk = Directory('lib/screens')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.dart'))
        .toSet();

    expect(onDisk.difference(_accountedFor), isEmpty,
        reason: 'new in lib/screens and nothing here draws it — add it to '
            '_screens, or to _accountedFor with a reason');
    expect(_accountedFor.difference(onDisk), isEmpty,
        reason: 'listed here but gone from lib/screens — drop it');
  });
}
