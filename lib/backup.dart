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
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';

enum BackupState { idle, scanning, running, paused, done, failed }

/// What happened to one photo. `already` is the one the old bool could not
/// express: the upload succeeded and yet nothing new exists on the server.
enum _Sent { stored, already, failed }

class BackupProgress {
  const BackupProgress({
    this.state = BackupState.idle,
    this.total = 0,
    this.done = 0,
    this.skipped = 0,
    this.failed = 0,
    this.message = '',
    this.reasons = const {},
    this.retryable = 0,
  });

  final BackupState state;
  final int total;      // photos this run has to consider
  final int done;       // uploaded now
  final int skipped;    // already on the server from a previous run
  final int failed;
  final String message;

  /// Why photos did not go, and how many for each cause.
  ///
  /// This was one String, overwritten by every failure, so a run where forty
  /// photos were stuck in iCloud and three hit an expired session reported
  /// only whichever happened last. One cause is a thing you fix; "some
  /// unspecified problem" is a thing you give up on.
  final Map<String, int> reasons;

  /// How many failures are worth trying again without rescanning the library.
  final int retryable;

  int get handled => done + skipped + failed;

  /// Clamped, because a LinearProgressIndicator asserts on a value outside
  /// 0..1 and the count it is derived from comes from the phone's library —
  /// which can change under a run that takes twenty minutes. A photo deleted
  /// mid-backup would otherwise crash the screen rather than nudge the bar.
  double get fraction =>
      total == 0 ? 0 : (handled / total).clamp(0.0, 1.0).toDouble();
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

  /// A run is in progress. Guards against a second loop starting over the same
  /// _sent/_failed state — the backup path's version of the gallery's "a reset
  /// is never dropped" rule. Set synchronously before the first await, because
  /// runFullBackup awaits _keepAwake() before the UI flips to running, and a
  /// fast double-tap in that gap would otherwise launch two concurrent backups.
  bool _busy = false;
  bool get busy => _busy;

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

