import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/app_logger.dart';
import '../../services/log.dart';
import '../../router/app_router.dart';
import '../local/local_notifications_service.dart';
import 'fcm_background_handler.dart';
import 'fcm_deeplink.dart';
import '../push_token/push_token_service.dart';

class FcmService {
  String? _pendingRoute;
  StreamSubscription<String>? _tokenSub;
  bool _initialized = false;
  final PushTokenService _push = PushTokenService();
  final LocalNotificationsService _localNotifs =
      LocalNotificationsService.instance;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    try {
      await _localNotifs.init();
    } catch (_) {}
    try {
      await messaging.setAutoInitEnabled(true);
    } catch (_) {}

    // Request notification permission after the first frame so the OS prompt
    // reliably appears on top of the app UI (and plugin bindings are ready).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureNotificationPermission());
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = fcmExtractRoute(message.data);
      if (route == null) return;
      _navigate(route);
    });

    FirebaseMessaging.onMessage.listen((message) async {
      try {
        final nTitle = (message.notification?.title ?? '').toString().trim();
        final nBody = (message.notification?.body ?? '').toString().trim();
        log.tag('FCM').i(
              'FCM(foreground) received: id=${message.messageId ?? '<null>'} '
              'notif=${message.notification != null} '
              'title=${nTitle.isEmpty ? '<empty>' : nTitle} '
              'body=${nBody.isEmpty ? '<empty>' : nBody} '
              'dataKeys=${message.data.keys.toList()}',
            );

        // Foreground: show a system notification via local notifications.
        // (Firebase/OS won't show notifications in foreground on Android.)
        unawaited(_localNotifs.showFromRemoteMessage(message));

        await FirebaseCrashlytics.instance.log(
          'FCM(foreground): ${message.messageId ?? ''}',
        );
      } catch (_) {}
    });

    try {
      final initial = await messaging.getInitialMessage();
      final route = initial == null ? null : fcmExtractRoute(initial.data);
      if (route != null) _pendingRoute = route;
    } catch (_) {}

    _tokenSub?.cancel();
    _tokenSub = messaging.onTokenRefresh.listen((token) async {
      await _logToken(token, source: 'refresh');
      await _push.registerIfPossible(pushToken: token, source: 'fcm_refresh');
    });

    try {
      final token = await messaging.getToken();
      await _logToken(token, source: 'initial');
      await _push.registerIfPossible(pushToken: token, source: 'fcm_initial');
    } catch (_) {}
  }

  void handlePendingRouteIfAny() {
    final route = _pendingRoute;
    if (route == null) return;
    _pendingRoute = null;
    _navigate(route);
  }

  Future<void> dispose() async {
    _initialized = false;
    final sub = _tokenSub;
    _tokenSub = null;
    await sub?.cancel();
  }

  Future<void> _logToken(String? token, {required String source}) async {
    try {
      final masked = AppLogger.maskToken(token);
      final toPrint = kDebugMode ? (token ?? '<null>') : masked;
      log.tag('FCM').i('FCM TOKEN == $toPrint (source=$source)');

      await FirebaseCrashlytics.instance.log(
        'FCM token ($source): ${token == null || token.trim().isEmpty ? 'null/empty' : 'received'}',
      );
    } catch (_) {}
  }

  Future<void> _ensureNotificationPermission() async {
    // iOS/Web: requestPermission() triggers the system prompt (only once).
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}

    // Android 13+: runtime notification permission.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final status = await Permission.notification.status;
        log.tag('FCM').i('Notification permission (current): $status');

        if (status.isDenied) {
          final next = await Permission.notification.request();
          log.tag('FCM').i('Notification permission (requested): $next');
        }
      } catch (_) {}
    }
  }

  Future<void> registerPushTokenIfAny() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      await _push.registerIfPossible(pushToken: token, source: 'manual');
    } catch (_) {}
  }

  void _navigate(String route) {
    try {
      appRouter.push(route);
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'fcm_deeplink_navigation',
        fatal: false,
      );
    }
  }
}
