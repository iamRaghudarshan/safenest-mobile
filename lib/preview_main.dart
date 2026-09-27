/// A browser preview of the app's screens, for judging the design.
///
/// WHY THIS EXISTS. Neither platform can be built on the machine this is
/// developed on — no Xcode, no Android SDK — so every screen has been shipped
/// unseen and every visual defect so far was found by the owner rather than by
/// anything here. A browser is the one target that does build, and it turns
/// "looks right in a PNG" into something that can be tapped.
///
/// WHY IT IS NOT `main.dart`. The real entry point awaits
/// `BackgroundBackup.initialise()` BEFORE `runApp` — a plugin with no web
/// implementation, so on the web it throws and the first frame never arrives.
/// That is a blank page, and it is correct behaviour for a phone app: the
/// background entry point has to be claimed during launch on iOS. Rather than
/// weaken the real startup for a preview, the preview gets its own door.
///
/// WHAT IT IS NOT. It does not talk to a server and it has no camera roll, so
/// it proves nothing about backup, sign-in or sync. It shows LAYOUT, COLOUR,
/// TYPE and SPACING, in both skins and both brightnesses, which is exactly
/// what could not be checked before.
///
///   flutter run -d chrome -t lib/preview_main.dart
library;

import 'package:flutter/material.dart';

