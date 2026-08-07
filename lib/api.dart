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

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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
  Future<bool> postMultipart(
    String path, {
    required String fileField,
    required String filename,
    required List<int> bytes,
    Map<String, String> fields = const {},
  }) async {
    final boundary = '----safenest${DateTime.now().microsecondsSinceEpoch}';
    final body = <int>[];
    void add(String s) => body.addAll(utf8.encode(s));

    fields.forEach((k, v) {
      add('--$boundary\r\nContent-Disposition: form-data; name="$k"\r\n\r\n$v\r\n');
    });
    add('--$boundary\r\n'
        'Content-Disposition: form-data; name="$fileField"; filename="$filename"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n');
    body.addAll(bytes);
    add('\r\n--$boundary--\r\n');

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
  Future<bool> postRaw(String path, List<int> body, String contentType) async {
    try {
      final res = await http
          .post(_url(path),
              headers: {
                'Content-Type': contentType,
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: body)
          .timeout(const Duration(minutes: 5));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
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
