/// Push from the owner's own server to this phone, by way of Firebase.
///
/// WHY FIREBASE IS IN A PRODUCT THAT AVOIDS THIRD PARTIES. There is no
/// self-hosted route to an iPhone's lock screen. Apple delivers to a native app
/// through APNs and nothing else; Google, through FCM. A server on somebody's
/// desk cannot reach a sleeping phone directly, and no amount of design here
/// changes that — it is Apple's and Google's decision.
///
/// So this is the one place something leaves the machine, and it is worth being
/// exact: what leaves is a TITLE and a LINE OF BODY — "HDFC card due today".
/// Not the amount, not the record, not the vault. If even that is too much, the
/// answer is to leave it unconfigured: `alarms.dart` schedules reminders on the
/// device, they ring in flight mode, and nothing leaves at all. Both work.
///
/// CONFIGURED AT RUN TIME. The usual Firebase setup drops google-services.json
/// into the Android project and applies a Gradle plugin that FAILS THE BUILD if
/// the file is missing. That would mean nobody could compile this app until
/// they had made a Firebase project — so the options are passed in Dart
/// instead, from --dart-define at build time. No file, no plugin, and an
/// unconfigured build simply has no push rather than no build.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';

/// Handed in at build time:
///
///   flutter build apk --dart-define=FCM_PROJECT_ID=... \
///                     --dart-define=FCM_APP_ID=... \
///                     --dart-define=FCM_API_KEY=... \
///                     --dart-define=FCM_SENDER_ID=...
///
/// All four come from the Firebase console. None is a secret in the sense the
/// vault key is — they identify a project, they do not authorise sending; that
/// is the service-account key, which stays on the owner's server.
const _projectId = String.fromEnvironment('FCM_PROJECT_ID');
const _appId = String.fromEnvironment('FCM_APP_ID');
const _apiKey = String.fromEnvironment('FCM_API_KEY');
const _senderId = String.fromEnvironment('FCM_SENDER_ID');

bool get pushCompiledIn =>
    _projectId.isNotEmpty && _appId.isNotEmpty && _senderId.isNotEmpty;

class Push {
  Push._();
  static final Push instance = Push._();

  bool _started = false;
  String? _token;

  String? get token => _token;

  /// Start Firebase and register this phone with the owner's server.
  ///
  /// Every step is allowed to fail quietly. Push is a convenience on top of a
  /// notification the server has already recorded — the bell shows it either
  /// way — so nothing here is worth an error in front of somebody who just
  /// wanted to see their expenses.
  Future<bool> start(Api api) async {
    if (!pushCompiledIn) return false;
    if (_started) return _token != null;
    _started = true;

    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );

      final messaging = FirebaseMessaging.instance;
      // Asked here rather than at first launch: a permission prompt before
      // anybody has seen what the app does is the one most often refused.
      final settings = await messaging.requestPermission(
          alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }

      final t = await messaging.getToken();
      if (t == null || t.isEmpty) return false;
      _token = t;
      await _register(api, t);

      // FCM replaces a token when the app is restored to a new handset or the
      // registration is invalidated. Without this the server keeps pushing to
      // an address that no longer exists and the phone goes quiet with nothing
      // to show why.
      messaging.onTokenRefresh.listen((fresh) {
        _token = fresh;
        _register(api, fresh).catchError((_) {});
      });
      return true;
    } catch (e) {
      debugPrint('[push] not started: $e');
      return false;
    }
  }

  Future<void> _register(Api api, String token) async {
    try {
      await api.post('/api/notifications/device', {
        'token': token,
        'platform': defaultTargetPlatform.name,
      });
    } on ApiError catch (e) {
      debugPrint('[push] could not register this device: ${e.message}');
    }
  }

  /// Forget this phone on the server — sign-out, or notifications turned off.
  ///
  /// Matters more than it sounds: a handset that signs out and is not
  /// unregistered keeps receiving the previous account's reminders, which on a
  /// shared family phone means one person's records announcing themselves to
  /// another.
  Future<void> forget(Api api) async {
    final t = _token;
    if (t == null) return;
    try {
      await api.post('/api/notifications/device/remove', {'token': t});
    } on ApiError {
      // Signing out must not be blocked by a network call.
    }
    _token = null;
  }
}
