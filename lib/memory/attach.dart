/// Attaching a photograph to a memory.
///
/// COPIED INTO THE APP'S OWN FOLDER, never referenced where it sits in the
/// camera roll. A library path is not a promise: the person may delete the
/// picture, and on iOS it is not readable again after a restart at all — the
/// memory would come back with a grey box and nothing to explain it. A few
/// megabytes is the right price for a photograph somebody attached to
/// something they wanted to keep.
///
/// Behind an interface for the same reason dictation is: no machine this app
/// is developed on has a camera roll, so the screen has to be drivable without
/// one.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// One picture offered to be attached.
class Snap {
  const Snap({required this.id, required this.thumb, required this.copy});

  final String id;

  /// Bytes for the tile. Small on purpose — a picker that decodes full-size
  /// photographs to draw a row of thumbnails is a picker that stutters.
  final Future<List<int>?> Function() thumb;

  /// Put it in the app's folder and return the path, or null if the phone
  /// could not produce the file — a picture still in iCloud, most often.
  final Future<String?> Function() copy;
}

abstract class PhotoSource {
  /// True if the app may look at the camera roll at all.
  Future<bool> allowed();

  /// The most recent pictures. Recent on purpose: a photograph somebody wants
  /// on a memory they are recording now is nearly always one they just took.
  Future<List<Snap>> recent({int limit = 24});
}

class PlatformPhotos implements PhotoSource {
  @override
  Future<bool> allowed() async {
    try {
      final ok = await PhotoManager.requestPermissionExtend();
      return ok.hasAccess;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<Snap>> recent({int limit = 24}) async {
    try {
      final albums = await PhotoManager.getAssetPathList(
          onlyAll: true, type: RequestType.image);
      if (albums.isEmpty) return const [];
      final assets = await albums.first.getAssetListRange(start: 0, end: limit);
      return [
        for (final a in assets)
          Snap(
            id: a.id,
            thumb: () async =>
                (await a.thumbnailDataWithSize(const ThumbnailSize(300, 300)))
                    ?.toList(),
            copy: () => adoptMemoryPhoto(a),
          ),
      ];
    } catch (_) {
      // A camera roll that will not answer is not a reason to fail the screen:
      // a memory with no picture is still a memory.
      return const [];
    }
  }
}

/// Copy [asset] into the app's own folder and return where it landed.
Future<String?> adoptMemoryPhoto(AssetEntity asset) async {
  final src = await asset.file;
  if (src == null) return null;

  final dir = await getApplicationDocumentsDirectory();
  final into = Directory(p.join(dir.path, 'memories'));
  await into.create(recursive: true);

  // A NEW NAME EVERY TIME. Writing over an existing filename leaves Flutter's
  // image cache holding the previous picture under that key, so the memory
  // shows the wrong photograph until the app is restarted.
  final ext = p.extension(src.path).toLowerCase();
  final name = 'm_${DateTime.now().microsecondsSinceEpoch}'
      '${ext.isEmpty ? '.jpg' : ext}';
  final dest = File(p.join(into.path, name));
  await src.copy(dest.path);
  return dest.path;
}

/// A camera roll for tests.
class FakePhotos implements PhotoSource {
  FakePhotos({this.canSee = true, this.count = 3, this.copies = true});

  final bool canSee;
  final int count;

  /// False to behave like a picture the phone cannot produce — still in
  /// iCloud, most often, which is the same reason a photo sometimes cannot be
  /// backed up.
  final bool copies;

  @override
  Future<bool> allowed() async => canSee;

  @override
  Future<List<Snap>> recent({int limit = 24}) async => [
        for (var i = 0; i < count; i++)
          Snap(
            id: 'fake-$i',
            thumb: () async => null,
            copy: () async => copies ? '/fake/memories/m_$i.jpg' : null,
          ),
      ];
}
