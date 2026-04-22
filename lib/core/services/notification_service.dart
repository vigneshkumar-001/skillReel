import '../notifications/fcm/fcm_service.dart';

/// Backward-compatible wrapper around the newer FCM module.
///
/// Keep existing call sites (`NotificationService.init()` and
/// `NotificationService.handlePendingRouteIfAny()`) stable.
class NotificationService {
  static final FcmService _fcm = FcmService();

  static Future<void> init() => _fcm.init();

  static void handlePendingRouteIfAny() => _fcm.handlePendingRouteIfAny();

  static Future<void> registerPushTokenIfAny() => _fcm.registerPushTokenIfAny();
}
