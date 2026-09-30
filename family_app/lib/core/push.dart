import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'api.dart';
import 'device.dart';

/// Notifications from family_notify: a meal's menu was set or changed, and
/// "book before …" reminders. Silently off until the Firebase keys are set.
class Push {
  static String? token;
  static final _foreground = StreamController<RemoteMessage>.broadcast();

  /// Notifications that arrive while the app is open (the phone shows none).
  static Stream<RemoteMessage> get foreground => _foreground.stream;

  static Future<void> init() async {
    if (!AppConfig.firebaseConfigured) return;
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: Platform.isIOS ? AppConfig.firebaseIosApiKey : AppConfig.firebaseApiKey,
          appId: Platform.isIOS ? AppConfig.firebaseIosAppId : AppConfig.firebaseAppId,
          iosBundleId: Platform.isIOS ? 'com.dhrruwa.cookfamily' : null,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      fm.onTokenRefresh.listen((t) {
        token = t;
        syncToken();
      });
      FirebaseMessaging.onMessage.listen(_foreground.add);
      // Not awaited: on iPhone this can take seconds, and startup must not wait.
      unawaited(_fetchToken(fm));
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// On iPhone, Firebase can only hand out a token after Apple has given the
  /// phone its push token, which arrives a few seconds after launch.
  static Future<void> _fetchToken(FirebaseMessaging fm) async {
    try {
      if (Platform.isIOS) {
        for (var i = 0; i < 30 && await fm.getAPNSToken() == null; i++) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      token = await fm.getToken();
      await syncToken();
    } catch (e) {
      debugPrint('Push token not available: $e');
    }
  }

  /// Tell the server where to send this member's notifications (member_home
  /// stores the token). Also called right after logging in.
  static Future<void> syncToken() async {
    if (token == null || !Device.loggedIn) return;
    try {
      await Api.call('member_home', {'days': 1, 'fcm_token': token});
    } catch (_) {}
  }
}
