// Does Info.plist carry a purpose string for every framework we link?
//
// APPLE SCANS THE LINKED BINARY, NOT THE CODE PATH. A dependency that links
// Speech, Photos or Core Location makes Apple demand that framework's purpose
// string whether or not the app ever calls it. Without one the UPLOAD STILL
// SUCCEEDS — altool says "UPLOAD SUCCEEDED with no errors" and hands back a
// delivery UUID — and the build then fails PROCESSING, so it never appears in
// TestFlight and nothing in CI goes red.
//
// That is exactly how 1.88.0 was lost: speech_to_text arrived with Life
// Memory, NSSpeechRecognitionUsageDescription did not, the upload reported
// success, and the testers sat on 1.86.0 for four days while every dashboard
// said the release had shipped.
//
// So this runs BEFORE the macOS archive, where a minute bills as ten. It reads
// the real pubspec.yaml and the real Info.plist and fails the build with the
// exact key to add, rather than letting Apple find it an hour and a round trip
// later.
//
//   dart run tool/check_purpose_strings.dart
import 'dart:io';

/// Package -> the key Apple demands once it is linked.
///
/// Keyed on the DEPENDENCY, not on a feature flag: the question Apple asks is
/// "is this framework in the binary", and a package in pubspec.yaml is the
/// honest local answer to that.
const _required = <String, List<String>>{
  'speech_to_text': ['NSSpeechRecognitionUsageDescription',
                     'NSMicrophoneUsageDescription'],
  'photo_manager': ['NSPhotoLibraryUsageDescription'],
  'image_picker': ['NSPhotoLibraryUsageDescription', 'NSCameraUsageDescription'],
  'gal': ['NSPhotoLibraryAddUsageDescription'],
  'camera': ['NSCameraUsageDescription', 'NSMicrophoneUsageDescription'],
  'record': ['NSMicrophoneUsageDescription'],
  'geolocator': ['NSLocationWhenInUseUsageDescription'],
  'local_auth': ['NSFaceIDUsageDescription'],
  'flutter_contacts': ['NSContactsUsageDescription'],
  'mobile_scanner': ['NSCameraUsageDescription'],
};

// NOTE: `exit`, not a returned int. A Dart `main` that returns a number exits
// 0 regardless, so the first version of this printed a perfectly good error
// and let CI go green — a guard that cannot fail the build is not a guard.
void main() {
  final pubspec = File('pubspec.yaml');
  final plist = File('ios/Runner/Info.plist');
  if (!pubspec.existsSync() || !plist.existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exit(2);
  }

  // Dependencies only, not dev_dependencies: a test-time package is never in
  // the shipped binary and demanding a purpose string for it would be noise
  // that teaches people to ignore this check.
  final lines = pubspec.readAsLinesSync();
  final deps = <String>{};
  var inDeps = false;
  for (final line in lines) {
    if (line.startsWith('dependencies:')) { inDeps = true; continue; }
    if (line.startsWith('dev_dependencies:') ||
        line.startsWith('flutter:') ||
        line.startsWith('dependency_overrides:')) { inDeps = false; continue; }
    if (!inDeps) continue;
    final m = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
    if (m != null) deps.add(m.group(1)!);
  }

  final plistText = plist.readAsStringSync();
  final missing = <String, String>{};
  for (final entry in _required.entries) {
    if (!deps.contains(entry.key)) continue;
    for (final key in entry.value) {
      if (!plistText.contains('<key>$key</key>')) missing[key] = entry.key;
    }
  }

  if (missing.isEmpty) {
    final checked = _required.keys.where(deps.contains).toList()..sort();
    stdout.writeln('Purpose strings present for: ${checked.join(', ')}');
    return;
  }

  stderr.writeln('ios/Runner/Info.plist is missing purpose strings.\n');
  missing.forEach((key, pkg) {
    stderr.writeln('  $key');
    stderr.writeln('      demanded because this app depends on $pkg\n');
  });
  stderr.writeln('Apple accepts the upload without these and then fails the\n'
      'build in processing, so TestFlight shows nothing and CI stays green.\n'
      'Add each key with an honest one-line reason and build again.');
  exit(1);
}
