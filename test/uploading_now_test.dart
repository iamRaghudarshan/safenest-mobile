// The row of photographs going up.
//
// There is no Android SDK or Xcode on the machine this is written on, so these
// prove it lays out and says the right thing — not how it looks. The thumbnail
// itself needs the photo library and cannot be reached from a test, so the
// cache is left empty on purpose: that is also the real first frame of every
// backup, before anything has decoded, and it must not be a blank hole.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safenest/backup.dart';
import 'package:safenest/theme.dart';
import 'package:safenest/widgets/uploading_now.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTheme(const Brand(), Brightness.light),
      home: Scaffold(body: child),
    );

void main() {
  late ThumbCache cache;

  setUp(() => cache = ThumbCache());
  tearDown(() => cache.dispose());

  testWidgets('nothing in flight draws nothing at all', (tester) async {
    await tester.pumpWidget(_wrap(UploadingNow(items: const [], cache: cache)));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four photos at once say so, and show four tiles',
      (tester) async {
    // The bug this is for: photos go up FOUR at a time, and one flickering
    // filename read as a single photo taking an age.
    final items = [
      for (var i = 0; i < 4; i++)
        BackupItem(
            id: 'a$i',
            label: 'IMG_$i.HEIC',
            isVideo: false,
            sent: 25 * i,
            total: 100),
    ];
    await tester.pumpWidget(_wrap(UploadingNow(items: items, cache: cache)));
    await tester.pump();

    expect(find.text('Sending 4 at once'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
    expect(find.text('50%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one video reads as a video, not as a photo', (tester) async {
    const items = [
      BackupItem(
          id: 'v', label: 'IMG.MOV', isVideo: true, sent: 30, total: 60),
    ];
    await tester.pumpWidget(_wrap(UploadingNow(items: items, cache: cache)));
    await tester.pump();
    expect(find.text('Sending 1 video'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });

  testWidgets('coming down from iCloud says THAT, not "sending"',
      (tester) async {
    // Two different waits. Telling somebody their photo is uploading while
    // Apple is still sending it down is the misinformation this separation
    // exists to prevent.
    final items = [
      const BackupItem(id: 'c', label: 'IMG.HEIC', isVideo: false)
          .withFetch(0.4),
    ];
    await tester.pumpWidget(_wrap(UploadingNow(items: items, cache: cache)));
    await tester.pump();

    expect(find.text('Getting 1 photo from iCloud'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_download), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('a size not yet known shows a placeholder, never "NaN%"',
      (tester) async {
    const items = [BackupItem(id: 'x', label: 'IMG.HEIC', isVideo: false)];
    await tester.pumpWidget(_wrap(UploadingNow(items: items, cache: cache)));
    await tester.pump();
    expect(find.text('…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no thumbnail decoded yet it still lays out', (tester) async {
    // The real first frame of every backup.
    const items = [
      BackupItem(id: 'x', label: 'IMG.HEIC', isVideo: false, sent: 1, total: 4),
    ];
    await tester.pumpWidget(_wrap(UploadingNow(items: items, cache: cache)));
    await tester.pump();
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
  });

  testWidgets('a narrow phone scrolls the row rather than overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final items = [
      for (var i = 0; i < 8; i++)
        BackupItem(
            id: 'a$i', label: 'IMG_$i', isVideo: false, sent: 1, total: 2),
    ];
    await tester.pumpWidget(_wrap(UploadingNow(items: items, cache: cache)));
    await tester.pump();
    // An overflow is a runtime stripe, not a build error, so it has to be
    // asserted rather than noticed.
    expect(tester.takeException(), isNull);
  });
}
