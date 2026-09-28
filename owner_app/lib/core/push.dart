import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'api.dart';

/// Firebase Cloud Messaging. Silently disabled until Firebase keys are set.
class Push {
  static String? token;
  static final _foreground = StreamController<RemoteMessage>.broadcast();
  static Stream<RemoteMessage> get foreground => _foreground.stream;

  static Future<void> init() async {
    if (!AppConfig.firebaseConfigured) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      token = await fm.getToken();
      fm.onTokenRefresh.listen((t) {
        token = t;
        syncToken();
      });
      FirebaseMessaging.onMessage.listen(_foreground.add);
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// Tell the server where to send this phone's notifications.
  static Future<void> syncToken() async {
    if (token == null) return;
    try {
      await Api.call('update_device', {'fcm_token': token});
    } catch (_) {}
  }
}
