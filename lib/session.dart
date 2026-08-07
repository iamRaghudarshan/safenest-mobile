/// Who is signed in, and to WHICH SafeNest.
///
/// The second half is not a detail. Every customer runs their own copy on their
/// own machine, so there is no such thing as "the server" — the address is
/// something this app is told and must never assume. There is deliberately no
/// default and no fallback: a hard-coded address was a real bug in the desktop
/// product, where every customer's screen ended up advertising the publisher's
/// own domain as though it were theirs.
///
/// The token lives in the Keychain on iOS and the Keystore on Android, not in
/// SharedPreferences — that is a plain XML file, readable by anything with root,
/// and this token opens somebody's financial records.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'masters.dart';

class Session extends ChangeNotifier {
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _kUrl = 'server.url';
  static const _kToken = 'server.token';

  String? _baseUrl;
  String? _token;
  Map<String, dynamic>? _user;
  bool _loading = true;

  String? get baseUrl => _baseUrl;
  Map<String, dynamic>? get user => _user;
  bool get loading => _loading;
  bool get signedIn => _token != null && _baseUrl != null;

  /// Set when the customer's copy refuses on licence grounds. The app shows one
  /// notice rather than each screen reporting it as its own failure.
  ApiError? _licence;
  ApiError? get licenceBlock => _licence;

  void clearLicenceBlock() {
    if (_licence == null) return;
    _licence = null;
    notifyListeners();
  }

  Api get api => Api(
        baseUrl: _baseUrl ?? '',
        token: _token,
        onLicenceBlocked: (e) {
          if (_licence?.message == e.message) return;   // do not loop on repeats
          _licence = e;
          notifyListeners();
        },
      );

  /// The user's category and bank lists, fetched once per run.
  ///
  /// Lives on the Session rather than in each screen because a record sheet and
  /// the Masters screen must agree: editing a category there has to change what
  /// the sheet offers here, and two independent caches would drift until the
  /// app was restarted.
  ///
  /// `() => api`, not `api` — see MasterCache. And cleared on sign-out below,
  /// because these lists are per USER: a household member signing in after
  /// somebody else would otherwise be offered the previous person's categories.
  late final MasterCache masters = MasterCache(() => api);

  Future<void> restore() async {
    _baseUrl = await _store.read(key: _kUrl);
    _token = await _store.read(key: _kToken);
    if (signedIn) {
      // Confirm the token is still good rather than assuming. Changing the
      // password bumps users.token_version on the server, which kills every
      // existing token — so a stored one can be perfectly well-formed and dead.
      try {
        final me = await api.get('/api/auth/me');
        _user = (me is Map && me['user'] is Map)
            ? Map<String, dynamic>.from(me['user'] as Map)
            : (me is Map ? Map<String, dynamic>.from(me) : null);
      } on ApiError catch (e) {
        // Only a refusal clears it. Being unable to REACH the computer is not a
        // reason to sign somebody out — the laptop is asleep, not hostile, and
        // making them type their password again for that would be its own bug.
        if (e.status == 401) await signOut();
      }
    }
    _loading = false;
    notifyListeners();
  }

