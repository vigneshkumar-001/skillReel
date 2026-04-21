import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';

class EnquiryRepository {
  final _api = ApiClient.instance;

  Future<void> createEnquiry(String providerId, String message) =>
      _api.post(ApiConstants.enquiries,
          data: {'providerId': providerId, 'message': message});

  Future<List<dynamic>> getMyEnquiries() async {
    final res = await _api.get(ApiConstants.enquiries);
    return res.data['data'] as List;
  }
}