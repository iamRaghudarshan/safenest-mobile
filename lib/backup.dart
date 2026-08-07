/// Backing up the phone's photo library. The point of the whole application.
///
/// WHY A NATIVE APP EXISTS AT ALL
/// A web page cannot read an iPhone's photo library — the file picker is the only
/// door, and above roughly a hundred photos iOS stops closing it. That was
/// measured on a real phone, in a Safari tab and in the Home-Screen copy alike,
/// with local photos and no format conversion involved. No web API raises that
/// ceiling and none can cap what the picker offers, so "back up my gallery" could
/// not be built out of a file input however it was dressed up. Everything below
/// is what having real library access buys.
///
/// WHAT MAKES THIS DIFFERENT FROM THE WEB ATTEMPT
///
///   * Nothing is selected. `PhotoManager` enumerates the library directly, so
///     the person presses one button and the app knows about every photo.
///   * It is resumable by construction. Each asset has a stable id; the ids
///     already sent are remembered, so a second run over 20,000 photos costs a
///     list comparison rather than 20,000 uploads.
///   * It can run while the app is in the background, which a web page cannot.
///
/// PACED ON PURPOSE
/// Four at a time, matching the server: measured at 7.81 photos/sec against a
/// ceiling of 8.50, where eight at a time was SLOWER. More parallelism here would
/// not make the server faster, it would just drain the battery quicker and give
/// the OS a better reason to kill us.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

enum BackupState { idle, scanning, running, paused, done, failed }

class BackupProgress {
  const BackupProgress({
    this.state = BackupState.idle,
    this.total = 0,
    this.done = 0,
    this.skipped = 0,
    this.failed = 0,
    this.message = '',
  });

  final BackupState state;
  final int total;      // photos this run has to consider
  final int done;       // uploaded now
  final int skipped;    // already on the server from a previous run
  final int failed;
  final String message;

  int get handled => done + skipped + failed;
  double get fraction => total == 0 ? 0 : handled / total;
}

class BackupService extends ChangeNotifier {
  BackupService(this._api);

  final Api _api;
  static const _sentKey = 'backup.sent.ids';
  static const _concurrency = 4;

  BackupProgress _p = const BackupProgress();
  BackupProgress get progress => _p;

  /// Ids already accepted by the server. This is what makes a repeat run cheap
  /// and is why the backup can be left on a nightly automation without shame.
  Set<String> _sent = {};
  bool _stop = false;

  void _emit(BackupProgress p) {
    _p = p;
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _sent = (prefs.getStringList(_sentKey) ?? const <String>[]).toSet();
  }

  Future<void> _remember(String id) async {
    _sent.add(id);
    // Written in batches by the caller rather than per photo: 20,000 individual
    // writes to disk during a first backup is its own performance problem.
  }

