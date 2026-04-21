import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';

class NotificationRepository {
  final _api = ApiClient.instance;

  Future<List<dynamic>> getNotifications() async {
    final res = await _api.get(ApiConstants.notifications);
    return res.data['data'] as List;
  }
}