import 'screens/backup_screen.dart';
import 'screens/vivid_home.dart';
import 'theme.dart';
import 'widgets/file_kinds.dart';
import 'widgets/library_growth.dart';
import 'widgets/memory_hero.dart';
import 'widgets/people_strip.dart';
import 'widgets/skin_picker.dart';
import 'backup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // No plugin work at all before the first frame — that is the whole
  // difference between this and main.dart.
  runApp(const PreviewApp());
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});

  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  AppSkin _skin = AppSkin.vivid;
  Brightness _mode = Brightness.light;
  int _screen = 0;

  static const _screens = ['Home', 'Backup', 'Pieces'];

  @override
  Widget build(BuildContext context) {
    final theme = buildTheme(const Brand(), _mode, skin: _skin);
    return MaterialApp(
      title: 'SafeNest preview',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        backgroundColor: const Color(0xFF1B1F28),
        body: SafeArea(
          child: Column(children: [
            _Controls(
              skin: _skin,
              mode: _mode,
              screen: _screen,
              screens: _screens,
              onSkin: (v) => setState(() => _skin = v),
              onMode: (v) => setState(() => _mode = v),
              onScreen: (v) => setState(() => _screen = v),
            ),
            // A REAL PHONE, not the browser window. 390x844 is the size the
            // designs were drawn at, and a screen judged at 1400 wide flatters
            // every layout on it.
            Expanded(
              child: Center(
                child: Container(
                  width: 390,
                  height: 844,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black54,
                          blurRadius: 40,
                          offset: Offset(0, 14)),
                    ],
                  ),
                  child: Theme(data: theme, child: _body()),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_screen) {
      case 1:
        return const BackupScreen(debugProgress: _running);
      case 2:
        return const _Pieces();
      default:
        return const VividHome(brand: Brand(), debugData: _home);
    }
  }
}

const _home = VividHomeData(
  name: 'Raghudarshan',
  photos: 1573,
  videos: 200,
  documents: 214,
  memory: VividCard(title: 'Goa', sub: '142 photos', count: 142),
  people: [
    VividCard(title: 'Anita', count: 312),
    VividCard(title: 'Dad', count: 108),
    VividCard(title: 'Meera', count: 64),
    VividCard(title: 'Arjun', count: 41),
  ],
  albums: [
    VividCard(title: 'Goa', sub: '142 photos', count: 142),
    VividCard(title: 'Diwali', sub: '88 photos', count: 88),
    VividCard(title: 'Coorg', sub: '64 photos', count: 64),
  ],
  kinds: {'pdf': 86, 'image': 54, 'sheet': 31, 'other': 43},
  months: [88, 142, 96, 174, 151, 118, 203, 165, 229, 141, 186, 312],
);

const _running = BackupProgress(
  state: BackupState.running,
  total: 1048,
  done: 68,
  skipped: 900,
  message: 'Backing up…',
  inFlight: [
    BackupItem(
        id: 'a1',
        label: 'IMG_4102.MOV',
        isVideo: true,
        sent: 41943040,
        total: 96468992),
    BackupItem(
        id: 'a2',
        label: 'IMG_4103.HEIC',
        isVideo: false,
        sent: 900000,
        total: 2400000),
    BackupItem(id: 'a3', label: 'IMG_4104.HEIC', isVideo: false),
  ],
);

/// The parts that are hard to see inside a whole screen.
class _Pieces extends StatelessWidget {
  const _Pieces();

  @override
  Widget build(BuildContext context) {
    final t = context.skin;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const _Label('The theme picker'),
      SkinPicker(brand: const Brand(), onChanged: () {}),
      const SizedBox(height: 22),
      const _Label('A memory'),
      const MemoryHero(
        title: 'Sunset at Palolem',
        subtitle: 'Goa · 142 photos',
        when: '2 years ago',
        pips: 4,
      ),
      const SizedBox(height: 22),
      const _Label('How the library is growing'),
      const LibraryGrowth(
        months: [88, 142, 96, 174, 151, 118, 203, 165, 229, 141, 186, 312],
        storage: '48.2 GB\nof 120 GB',
      ),
      const SizedBox(height: 22),
      const _Label('Files, by kind'),
      FileKindBar(
        counts: const {'pdf': 86, 'image': 54, 'sheet': 31, 'other': 43},
        selected: 'pdf',
        onPick: (_) {},
      ),
      const SizedBox(height: 22),
      const _Label('The faces on Photos'),
      PeopleStrip(
        people: const [
          {'id': 1, 'name': 'Anita', 'photo_count': 312},
          {'id': 2, 'name': 'Dad', 'photo_count': 108},
          {'id': 3, 'name': 'Meera', 'photo_count': 64},
          {'id': 4, 'name': 'Arjun', 'photo_count': 41},
        ],
        selected: const {1},
        onToggle: (_) {},
        onSeeAll: () {},
      ),
      const SizedBox(height: 22),
      const _Label('Buttons and fields, as the theme makes them'),
      const TextField(decoration: InputDecoration(hintText: 'Search')),
      const SizedBox(height: 10),
      FilledButton(onPressed: () {}, child: const Text('Back up now')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: () {}, child: const Text('Back up automatically')),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        for (final m in ['gallery', 'documents', 'expenses', 'notes'])
          Chip(
            label: Text(m),
            backgroundColor: t.module(m).withValues(alpha: 0.12),
            labelStyle: TextStyle(color: t.module(m), fontWeight: FontWeight.w700),
          ),
      ]),
      const SizedBox(height: 40),
    ]);
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.skin,
    required this.mode,
    required this.screen,
    required this.screens,
    required this.onSkin,
    required this.onMode,
    required this.onScreen,
  });

  final AppSkin skin;
  final Brightness mode;
  final int screen;
  final List<String> screens;
  final ValueChanged<AppSkin> onSkin;
  final ValueChanged<Brightness> onMode;
  final ValueChanged<int> onScreen;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: const Color(0xFF11151C),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('SafeNest preview',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            _Group(
              labels: const ['Classic', 'Colourful'],
              index: skin == AppSkin.vivid ? 1 : 0,
              onTap: (i) => onSkin(i == 1 ? AppSkin.vivid : AppSkin.classic),
            ),
            _Group(
              labels: const ['Light', 'Dark'],
              index: mode == Brightness.dark ? 1 : 0,
              onTap: (i) =>
                  onMode(i == 1 ? Brightness.dark : Brightness.light),
            ),
            _Group(labels: screens, index: screen, onTap: onScreen),
          ],
        ),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.labels, required this.index, required this.onTap});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFF1E242F),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: i == index ? const Color(0xFF3B82F6) : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: i == index
                            ? Colors.white
                            : const Color(0xFF9AA4B8))),
              ),
            ),
        ]),
      );
}
