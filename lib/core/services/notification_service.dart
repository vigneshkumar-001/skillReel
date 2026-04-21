import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../router/app_router.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();
    await FirebaseCrashlytics.instance.log(
      'FCM(background): ${message.messageId ?? ''}',
    );
  } catch (_) {
    // Avoid crashing the background isolate.
  }
}

class NotificationService {
  static String? _pendingRoute;

  static Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.setAutoInitEnabled(true);
    } catch (_) {}

    try {
      await messaging.requestPermission();
    } catch (_) {}

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = _extractRoute(message.data);
      if (route == null) return;
      _navigate(route);
    });

    try {
      final initial = await messaging.getInitialMessage();
      final route = initial == null ? null : _extractRoute(initial.data);
      if (route != null) {
        _pendingRoute = route;
      }
    } catch (_) {}

    if (kDebugMode) {
      try {
        final token = await messaging.getToken();
        await FirebaseCrashlytics.instance.log(
          'FCM token: ${token == null ? 'null' : 'received'}',
        );
      } catch (_) {}
    }
  }

  static void handlePendingRouteIfAny() {
    final route = _pendingRoute;
    if (route == null) return;
    _pendingRoute = null;
    _navigate(route);
  }

  static String? _extractRoute(Map<String, dynamic> data) {
    final rawRoute = data['route']?.toString();
    if (rawRoute != null && rawRoute.trim().isNotEmpty) {
      return rawRoute.trim();
    }

    final reelId = data['reelId']?.toString();
    if (reelId != null && reelId.trim().isNotEmpty) {
      return '/reel/${reelId.trim()}';
    }

    final providerId = data['providerId']?.toString();
    if (providerId != null && providerId.trim().isNotEmpty) {
      return '/provider/${providerId.trim()}';
    }

    return null;
  }

  static void _navigate(String route) {
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