  /// Forget what has already been sent, so the next run offers everything again.
  ///
  /// WITHOUT THIS THERE IS NO WAY BACK from a deletion on the computer. This
  /// list lives on the phone and says "already backed up"; the server knowing
  /// nothing about a photo does not change it. So when photos are removed at
  /// the computer — emptying the bin there, a restore gone wrong, a disk
  /// replaced — running the backup again skips every one of them and reports a
  /// clean success, and the photos are on the phone the whole time.
  ///
  /// That happened here: an empty-bin on the computer removed a whole library,
  /// and "back up my photos" would have said "0 new, 20,000 already there".
  ///
  /// It costs a re-upload of everything, which the server de-duplicates by
  /// content hash — so anything still on the computer is recognised and
  /// nothing is stored twice. Slow, never destructive.
  Future<void> forgetSent() async {
    // Not while a backup is running. The running loop keeps its own copy of
    // this list in memory and re-persists it every page (_flush), so clearing
    // it here would look done and then silently undo itself on the next page —
    // the "reset dropped while a page is in flight" trap the gallery already
    // fixed. Stop first, reset then; never pretend to reset.
    if (_busy) {
      _emit(const BackupProgress(
          message: 'Stop the backup that is running, then reset.'));
      return;
    }
    _sent.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sentKey);
    _emit(const BackupProgress(
        message: 'Ready to check every photo again. Nothing has been deleted '
            'from this phone.'));
  }

  /// How many photos this phone believes are already on the computer.
  int get rememberedCount => _sent.length;


  /// Ask the server which of these it already holds, by content.
  ///
  /// Returns the asset ids to skip. Failure returns EMPTY, never throws: this
  /// is an optimisation, and a backup must still work against a server too old
  /// to answer — or one that is simply having a bad moment.
  Future<Set<String>> _serverAlreadyHas(List<AssetEntity> assets) async {
    final byHash = <String, String>{};   // hash -> asset id
    for (final a in assets) {
      try {
        final f = await a.originFile;
        if (f == null || !await f.exists()) continue;
        // Streamed rather than readAsBytes: a 4K video is hundreds of
        // megabytes and holding one in memory to hash it is how a phone runs
        // out, which is the thing this whole file keeps having to avoid.
        final digest = await sha256.bind(f.openRead()).first;
        byHash[digest.toString()] = a.id;
      } catch (_) {
        // Unreadable here means unreadable at upload time too, and _send will
        // report it properly with a reason.
      }
    }
    if (byHash.isEmpty) return const {};
    try {
      final r = await _api.post('/api/gallery/have',
          {'hashes': byHash.keys.toList()});
      final have = (r is Map ? r['have'] as List? : null) ?? const [];
      return {
        for (final h in have)
          if (byHash.containsKey('$h')) byHash['$h']!
      };
    } catch (_) {
      return const {};
    }
  }

  /// How many items the computer actually holds for this account. A cheap way to
  /// notice a stale "already sent" list — ask for one item and read the true total.
  /// Returns null if it cannot ask (offline, old server); the caller then keeps
  /// trusting its local list, exactly as before.
  Future<int?> _serverItemCount() async {
    try {
      final r = await _api.get('/api/gallery', {'limit': '1'});
      final t = (r is Map) ? r['total'] : null;
      if (t is int) return t;
      return int.tryParse('$t');
    } catch (_) {
      return null;
    }
  }

  void stop() => _stop = true;

  /// Keep the screen on for the length of a run, and only that long.
  ///
  /// A phone dims and sleeps an idle screen after a minute or two, and that
  /// suspends the app — so a backup of a large library stopped shortly after
  /// it was started and sat there looking frozen. The only workaround was
  /// tapping the screen every minute for half an hour.
  ///
  /// Released in a `finally`, never on the happy path alone: a backup that
  /// throws must not leave the phone awake all night, because a flat battery
  /// in the morning is blamed on this app and is a fair thing to blame it for.
  Future<void> _keepAwake(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // Not worth failing a backup over. On a device that refuses it the run
      // still works; it just needs the screen touched.
    }
  }


  /// Ask for the library. Note `PermissionState.limited`: iOS lets someone grant
  /// access to a HANDFUL of photos, and an app that treats that as "granted"
  /// silently backs up four pictures and reports success. It has to be named.
  Future<PermissionState> requestAccess() =>
      PhotoManager.requestPermissionExtend();

  Future<void> runFullBackup() async {
    if (_busy) return;   // a double-tap must not launch a second loop
    _busy = true;
    await _keepAwake(true);
    try {
      await _runFullBackup();
    } finally {
      await _keepAwake(false);
      _busy = false;
    }
  }

  Future<void> _runFullBackup() async {
    _stop = false;
    // A fresh run's failures are its own. Carrying the previous run's causes
    // over would report a problem that has just been fixed.
    _problems.clear();
    _failedAssets.clear();
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

    // Catch a STALE "already sent" list before trusting it to skip anything.
    //
    // That list lives on this phone and says "already backed up". If the computer
    // now holds FEWER items than the list claims to have sent, photos were removed
    // there (its bin emptied, a disk swapped, a restore gone wrong) — and every one
    // of them would be skipped for ever, reported as a clean success, while sitting
    // unprotected on the phone the whole time. It is the exact failure forgetSent()
    // exists to undo, done automatically. Trust the computer over our memory: clear
    // the list and re-check everything against the server, which de-duplicates by
    // hash so nothing still there is stored twice. Safe in one direction only — the
    // worst case is a needless re-check, never a skipped photo.
    final serverCount = await _serverItemCount();
    if (serverCount != null && serverCount < _sent.length) {
      _sent.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sentKey);
    }

    // Photos AND videos. This said `RequestType.image` with the note "videos
    // are not photos and the gallery cannot store them" — true when it was
    // written, and no longer: the server takes video now, makes a still from it
    // and files it beside the photos. A backup that silently skipped every clip
    // somebody had ever taken was the largest hole in a thing called "back up
    // my phone", and nothing on screen said it was happening.
    final albums = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.common,
    );
    if (albums.isEmpty) {
      _emit(const BackupProgress(
          state: BackupState.done,
          message: 'No photos or videos found on this phone.'));
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

    // Emitting the current counts. Hoisted out because it has to happen in
    // THREE places, and only one of them used to do it.
    void report() => _emit(BackupProgress(
          state: BackupState.running,
          total: count,
          done: handledDone,
          skipped: handledSkip,
          failed: handledFail,
          message: 'Backing up…',
        ));

    for (var offset = 0; offset < count; offset += page) {
      if (_stop) break;
      final batch = await all.getAssetListRange(start: offset, end: offset + page);
      var todo = batch.where((a) => !_sent.contains(a.id)).toList();
      handledSkip += batch.length - todo.length;

      // ASK THE COMPUTER WHAT IT ALREADY HAS, before sending anything.
      //
      // The skip above uses a list kept on THIS phone. That list is local: a
      // reinstall, cleared app data, or the "photos missing on the computer"
      // reset all leave it empty, and the phone then has to assume it has sent
      // nothing. It would upload the entire library — gigabytes over a home
      // connection — for the computer to recognise nearly all of it and store
      // none of it. The work was always avoidable; there was simply no way to
      // ask.
      //
      // Hashing costs a read of a file that was about to be uploaded anyway,
      // and the answer is a few hundred bytes. On a library already backed up
      // this turns hours into seconds.
      if (todo.isNotEmpty) {
        final known = await _serverAlreadyHas(todo);
        if (known.isNotEmpty) {
          for (final a in todo) {
            if (known.contains(a.id)) await _remember(a.id);
          }
          final before = todo.length;
          todo = todo.where((a) => !known.contains(a.id)).toList();
          handledSkip += before - todo.length;
        }
      }

      // THE PROGRESS BAR FREEZING WAS THIS.
      //
      // The only report() used to be inside the upload loop below. A page whose
      // photos are ALL already backed up has an empty `todo`, so that loop never
      // runs and nothing was emitted — `skipped` climbed by 200 in silence and
      // the bar did not move.
      //
      // Which means it looked broken on precisely the runs people do most: the
      // second one, and every one after it. A first backup uploads everything
      // and moves smoothly; a repeat backup skips nearly everything, sat at 0%
      // through the whole library, then jumped to 100% at the end.
      report();

      // Four at a time, matching what the server was measured to do best.
      for (var i = 0; i < todo.length; i += _concurrency) {
        if (_stop) break;
        final slice = todo.skip(i).take(_concurrency).toList();
        final results = await Future.wait(slice.map(_send));
        for (var k = 0; k < results.length; k++) {
          switch (results[k]) {
            case _Sent.stored:
              handledDone++;
            case _Sent.already:
              // Already on the server. Counted with the ones skipped locally,
              // because to the person watching they are the same thing: not a
              // new photo.
              handledSkip++;
            case _Sent.failed:
              handledFail++;
              // Kept so "try these again" does not mean "walk the library
              // again".
              _failedAssets.add(slice[k]);
          }
        }
        report();
      }
      await _flush();
      report();
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
      reasons: Map.unmodifiable(_problems),
      retryable: _failedAssets.length,
      message: _stop
          ? 'Stopped — nothing is lost, it carries on from here next time.'
          : nothingWorked
              ? 'Nothing could be backed up.'
              : someFailed
                  // Named, and the count kept, so a partial run cannot pass for
                  // a whole one. They are not marked sent, so they can be tried
                  // again without rescanning anything.
                  ? '$handledDone backed up, $handledSkip already there, '
                      '$handledFail could not be sent.'
                  : 'Backed up. $handledDone new, $handledSkip already there.',
    ));
  }

  /// Try only the photos that did not go.
  ///
  /// Almost every backup failure here is one cause affecting many photos — a
  /// sleeping computer, an expired session, a licence needing attention — and
  /// all of them are fixed in seconds. Making someone re-run the whole library
  /// to find out whether it worked is what turns a ten-second fix into "the
  /// backup is broken". This walks only what failed, so it finishes in about
  /// as long as the fix took.
  Future<void> retryFailed() async {
    if (_failedAssets.isEmpty) return;
    if (_busy) return;   // shares _failedAssets/_sent with a live run
    _busy = true;
    await _keepAwake(true);
    try {
      await _retryFailed();
    } finally {
      await _keepAwake(false);
      _busy = false;
    }
  }

  Future<void> _retryFailed() async {
    _stop = false;
    final queue = List<AssetEntity>.from(_failedAssets);
    _failedAssets.clear();
    _problems.clear();

    final total = queue.length;
    var ok = 0, bad = 0;
    void report() => _emit(BackupProgress(
          state: BackupState.running,
          total: total,
          done: ok,
          failed: bad,
          message: 'Trying $total photo${total == 1 ? '' : 's'} again…',
        ));
    report();

    for (var i = 0; i < queue.length; i += _concurrency) {
      if (_stop) break;
      final slice = queue.skip(i).take(_concurrency).toList();
      final results = await Future.wait(slice.map(_send));
      for (var k = 0; k < results.length; k++) {
        if (results[k] == _Sent.failed) {
          bad++;
          _failedAssets.add(slice[k]);
        } else {
          ok++;
        }
      }
      report();
    }
    await _flush();

    _emit(BackupProgress(
      state: _stop
          ? BackupState.paused
          : (bad > 0 && ok == 0 ? BackupState.failed : BackupState.done),
      total: total,
      done: ok,
      failed: bad,
      reasons: Map.unmodifiable(_problems),
      retryable: _failedAssets.length,
      message: _stop
          ? 'Stopped.'
          : bad == 0
              ? 'All $ok went through this time.'
              : '$ok went through, $bad still could not be sent.',
    ));
  }

  /// Why failures failed, in the server's own terms, counted per cause.
  final Map<String, int> _problems = {};

  /// The photos that did not go, so they can be retried directly instead of
  /// walking the whole library again. A retry after fixing the cause — waking
  /// the computer, signing back in — should take seconds, not another full
  /// scan of twenty thousand photos.
  final List<AssetEntity> _failedAssets = [];

  void _blame(String reason) => _problems[reason] = (_problems[reason] ?? 0) + 1;

  /// The causes, worst first, as sentences a person can act on.
  List<String> get problemLines {
    final e = _problems.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final x in e) '${x.value} photo${x.value == 1 ? '' : 's'}: ${x.key}'];
  }

  /// What became of one photo. `bool` could not tell "stored" from "the server
  /// already had it", and the difference is the whole of the count mismatch.
  Future<_Sent> _send(AssetEntity asset) async {
    try {
      // originFile, not file: `file` hands back a transcoded copy on iOS, which
      // is slower and loses the original. The server decodes HEIC itself.
      final f = await asset.originFile;
      if (f == null || !await f.exists()) {
        _blame('stored in iCloud rather than on this phone. Open them in '
            'Photos once, or turn off "Optimise Storage".');
        return _Sent.failed;
      }
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) {
        _blame('in iCloud rather than on the phone.');
        return _Sent.failed;
      }

      final r = await _upload(bytes, asset.title ?? '${asset.id}.jpg');
      if (r.status >= 200 && r.status < 300) {
        await _remember(asset.id);
        // The server answers 200 for a photo it already holds, saying so in
        // the body. Counted as new, that is a backup claiming to have sent
        // thousands while the gallery gains none — which is exactly what a
        // reinstall looked like, because the phone's "already sent" memory is
        // local and starts empty.
        return r.body['duplicate'] == true ? _Sent.already : _Sent.stored;
      }
      // Naming the cause is the entire difference between a person fixing this
      // in ten seconds and reporting "backup does not work".
      _blame(switch (r.status) {
        0 => 'your computer could not be reached. Check it is awake and that '
            'the address in Profile is right.',
        401 => 'your session has expired. Sign out and back in.',
        402 => 'the licence on your computer needs attention — photos cannot '
            'be added until it does.',
        403 => 'this account is not allowed to add photos.',
        413 => 'they are larger than your computer will accept.',
        >= 500 => 'your computer answered with an error (${r.status}). Its own '
            'console may say more.',
        _ => 'your computer refused the upload (${r.status}).',
      });
      return _Sent.failed;
    } catch (_) {
      _blame('could not be read from this phone.');
      return _Sent.failed;
    }
  }

  /// Returns the HTTP status: 2xx is a success, 0 means it never arrived.
  Future<({int status, Map<String, dynamic> body})> _upload(
      Uint8List bytes, String name) async {
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
      return await _api.postRawResult(
        '/api/gallery/upload?faces=0',
        buf.takeBytes(),
        'multipart/form-data; boundary=$boundary',
      );
    } catch (_) {
      return (status: 0, body: const <String, dynamic>{});
    }
  }
}
