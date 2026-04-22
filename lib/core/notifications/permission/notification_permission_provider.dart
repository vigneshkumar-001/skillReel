import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final notificationPermissionStatusProvider =
    FutureProvider<PermissionStatus>((ref) async {
  return Permission.notification.status;
});

final notificationPermissionPromptDismissedProvider =
    StateProvider<bool>((ref) => false);
