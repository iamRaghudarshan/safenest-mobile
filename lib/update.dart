/// Checking whether a newer Android build is on the customer's own server, and
/// installing it.
///
/// The phone talks only to its household's SafeNest, so its updates come from
/// there too: GET /api/mobile/latest reports the current APK and
/// /api/mobile/download serves it. iOS never uses this — Apple only allows the
/// App Store — so the check is Android-only by construction.
///
/// Defensive throughout: an update check must never break the app it is checking.
/// Any failure — offline, no build published, a server too old to answer — is
/// swallowed and the app carries on as if nothing happened.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'session.dart';

/// True when [candidate] is a strictly newer dotted version than [current].
///
/// A port of the server's updates.is_newer: compared number by number, so
/// 1.17.0 beats 1.9.0 (which a string compare gets wrong) and 1.17.0 beats 1.17.
bool isNewer(String candidate, String current) {
  List<int> parts(String v) => v
      .split('.')
      .map((p) => int.tryParse(RegExp(r'\d+').stringMatch(p) ?? '') ?? 0)
      .toList();
  final a = parts(candidate), b = parts(current);
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Check once and, if a newer Android build is on offer, prompt to install it.
/// Safe to call after sign-in from a context below MaterialApp; does nothing on
/// iOS, when signed out, or on any error.
Future<void> checkForUpdate(BuildContext context, Session session) async {
  if (!Platform.isAndroid) return;        // iOS updates via the App Store only
  if (!session.signedIn) return;
  try {
    final info = await PackageInfo.fromPlatform();
    final res = await session.api.get('/api/mobile/latest', {'platform': 'android'});
    if (res is! Map || res['available'] != true) return;
    final latest = '${res['version'] ?? ''}';
    if (latest.isEmpty || !isNewer(latest, info.version)) return;
    if (!context.mounted) return;

    final notes = '${res['notes'] ?? ''}'.trim();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update available ($latest)'),
        content: SingleChildScrollView(
          child: Text(notes.isEmpty
              ? 'A newer version of the app is ready to install.'
              : notes),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await _downloadAndInstall(context, session, '${res['url']}');
  } catch (_) {
    // An update check must never break the app. Offline, no build, an old
    // server — all simply mean "not now".
  }
}

Future<void> _downloadAndInstall(
    BuildContext context, Session session, String path) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Downloading update…')));
  try {
    // A relative path from the server, fetched against the address this phone is
    // already on — the same download() the app uses for documents, which already
    // carries query strings, so the ?platform= survives.
    final bytes = await session.api.download(path);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/safenest-update.apk');
    await file.writeAsBytes(bytes, flush: true);
    // Hands the APK to the system package installer. The first time, Android
    // sends the person to Settings to allow "install unknown apps" for SafeNest;
    // after that it installs directly. Requires REQUEST_INSTALL_PACKAGES, which
    // AndroidManifest.xml now declares.
    final r = await OpenFilex.open(file.path,
        type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done && context.mounted) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not open the installer: ${r.message}')));
    }
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('The update could not be downloaded. Try again later.')));
  }
}
