import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'api.dart';
import 'i18n.dart';

/// Firebase Cloud Messaging. Silently disabled until Firebase keys are set.
class Push {
  static String? token;
  static final _foreground = StreamController<RemoteMessage>.broadcast();
  static Stream<RemoteMessage> get foreground => _foreground.stream;

  static Future<void> init() async {
    if (!AppConfig.firebaseConfigured) return;
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: Platform.isIOS ? AppConfig.firebaseIosAppId : AppConfig.firebaseAppId,
          iosBundleId: Platform.isIOS ? 'com.dhrruwa.cookattendance' : null,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      token = await fm.getToken();
      fm.onTokenRefresh.listen((t) {
        token = t;
        syncDevice();
      });
      FirebaseMessaging.onMessage.listen(_foreground.add);
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// Sends the FCM token and chosen language to the server.
  static Future<void> syncDevice() async {
    try {
      await Api.call('update_device', {'fcm_token': ?token, 'lang': L.code});
    } catch (_) {}
  }
}
