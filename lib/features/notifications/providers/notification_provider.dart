import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/notification_repository.dart';

final notifRepoProvider = Provider((_) => NotificationRepository());

final notificationsProvider = FutureProvider<List<dynamic>>((ref) {
  return ref.read(notifRepoProvider).getNotifications();
});