  Future<void> _flush() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_sentKey, _sent.toList());
  }

  void stop() => _stop = true;

  /// Ask for the library. Note `PermissionState.limited`: iOS lets someone grant
  /// access to a HANDFUL of photos, and an app that treats that as "granted"
  /// silently backs up four pictures and reports success. It has to be named.
  Future<PermissionState> requestAccess() =>
      PhotoManager.requestPermissionExtend();

  Future<void> runFullBackup() async {
    _stop = false;
    _emit(const BackupProgress(
        state: BackupState.scanning, message: 'Looking through your photos…'));

    final perm = await requestAccess();
    if (!perm.hasAccess) {
      _emit(const BackupProgress(
          state: BackupState.failed,
          message: 'SafeNest has not been allowed to see your photos. '
              'Open Settings and grant access to all photos.'));
      return;
    }
    // `hasAccess` is TRUE for PermissionState.limited — the comment on
    // requestAccess() said this had to be named and then the code did not name
    // it. iOS lets somebody grant access to a handful of chosen photos; the
    // library then reports only those, so the backup would sweep four pictures
    // out of twenty thousand and report a clean success. Nobody would look
    // again for months.
    if (perm == PermissionState.limited) {
      _emit(const BackupProgress(
          state: BackupState.failed,
          message: 'SafeNest can only see the few photos you picked, not your '
              'whole library. Settings → Privacy → Photos → SafeNest → '
              'All Photos, then run this again.'));
      return;
    }

    await load();

    final albums = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,   // videos are not photos and the gallery cannot store them
    );
    if (albums.isEmpty) {
      _emit(const BackupProgress(
          state: BackupState.done, message: 'No photos found on this phone.'));
      return;
    }

    final all = albums.first;
    final count = await all.assetCountAsync;

    // Paged rather than fetched whole: asking for a list of 40,000 asset objects
    // at once is how an app gets killed on a phone with the library it most
    // needs to back up.
    const page = 200;
    var handledDone = 0, handledSkip = 0, handledFail = 0;
    _emit(BackupProgress(
        state: BackupState.running,
        total: count,
        message: 'Backing up $count photos'));

    for (var offset = 0; offset < count; offset += page) {
      if (_stop) break;
      final batch = await all.getAssetListRange(start: offset, end: offset + page);
      final todo = batch.where((a) => !_sent.contains(a.id)).toList();
      handledSkip += batch.length - todo.length;

      // Four at a time, matching what the server was measured to do best.
      for (var i = 0; i < todo.length; i += _concurrency) {
        if (_stop) break;
        final slice = todo.skip(i).take(_concurrency);
        final results = await Future.wait(slice.map(_send));
        for (final ok in results) {
          if (ok) {
            handledDone++;
          } else {
            handledFail++;
          }
        }
        _emit(BackupProgress(
          state: BackupState.running,
          total: count,
          done: handledDone,
          skipped: handledSkip,
          failed: handledFail,
          message: 'Backing up…',
        ));
      }
      await _flush();
    }

    await _flush();

    // A run where NOTHING got through is a failure, not a success with a small
    // number in it. The old message was "Backed up. 0 new, 0 already there."
    // whatever had happened — so an expired session, a lapsed licence or a
    // sleeping laptop all read as a completed backup, and the photos were not
    // there. That is the worst outcome this app can produce: it is the one
    // screen whose entire promise is "your photos are safe now".
    final nothingWorked = handledFail > 0 && handledDone == 0;
    final someFailed = handledFail > 0;

    _emit(BackupProgress(
      state: _stop
          ? BackupState.paused
          : nothingWorked
              ? BackupState.failed
              : BackupState.done,
      total: count,
      done: handledDone,
      skipped: handledSkip,
      failed: handledFail,
      message: _stop
          ? 'Stopped — nothing is lost, it carries on from here next time.'
          : nothingWorked
              ? 'Nothing could be backed up. ${_lastProblem ?? ""}'.trim()
              : someFailed
                  // Named, and the count kept, so a partial run cannot pass for
                  // a whole one. They are not marked sent, so the next run
                  // retries exactly these.
                  ? '$handledDone backed up, $handledSkip already there, '
                      '$handledFail could not be sent. '
                      '${_lastProblem ?? ""} They will be tried again next time.'
                      .trim()
                  : 'Backed up. $handledDone new, $handledSkip already there.',
    ));
  }

  /// Why the most recent failures failed, in the server's own terms. Kept so the
  /// screen can say something true instead of "could not be read".
  String? _lastProblem;

  Future<bool> _send(AssetEntity asset) async {
    try {
      // originFile, not file: `file` hands back a transcoded copy on iOS, which
      // is slower and loses the original. The server decodes HEIC itself.
      final f = await asset.originFile;
      if (f == null || !await f.exists()) {
        _lastProblem = 'Some photos are stored in iCloud and are not on this '
            'phone. Open them in Photos once, or turn off "Optimise Storage".';
        return false;
      }
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) {
        _lastProblem = 'Some photos are in iCloud rather than on the phone.';
        return false;
      }

      final status = await _upload(bytes, asset.title ?? '${asset.id}.jpg');
      if (status >= 200 && status < 300) {
        await _remember(asset.id);
        return true;
      }
      // Naming the cause is the entire difference between a person fixing this
      // in ten seconds and reporting "backup does not work".
      _lastProblem = switch (status) {
        0 => 'Your computer could not be reached. Check it is awake and that '
            'the address in Profile is right.',
        401 => 'Your session has expired. Sign out and back in.',
        402 => 'The licence on your computer needs attention — photos cannot '
            'be added until it does.',
        403 => 'This account is not allowed to add photos.',
        413 => 'Some photos are larger than your computer will accept.',
        >= 500 => 'Your computer answered with an error ($status). Its own '
            'console may say more.',
        _ => 'Your computer refused the upload ($status).',
      };
      return false;
    } catch (_) {
      _lastProblem = 'Something went wrong reading a photo from this phone.';
      return false;
    }
  }

  /// Returns the HTTP status: 2xx is a success, 0 means it never arrived.
  Future<int> _upload(Uint8List bytes, String name) async {
    // Multipart by hand rather than pulling in a client: one field, one file, and
    // the server's /api/gallery/upload has been driven with exactly this shape.
    final boundary = '----safenest${DateTime.now().microsecondsSinceEpoch}';

    // A filename is a header VALUE. A quote, a newline or a stray CR in a photo
    // title would break the Content-Disposition line and, with a newline, let
    // the name inject headers of its own. Phone camera names are tame; names
    // that came off a computer, a messaging app or a rename are not.
    final safe = name
        .replaceAll(RegExp(r'[\r\n"\\]'), '_')
        .replaceAll(RegExp(r'[\x00-\x1f]'), '_');

    final head = utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$safe"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--\r\n');

    // A BytesBuilder, not `<int>[...head, ...bytes, ...tail]`.
    //
    // That spread built a growable List<int> of BOXED integers — for a 4 MB
    // photo, four million heap objects instead of a four-megabyte buffer, and
    // four of those alive at once because uploads run four at a time. On a
    // phone backing up a large library that is an out-of-memory kill, and the
    // library most worth backing up is the biggest one.
    final buf = BytesBuilder(copy: false)
      ..add(head)
      ..add(bytes)
      ..add(tail);

    try {
      return await _api.postRawStatus(
        '/api/gallery/upload?faces=0',
        buf.takeBytes(),
        'multipart/form-data; boundary=$boundary',
      );
    } catch (_) {
      return 0;
    }
  }
}
