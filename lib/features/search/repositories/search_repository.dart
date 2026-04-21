import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';
import '../../home/models/feed_model.dart';
import '../../reels/models/reel_model.dart';
import '../../providers_module/models/provider_model.dart';
import '../models/search_category_model.dart';

class SearchRepository {
  final _api = ApiClient.instance;

  Future<FeedModel> search(
    String query, {
    int page = 1,
    int limit = 10,
  }) async {
    final res = await _api.get(
      ApiConstants.search,
      params: {
        'q': query,
        'page': page,
        'limit': limit,
      },
    );
    final data = res.data['data'];
    return FeedModel(
      providers: (data['providers'] as List? ?? [])
          .map((p) => ProviderModel.fromJson(p))
          .toList(),
      reels: (data['reels'] as List? ?? [])
          .map((r) => ReelModel.fromJson(r))
          .toList(),
    );
  }

  Future<List<SearchCategoryModel>> fetchCategories() async {
    final res = await _api.get(ApiConstants.searchCategories);
    final data = res.data['data'];
    if (data is! List) return const <SearchCategoryModel>[];
    return data
        .whereType<Map>()
        .map((m) => SearchCategoryModel.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<List<ReelModel>> fetchCategoryReels(
    String category, {
    int page = 1,
    int limit = 12,
  }) async {
    final res = await _api.get(
      ApiConstants.searchReelsByCategory,
      params: {
        'category': category,
        'page': page,
        'limit': limit,
      },
    );
    final data = res.data['data'];
    if (data is! List) return const <ReelModel>[];
    return data
        .whereType<Map>()
        .map((m) => ReelModel.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}
