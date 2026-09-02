/// Talking to the customer's own SafeNest, and nothing else.
///
/// The web app's api.ts is the model for this, deliberately — the same server,
/// the same JWT, the same errors — so a fix in one is a fix worth copying to the
/// other rather than a difference to discover later.
///
/// TWO THINGS CARRIED OVER FROM ITS MISTAKES
///
/// A validation failure answers with a LIST of objects, not a string. Rendering
/// that naively produced the literal text "[object Object]" in the web app, shown
/// to a real person, saying nothing. `_readable` unpacks it here from the start.
///
/// The base address is the CUSTOMER'S machine, and there is no default for it.
/// Nothing in this app may ever point at the publisher's server: that was a real
/// bug in the desktop product, where a hard-coded address meant every customer's
/// Profile screen advertised somebody else's domain as "your web address".
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'dart:typed_data' show BytesBuilder;
import 'dart:io';

import 'package:http/http.dart' as http;

/// An upload that ran out of time rather than failing to connect.
///
/// Negative so it can never collide with an HTTP status, and distinct from 0,
/// which means "could not reach it at all".
const int kTimedOut = -2;

class ApiError implements Exception {
  ApiError(this.status, this.message, {this.offline = false, this.licence});
  final int status;
  final String message;
  final bool offline;

  /// The licence gate answers 402 with {state, expires_on, key_id} beside the
  /// message. Kept whole rather than flattened to a sentence: "expired" and
  /// "withdrawn" need different things said to the person, and the key id is
  /// what they will be asked for when they get in touch.
  final Map<String, dynamic>? licence;

  bool get licenceBlocked => status == 402;

  @override
  String toString() => message;
}

const _offlineMsg = 'No connection — your records are on your own computer, '
    'and this phone cannot reach it right now.';
const _unreachableMsg = 'Cannot reach your SafeNest. Check the address, and that '
    'the computer running it is switched on.';

class Api {
  Api({required this.baseUrl, this.token, this.onLicenceBlocked});

  /// Told whenever the server refuses on licence grounds, so the whole app can
  /// say so once instead of every screen discovering it separately. The gate is
  /// global — middleware over every /api/ path — so the answer to it should be
  /// global too.
  final void Function(ApiError)? onLicenceBlocked;

  /// e.g. https://finmate.example.com — the customer's own address.
  final String baseUrl;
  String? token;

  Uri _url(String path, [Map<String, String>? query]) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path')
          .replace(queryParameters: query);

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _send(() => http.get(_url(path, query), headers: _headers(json: false)));

  Future<dynamic> post(String path, [Object? body]) => _send(() => http.post(
        _url(path),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      ));

  Future<dynamic> put(String path, [Object? body]) => _send(() => http.put(
        _url(path),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      ));

  Future<dynamic> delete(String path) =>
      _send(() => http.delete(_url(path), headers: _headers(json: false)));

