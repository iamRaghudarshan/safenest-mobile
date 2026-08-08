/// Sending a photo or a document out of the app.
///
/// WHY THIS IS NOT JUST A URL
/// Media on the server is HMAC-signed and time-limited — handing the share sheet
/// a link would send somebody a URL that has already lapsed by the time they
/// open it, and would put an address for the owner's private machine into a
/// WhatsApp thread. So the bytes are fetched with the session's own token,
/// written to a temporary file, and THAT is shared. What leaves the app is a
/// file, not a way in.
///
/// The temporary copy lives in the OS cache directory, which the system clears
/// on its own. Deleting it ourselves the moment the sheet returns would be
/// wrong: on iOS the share sheet is still reading the file while the app has
/// already been given control back, and some targets copy it lazily.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';

/// Fetches each path and hands the lot to the platform share sheet.
///
/// `paths` are API paths (already signed by the server); `names` are what the
/// recipient sees. Returns null on success, or a sentence to show if it failed.
Future<String?> shareFromServer(
  Api api, {
  required List<({String path, String name})> items,
  String? text,
  String? subject,
}) async {
  if (items.isEmpty) return null;
  try {
    final dir = await getTemporaryDirectory();
    // Its own folder, so a share of thirty photos does not scatter files
    // among whatever else is cached.
    final out = Directory('${dir.path}/share');
    if (!await out.exists()) await out.create(recursive: true);

    final files = <XFile>[];
    for (var i = 0; i < items.length; i++) {
      final bytes = await api.download(items[i].path);
      // A filename is used verbatim by the receiving app, and these come from
      // photo titles and document names that people typed.
      final safe = items[i]
          .name
          .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_')
          .trim();
      final f = File('${out.path}/${i}_${safe.isEmpty ? "file" : safe}');
      await f.writeAsBytes(bytes);
      files.add(XFile(f.path));
    }

    await SharePlus.instance.share(ShareParams(
      files: files,
      text: text,
      subject: subject,
    ));
    return null;
  } on ApiError catch (e) {
    return e.message;
  } catch (_) {
    return 'That could not be shared.';
  }
}
