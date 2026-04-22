import '../../constants/api_constants.dart';
import '../../network/api_client.dart';

class PushTokenRepository {
  final ApiClient _api;

  PushTokenRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  Future<void> savePushToken(Map<String, dynamic> payload) async {
    await _api.post(ApiConstants.pushToken, data: payload);
  }
}
