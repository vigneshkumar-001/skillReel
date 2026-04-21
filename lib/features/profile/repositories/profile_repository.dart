import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';

class ProfileRepository {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> getMyProfile() async {
    final res = await _api.get(ApiConstants.me);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<void> updateProfile(Map<String, dynamic> data) =>
      _api.put(ApiConstants.appMeProfile, data: data);
}
