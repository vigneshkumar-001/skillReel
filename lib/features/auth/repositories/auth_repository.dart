import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';
import '../models/auth_model.dart';

class AuthRepository {
  final _api = ApiClient.instance;

  Future<void> requestOtp(String mobile) async {
    await _api.post(ApiConstants.requestOtp, data: {'mobile': mobile});
  }

  Future<AuthModel> verifyOtp(String mobile, String otp) async {
    final res = await _api.post(
      ApiConstants.verifyOtp,
      data: {'mobile': mobile, 'otp': otp},
    );
    return AuthModel.fromJson(res.data['data']);
  }
}