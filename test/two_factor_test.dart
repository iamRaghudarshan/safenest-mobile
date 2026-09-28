// Signing in to an account that asks for a code.
//
// This was a dead end until now: the app answered "two-step sign-in is not
// supported in the phone app yet" and stopped, so turning the second factor on
// anywhere locked that account out of the phone entirely — including the
// owner's own. The server has always had the endpoint.
//
// It is tested against a REAL HTTP server rather than a stubbed client,
// because the thing that was wrong was never a parsing detail: it was that one
// leg of a two-leg conversation was missing. A fake that answers whatever the
// app asks cannot show that the second leg reaches the right URL with the
// right body, and this suite would have passed against the broken version.
// The routes below mirror backend/app/routers/auth.py.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safenest/api.dart';
import 'package:safenest/session.dart';

/// Session keeps its secure store in a `static const`, so there is nothing to
/// inject — the channel itself has to be stood in for. An in-memory map is the
/// whole of what the Keychain does from Dart's point of view.
void _mockSecureStorage() {
  final mem = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
    final key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        return mem[key];
      case 'write':
        if (args['value'] != null) mem[key!] = args['value'] as String;
        return null;
      case 'delete':
        mem.remove(key);
        return null;
      case 'readAll':
        return Map<String, String>.from(mem);
      case 'deleteAll':
        mem.clear();
        return null;
      case 'containsKey':
        return mem.containsKey(key);
    }
    return null;
  });
}

/// A stand-in SafeNest. `twoFactor` decides which of the two shapes
/// `/api/auth/login` answers with, which is the fork the app got wrong.
class _FakeServer {
  _FakeServer({required this.twoFactor});

  final bool twoFactor;
  late final HttpServer _server;

  /// Every challenge this server has handed out and not yet spent. Single-use
  /// on purpose: the real one burns the challenge before it returns a session,
  /// so a test that let one be replayed would be testing a weaker server than
  /// the one that ships.
  final _live = <String>{};

  static const goodCode = '123456';
  static const recoveryCode = 'apple-otter-7';

  String get url => '127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final json = body.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(body) as Map);
      Object? out;
      var status = 200;

