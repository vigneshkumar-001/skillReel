import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../router/app_router.dart';
import '../fcm/fcm_deeplink.dart';
import '../../services/log.dart';

class LocalNotificationsService {
  static final LocalNotificationsService instance =
      LocalNotificationsService._();
  LocalNotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'skilreel_high_importance',
    'SkilReel',
    description: 'SkilReel notifications',
    importance: Importance.high,
  );

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = (resp.payload ?? '').trim();
        if (payload.isEmpty) return;
        try {
          appRouter.push(payload);
        } catch (_) {}
      },
    );

    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);
    } catch (_) {}

    if (!kIsWeb) {
      try {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}
    }
  }

  Future<void> showFromRemoteMessage(RemoteMessage message) async {
    // Only for foreground use. Background/terminated: OS will handle it
    // when the push contains a "notification" payload.
    final n = message.notification;
    final title =
        (n?.title ?? message.data['title'] ?? 'SkilReel').toString().trim();
    final body =
        (n?.body ?? message.data['body'] ?? message.data['message'] ?? '')
            .toString()
            .trim();

    final deepLink = fcmExtractRoute(message.data);

    if (title.isEmpty && body.isEmpty) {
      log.tag('LocalNotif').i('Skip local notification (empty title/body).');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    final details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      message.messageId.hashCode,
      title,
      body,
      details,
      payload: deepLink,
    );
  }
}