  /// Fetch a file's bytes — a document to open, an export to save.
  ///
  /// Signed and expiring on the server, and bound to the owner, so this cannot
  /// be handed to an external viewer as a URL and fetched later: by then the
  /// signature has lapsed. It is downloaded here and written to a temporary file
  /// instead, which is also the only way a PDF viewer on the phone can see it.
  Future<List<int>> download(String path) async {
    final res = await http.get(_url(path), headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    }).timeout(const Duration(minutes: 5));
    if (res.statusCode >= 400) {
      throw ApiError(res.statusCode,
          res.statusCode == 404 ? 'That file is no longer there' : 'Could not fetch it');
    }
    return res.bodyBytes;
  }

  /// One file plus form fields, framed by hand.
  ///
  /// By hand rather than with a client package because the framing has to match
  /// what the server's UploadFile expects exactly, and that shape has already
  /// been driven end to end against these endpoints.
  /// Builds the multipart body. Shared so the two callers cannot drift.
  ///
  /// A BytesBuilder rather than `<int>[]` + addAll: that builds a growable list
  /// of BOXED integers, which for an 8 MB image is eight million heap objects
  /// instead of an eight-megabyte buffer.
  List<int> _multipart(
    String boundary, {
    required String fileField,
    required String filename,
    required List<int> bytes,
    Map<String, String> fields = const {},
  }) {
    // A filename is a header VALUE — a quote or a newline in it breaks the
    // Content-Disposition line, and a newline can inject headers of its own.
    final safe = filename
        .replaceAll(RegExp(r'[\r\n"\\]'), '_')
        .replaceAll(RegExp(r'[\x00-\x1f]'), '_');

    final buf = BytesBuilder(copy: false);
    void add(String s) => buf.add(utf8.encode(s));

    fields.forEach((k, v) {
      add('--$boundary\r\nContent-Disposition: form-data; name="$k"\r\n\r\n$v\r\n');
    });
    add('--$boundary\r\n'
        'Content-Disposition: form-data; name="$fileField"; filename="$safe"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n');
    buf.add(bytes);
    add('\r\n--$boundary--\r\n');
    return buf.takeBytes();
  }

  /// Upload and return the parsed reply, THROWING ApiError with whatever the
  /// server said.
  ///
  /// `postMultipart` returns a bool, which throws away the one useful thing:
  /// this endpoint answers "Image too large (max 8 MB)" and "That file isn't a
  /// readable image", and a person can act on either. A bare false leaves them
  /// pressing the same button again.
  Future<dynamic> postMultipartJson(
    String path, {
    required String fileField,
    required String filename,
    required List<int> bytes,
    Map<String, String> fields = const {},
  }) async {
    final boundary = '----safenest${DateTime.now().microsecondsSinceEpoch}';
    final body = _multipart(boundary,
        fileField: fileField, filename: filename, bytes: bytes, fields: fields);

    http.Response res;
    try {
      res = await http
          .post(_url(path),
              headers: {
                'Content-Type': 'multipart/form-data; boundary=$boundary',
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: body)
          .timeout(const Duration(minutes: 5));
    } on SocketException {
      throw ApiError(0, _offlineMsg, offline: true);
    } catch (_) {
      throw ApiError(0, _unreachableMsg, offline: true);
    }

    dynamic data;
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body);
      } catch (_) {
        data = res.body;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    final detail = (data is Map && data['detail'] != null)
        ? '${data['detail']}'
        : 'That could not be uploaded (${res.statusCode}).';
    throw ApiError(res.statusCode, detail);
  }

  /// SEVERAL files under the SAME field name, plus form fields.
  ///
  /// `POST /api/documents/scan` takes `files: list[UploadFile]` — one part per
  /// page, in order — and assembles them into a single multi-page PDF. A
  /// scanned passport is one document, not a pile of loose photos, and nothing
  /// here could send more than one file at a time.
  ///
  /// Order is the order of the list, and it matters: it becomes the page order
  /// of the PDF.
  Future<dynamic> postMultipartFiles(
    String path, {
    required String fileField,
    required List<({String name, List<int> bytes})> files,
    Map<String, String> fields = const {},
  }) async {
    final boundary = '----safenest${DateTime.now().microsecondsSinceEpoch}';
    final buf = BytesBuilder(copy: false);
    void add(String s) => buf.add(utf8.encode(s));

    fields.forEach((k, v) {
      add('--$boundary\r\nContent-Disposition: form-data; name="$k"\r\n\r\n$v\r\n');
    });
    for (final f in files) {
      final safe = f.name
          .replaceAll(RegExp(r'[\r\n"\\]'), '_')
          .replaceAll(RegExp(r'[\x00-\x1f]'), '_');
      add('--$boundary\r\n'
          'Content-Disposition: form-data; name="$fileField"; filename="$safe"\r\n'
          'Content-Type: image/jpeg\r\n\r\n');
      buf.add(f.bytes);
      add('\r\n');
    }
    add('--$boundary--\r\n');

    http.Response res;
    try {
      res = await http
          .post(_url(path),
              headers: {
                'Content-Type': 'multipart/form-data; boundary=$boundary',
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: buf.takeBytes())
          .timeout(const Duration(minutes: 5));
    } on SocketException {
      throw ApiError(0, _offlineMsg, offline: true);
    } catch (_) {
      throw ApiError(0, _unreachableMsg, offline: true);
    }

    dynamic data;
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body);
      } catch (_) {
        data = res.body;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final detail = (data is Map && data['detail'] != null)
        ? '${data['detail']}'
        : 'That could not be saved (${res.statusCode}).';
    throw ApiError(res.statusCode, detail);
  }

  Future<bool> postMultipart(
    String path, {
    required String fileField,
    required String filename,
    required List<int> bytes,
    Map<String, String> fields = const {},
  }) async {
    final boundary = '----safenest${DateTime.now().microsecondsSinceEpoch}';
    final body = _multipart(boundary,
        fileField: fileField, filename: filename, bytes: bytes, fields: fields);
    try {
      final res = await http
          .post(_url(path),
              headers: {
                'Content-Type': 'multipart/form-data; boundary=$boundary',
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: body)
          .timeout(const Duration(minutes: 5));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// A body we have already framed ourselves — one photo, as multipart.
  ///
  /// Returns true for "the server has this photo", which INCLUDES the duplicate
  /// answer. A photo the server already had is not a failure to retry for ever;
  /// it is the backup working, and counting it as an error would make every
  /// second run look broken.
  /// Returns the HTTP status, or 0 when the request never got an answer.
  ///
  /// This used to return a bare bool, and that is precisely why a failing
  /// backup could not be reported: an expired token (401), a lapsed licence
  /// (402), a file the server refused (413) and a dropped connection all
  /// collapsed into `false`. The screen could then only say "could not be
  /// read", which is not even the right half of the system — the photo read
  /// perfectly, the upload failed.
  ///
  /// Keeping the status is what separates "sign in again" from "your laptop is
  /// asleep", and the person can act on exactly one of those.
  /// Status AND body. `postRawStatus` throws the body away, which was fine
  /// until a caller needed to know WHAT the server did, not just that it
  /// worked: /api/gallery/upload answers 200 for a photo it already had, with
  /// `duplicate: true` in the body. Counting that as a new upload is how a
  /// backup reported thousands sent while the gallery gained none.
  /// How long to allow for a body of this size.
  ///
  /// A FLAT FIVE MINUTES WAS THE BUG. backup.dart measured 51 MB in 67 seconds
  /// over the tunnel -- about 0.76 MB/s on a home upstream -- so a 250 MB clip
  /// needs five and a half minutes and timed out at five. Worse, every
  /// exception here became `status: 0`, which the backup screen reports as
  /// "your computer could not be reached", sending somebody to check a network
  /// that was working perfectly. Reported by a customer: 1,137 photos through,
  /// 22 videos refused, all blamed on reachability.
  ///
  /// Allows 100 KB/s, which is well below the measured rate, with a five-minute
  /// floor. A timeout is a last resort against something genuinely stuck, not a
  /// budget for how fast an upload ought to be.
  @visibleForTesting
  static Duration uploadTimeout(int bytes) => _uploadTimeout(bytes);

  static Duration _uploadTimeout(int bytes) {
    final seconds = bytes ~/ 100000;
    return Duration(seconds: seconds < 300 ? 300 : seconds);
  }

  Future<({int status, Map<String, dynamic> body})> postRawResult(
      String path, List<int> body, String contentType) async {
    try {
      final res = await http
          .post(_url(path),
              headers: {
                'Content-Type': contentType,
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: body)
          .timeout(_uploadTimeout(body.length));
      Map<String, dynamic> parsed = const {};
      try {
        final d = jsonDecode(res.body);
        if (d is Map) parsed = d.cast<String, dynamic>();
      } catch (_) {
        // A body that is not JSON is not a reason to fail an upload that the
        // status code says succeeded.
      }
      return (status: res.statusCode, body: parsed);
    } on TimeoutException {
      // NOT the same as unreachable, and saying so matters: one means check
      // the network, the other means the file is large or the link is slow.
      // Collapsing both into 0 is what had a customer checking a computer that
      // was awake the whole time.
      return (status: kTimedOut, body: const <String, dynamic>{});
    } catch (_) {
      return (status: 0, body: const <String, dynamic>{});
    }
  }

  Future<int> postRawStatus(String path, List<int> body, String contentType) async {
    try {
      final res = await http
          .post(_url(path),
              headers: {
                'Content-Type': contentType,
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: body)
          .timeout(const Duration(minutes: 5));
      return res.statusCode;
    } catch (_) {
      return 0;   // never reached the server at all
    }
  }

  Future<bool> postRaw(String path, List<int> body, String contentType) async {
    final s = await postRawStatus(path, body, contentType);
    return s >= 200 && s < 300;
  }

  Future<dynamic> _send(Future<http.Response> Function() run) async {
    http.Response res;
    try {
      res = await run().timeout(const Duration(seconds: 60));
    } on SocketException {
      throw ApiError(0, _offlineMsg, offline: true);
    } catch (_) {
      throw ApiError(0, _unreachableMsg, offline: true);
    }

    dynamic data;
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body);
      } catch (_) {
        data = res.body;
      }
    }

    if (res.statusCode == 402) {
      // The licence gate. Reads and writes are refused, but an export never is —
      // a lapsed licence ends the right to USE the software, it does not make
      // somebody's records ours to withhold.
      final err = ApiError(
        402,
        _detailOf(data) ?? 'This copy of SafeNest needs its licence renewing.',
        licence: (data is Map && data['licence'] is Map)
            ? Map<String, dynamic>.from(data['licence'] as Map)
            : null,
      );
      onLicenceBlocked?.call(err);
      throw err;
    }
    // A GATEWAY error is not the app failing. 502/503/504 come from the tunnel
    // in front of it: Cloudflare answered, the computer behind it did not. That
    // is the laptop asleep, the API not started, or the terminal closed — none
    // of which is a bug in SafeNest.
    //
    // Lumping these in with 500 told a real person "your SafeNest ran into a
    // problem" while the truth was that it was not running, and sent them
    // looking at the app instead of at the machine. The web client already drew
    // this distinction; it was not carried across, and it cost a sign-in that
    // looked like a broken app.
    if (res.statusCode == 502 || res.statusCode == 503 || res.statusCode == 504) {
      throw ApiError(res.statusCode,
          'Your computer is not answering. Check that it is switched on and '
          'that SafeNest is running on it.',
          offline: true);
    }
    if (res.statusCode >= 500) {
      throw ApiError(res.statusCode, 'Your SafeNest ran into a problem.');
    }
    if (res.statusCode >= 400) {
      throw ApiError(res.statusCode,
          _detailOf(data) ?? _readable(null, res.statusCode));
    }
    return data;
  }

  String? _detailOf(dynamic data) {
    if (data is Map && data['detail'] != null) {
      return _readable(data['detail'], 0);
    }
    return null;
  }

  /// Whatever came back in `detail`, as a sentence a person can read.
  static String _readable(dynamic detail, int status) {
    if (detail is String && detail.isNotEmpty) return detail;

    String one(dynamic v) {
      if (v is String) return v;
      if (v is Map && v['msg'] is String) {
        // loc is ["body", "name"] — the last part names the field that upset it,
        // which is the difference between "invalid" and "which one?".
        final loc = v['loc'];
        final field = (loc is List && loc.isNotEmpty) ? loc.last : null;
        return (field != null && field != 'body')
            ? '$field: ${v['msg']}'
            : v['msg'] as String;
      }
      return '';
    }

    if (detail is List) {
      final parts = detail.map(one).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.join('; ');
    }
    final single = one(detail);
    if (single.isNotEmpty) return single;
    // Never fall through to printing an object. A status code is not much, but
    // it is honest, and "[object Object]" is not even that.
    return status == 422
        ? 'The app sent something this screen could not accept'
        : 'Request failed${status > 0 ? ' ($status)' : ''}';
  }
}
