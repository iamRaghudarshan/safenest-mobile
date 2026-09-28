// A PICTURE of the assembled shell, not of a screen on its own.
//
// The blank-Home-with-a-floating-bar defect was invisible to every render test
// here because they all draw one screen directly. This draws HomeScreen — the
// thing with the bar in it — and writes a PNG, so the shell is looked at the
// same way the screens are.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:safenest/screens/home_screen.dart';
import 'package:safenest/session.dart';
import 'package:safenest/theme.dart';

const _out =
    r'C:\Users\Pro-TEAM\AppData\Local\Temp\claude\d--AI-TUBE\4dda9227-6269-4d42-aac1-051ae3b25e79\scratchpad';

Future<void> _useRealFont() async {
  for (final path in [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    for (final family in ['Roboto', 'packages/safenest/Roboto', '.SF UI Text']) {
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }
    return;
  }
}

/// The Profile tab asks `package_info_plus` for the version the moment it is
/// built, and an IndexedStack builds every tab at once — so a shell test always
/// hits it. There is no plugin off-device, and the exception it throws lands in
/// the middle of the test rather than in Profile, which reads like a fault in
/// whatever was being measured.
void _mockPackageInfo() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async {
    if (call.method != 'getAll') return null;
    return <String, dynamic>{
      'appName': 'SafeNest',
      'packageName': 'in.safenesthub.app',
      'version': '1.75.0',
      'buildNumber': '176',
    };
  });
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockPackageInfo();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final skin in AppSkin.values) {
    testWidgets('shell shot: ${skin.name}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Customize.ensureLoaded();
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _useRealFont();

      final session = Session();
      final store = OfflineStore();
      final mode = OfflineMode();
      final records = OfflineRecords(store: store, mode: mode);
      final key = GlobalKey();
      await tester.pumpWidget(MultiProvider(
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
          home: RepaintBoundary(key: key, child: const HomeScreen(brand: Brand())),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await b.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (png != null && Directory(_out).existsSync()) {
          File('$_out/shell_${skin.name}.png')
              .writeAsBytesSync(png.buffer.asUint8List());
        }
      });
    });
  }
}