  /// `address` is whatever the person typed: safenest.example.com,
  /// https://SafeNest.Example.com/, or a LAN address with a port.
  Future<void> signIn(String address, String email, String password) async {
    final url = normaliseAddress(address);
    final probe = Api(baseUrl: url);

    // Confirm this address is a SafeNest before sending a password to it. A
    // domain that resolves to somebody else's site answers 200 perfectly
    // happily; the desktop app checks the same marker for the same reason.
    try {
      final health = await probe.get('/api/health');
      if (health is! Map || health['service'] != 'finmate-api') {
        throw ApiError(0,
            'That address answered, but it is not a SafeNest. Check it and try again.');
      }
    } on ApiError {
      rethrow;
    }

    final out = await probe.post('/api/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    final token = (out is Map) ? (out['token'] ?? out['access_token']) : null;
    if (token is! String || token.isEmpty) {
      throw ApiError(0, 'Signed in, but no session came back.');
    }

    _baseUrl = url;
    _token = token;
    await _store.write(key: _kUrl, value: url);
    await _store.write(key: _kToken, value: token);

    final me = await api.get('/api/auth/me');
    _user = (me is Map && me['user'] is Map)
        ? Map<String, dynamic>.from(me['user'] as Map)
        : (me is Map ? Map<String, dynamic>.from(me) : null);
    notifyListeners();
  }

  /// Re-read the signed-in user. Called after editing a profile so the name on
  /// screen matches what was just saved, rather than waiting for a restart.
  Future<void> refreshUser() async {
    try {
      final me = await api.get('/api/auth/me');
      _user = (me is Map && me['user'] is Map)
          ? Map<String, dynamic>.from(me['user'] as Map)
          : (me is Map ? Map<String, dynamic>.from(me) : null);
      notifyListeners();
    } on ApiError {
      // Not worth surfacing: the save already succeeded, and the name will be
      // right at the next launch regardless.
    }
  }

  /// Point the app at a different address for the SAME computer.
  ///
  /// Needed because the address is not one thing for ever: at home the phone
  /// should use 192.168.x.x and talk to the machine directly, and away from home
  /// it needs the domain. Before this, changing it meant signing out — which
  /// discarded a perfectly good session over what is only a different way of
  /// reaching the same server.
  ///
  /// The existing token is TESTED against the new address rather than assumed.
  /// If it still works this is the same computer and the session stands; if it
  /// does not, the address points somewhere else and signing in again is the
  /// honest outcome. Nothing is written until one of those is known.
  Future<bool> changeAddress(String address) async {
    final url = normaliseAddress(address);
    final probe = Api(baseUrl: url, token: _token);

    final health = await probe.get('/api/health');
    if (health is! Map || health['service'] != 'finmate-api') {
      throw ApiError(0,
          'That address answered, but it is not a SafeNest. Check it and try again.');
    }

    var stillSignedIn = true;
    try {
      await probe.get('/api/auth/me');
    } on ApiError catch (e) {
      if (e.status == 401) {
        stillSignedIn = false;
      } else {
        rethrow;   // unreachable, or a licence block — not a reason to sign out
      }
    }

    _baseUrl = url;
    await _store.write(key: _kUrl, value: url);
    if (!stillSignedIn) {
      _token = null;
      _user = null;
      await _store.delete(key: _kToken);
    }
    notifyListeners();
    return stillSignedIn;
  }

  Future<void> signOut() async {
    _token = null;
    _user = null;
    // Whoever signs in next has their OWN categories and banks — masters are
    // per-user rows. Keeping them would show one household member the previous
    // one's lists, which is both wrong and a small leak of what they file.
    masters.forget();
    // The address is deliberately KEPT. Signing out is not forgetting which
    // computer is yours, and making somebody retype it every time is friction
    // with nothing behind it.
    await _store.delete(key: _kToken);
    notifyListeners();
  }

  /// Accepts what a person would actually type; always returns a real base URL.
  ///
  /// http is allowed ONLY for a private address. Over the internet it would send
  /// the password in the clear; on a home network, insisting on https would make
  /// the app unusable for someone who has not set up a domain, which is most
  /// people on the day they install it.
  static String normaliseAddress(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (s.isEmpty) throw ApiError(0, 'Type the address of your SafeNest.');
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      final host = s.split(':').first;
      final private = host == 'localhost' ||
          RegExp(r'^10\.').hasMatch(host) ||
          RegExp(r'^192\.168\.').hasMatch(host) ||
          RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host) ||
          RegExp(r'^127\.').hasMatch(host);
      s = '${private ? 'http' : 'https'}://$s';
    }
    return s;
  }
}
