import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';

class ReviewRepository {
  final _api = ApiClient.instance;

  Future<void> createReview(String providerId, int rating, String comment) =>
      _api.post(ApiConstants.reviews,
          data: {'providerId': providerId, 'rating': rating, 'comment': comment});

  Future<List<dynamic>> getProviderReviews(String providerId) async {
    final res = await _api.get(ApiConstants.reviews,
        params: {'providerId': providerId});
    return res.data['data'] as List;
  }
}