      switch (req.uri.path) {
        // The app refuses to send a password anywhere that does not answer
        // with this exact marker, so the fake has to carry it.
        case '/api/health':
          out = {'ok': true, 'service': 'finmate-api', 'version': '2.0'};
        case '/api/auth/login':
          if (json['password'] != 'right') {
            status = 401;
            out = {'detail': 'Invalid email or password'};
          } else if (twoFactor) {
            final c = 'challenge-${_live.length}';
            _live.add(c);
            out = {
              'two_factor': true,
              'challenge': c,
              'methods': ['totp', 'recovery'],
            };
          } else {
            out = {'token': 'tok', 'user': {'name': 'Raghudarshan'}};
          }
        case '/api/auth/login/2fa':
          final c = json['challenge'];
          final code = json['code'];
          if (!_live.contains(c)) {
            status = 401;
            out = {'detail': 'That sign-in expired. Enter your password again.'};
          } else if (code == goodCode || code == recoveryCode) {
            _live.remove(c);
            out = {'token': 'tok', 'user': {'name': 'Raghudarshan'}};
          } else {
            status = 401;
            out = {'detail': 'That code is not right. Try the next one.'};
          }
        case '/api/auth/me':
          out = {'user': {'name': 'Raghudarshan'}};
        default:
          status = 404;
          out = {'detail': 'Not Found'};
      }

      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(out));
      await req.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The test binding installs an HttpOverrides that answers every request with
  // a 400, so that a suite cannot quietly depend on the network. This one
  // depends on it deliberately — the server it talks to is the fake below, on
  // loopback, started and stopped by the test — so the real client is put back.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockSecureStorage();
  });

  group('an account that asks for a code', () {
    late _FakeServer server;

    setUp(() async {
      server = _FakeServer(twoFactor: true);
      await server.start();
    });
    tearDown(() => server.stop());

    test('the password step stops short, and says what is needed', () async {
      final session = Session();
      try {
        await session.signIn(server.url, 'raghudarshan10@gmail.com', 'right');
        fail('signing in should not have completed on the password alone');
      } on TwoFactorRequired catch (pending) {
        // THE ADDRESS TRAVELS WITH THE CHALLENGE. The second leg has to reach
        // the same server as the first, and a challenge without the address it
        // belongs to is only half an instruction.
        expect(pending.url, 'http://${server.url}');
        expect(pending.challenge, isNotEmpty);
        expect(pending.acceptsRecovery, isTrue);
      }
      // And crucially: no session yet. A token handed out before the code is
      // checked would make the second factor decorative.
      expect(session.signedIn, isFalse);
    });

    test('the right code finishes the sign-in', () async {
      final session = Session();
      late TwoFactorRequired pending;
      try {
        await session.signIn(server.url, 'raghudarshan10@gmail.com', 'right');
      } on TwoFactorRequired catch (e) {
        pending = e;
      }

      await session.completeTwoFactor(
        url: pending.url,
        challenge: pending.challenge,
        code: _FakeServer.goodCode,
      );

      expect(session.signedIn, isTrue);
      expect(session.baseUrl, 'http://${server.url}');
      // The profile is fetched on this path too. It is the shared step that
      // was easiest to forget when a second door into the session was added,
      // and a sign-in missing it looks fine and then behaves differently.
      expect(session.user?['name'], 'Raghudarshan');
    });

    test('a recovery code works where the authenticator cannot', () async {
      final session = Session();
      late TwoFactorRequired pending;
      try {
        await session.signIn(server.url, 'raghudarshan10@gmail.com', 'right');
      } on TwoFactorRequired catch (e) {
        pending = e;
      }
      await session.completeTwoFactor(
        url: pending.url,
        challenge: pending.challenge,
        code: _FakeServer.recoveryCode,
      );
      expect(session.signedIn, isTrue);
    });

    test('a wrong code leaves you signed out, and says so', () async {
      final session = Session();
      late TwoFactorRequired pending;
      try {
        await session.signIn(server.url, 'raghudarshan10@gmail.com', 'right');
      } on TwoFactorRequired catch (e) {
        pending = e;
      }

      await expectLater(
        session.completeTwoFactor(
            url: pending.url, challenge: pending.challenge, code: '000000'),
        throwsA(isA<ApiError>().having(
            (e) => e.message, 'message', contains('not right'))),
      );
      expect(session.signedIn, isFalse);
    });

    test('a challenge is spent once', () async {
      // The screen sends the user back to the password when this happens, so
      // the message has to be the one it looks for.
      final session = Session();
      late TwoFactorRequired pending;
      try {
        await session.signIn(server.url, 'raghudarshan10@gmail.com', 'right');
      } on TwoFactorRequired catch (e) {
        pending = e;
      }
      await session.completeTwoFactor(
          url: pending.url,
          challenge: pending.challenge,
          code: _FakeServer.goodCode);

      await expectLater(
        Session().completeTwoFactor(
            url: pending.url,
            challenge: pending.challenge,
            code: _FakeServer.goodCode),
        throwsA(isA<ApiError>()
            .having((e) => e.message, 'message', contains('expired'))),
      );
    });

    test('a wrong password never reaches the code step at all', () async {
      final session = Session();
      await expectLater(
        session.signIn(server.url, 'raghudarshan10@gmail.com', 'wrong'),
        throwsA(isA<ApiError>()),
      );
      expect(session.signedIn, isFalse);
    });
  });

  group('an account without a second factor', () {
    late _FakeServer server;

    setUp(() async {
      server = _FakeServer(twoFactor: false);
      await server.start();
    });
    tearDown(() => server.stop());

    test('still signs in on the password alone', () async {
      // The regression that matters: adding the second door must not put a
      // lock on the first.
      final session = Session();
      await session.signIn(server.url, 'raghudarshan10@gmail.com', 'right');
      expect(session.signedIn, isTrue);
      expect(session.user?['name'], 'Raghudarshan');
    });
  });
}
