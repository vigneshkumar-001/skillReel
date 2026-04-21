import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';
import '../models/feed_model.dart';
import '../models/feed_page.dart';
import '../../reels/models/reel_model.dart';
import '../../providers_module/models/provider_model.dart';

class FeedRepository {
  FeedRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient.instance;

  final ApiClient _apiClient;

  Future<FeedPage> getFeedPage(
    String type, {
    String? cursor,
    int page = 1,
    int limit = 20,
    double? latitude,
    double? longitude,
  }) async {
    final trimmedType = type.trim();
    if (trimmedType.startsWith('search_q:')) {
      final raw = trimmedType.substring('search_q:'.length);
      final q = _safeDecode(raw);
      return _getSearchQueryPage(q, page: page, limit: limit);
    }
    if (trimmedType.startsWith('search_category:')) {
      final raw = trimmedType.substring('search_category:'.length);
      final category = _safeDecode(raw);
      return _getSearchCategoryPage(category, page: page, limit: limit);
    }

    final path = switch (type) {
      'my_provider' => ApiConstants.myProviderReels,
      'saved' => ApiConstants.myProviderSaved,
      'trending' => ApiConstants.feedTrending,
      'nearby' => ApiConstants.feedNearby,
      'following' => ApiConstants.feedFollowing,
      _ => ApiConstants.feedHome,
    };

    final params = <String, dynamic>{'limit': limit};
    if (type == 'my_provider' || type == 'saved') {
      if (cursor != null && cursor.trim().isNotEmpty) {
        params['cursor'] = cursor.trim();
      }
    } else {
      if (cursor != null && cursor.trim().isNotEmpty) {
        params['cursor'] = cursor.trim();
      } else {
        params['page'] = page;
      }
    }

    if (type == 'nearby') {
      if (latitude != null) params['lat'] = latitude;
      if (longitude != null) params['lng'] = longitude;
    }

    final res = await _apiClient.get(path, params: params);
    final root = res.data;
    if (root is! Map) {
      throw StateError('Unexpected feed response: ${root.runtimeType}');
    }

    final rootMap = Map<String, dynamic>.from(root);
    final dataObj = rootMap['data'];

    final reels = <ReelModel>[];
    if (dataObj is List) {
      reels.addAll(
        dataObj.whereType<Map>().map((r) {
          final m = Map<String, dynamic>.from(r);
          if (type != 'my_provider' && type != 'saved') {
            return ReelModel.fromJson(m);
          }

          final id = (m['id'] ?? m['_id'] ?? '').toString();
          final mediaUrl =
              (m['playbackUrl'] ?? m['mediaUrl'] ?? m['coverUrl'] ?? '')
                  .toString();
          final coverUrl = (m['coverUrl'] ?? '').toString();

          final mapped = <String, dynamic>{
            '_id': id,
            'title': (m['title'] ?? '').toString(),
            'description': '',
            'mediaType': (m['mediaType'] ?? 'video').toString(),
            'mediaUrl': mediaUrl,
            'thumbnailUrl': coverUrl.isNotEmpty ? coverUrl : mediaUrl,
            'viewCount': m['viewCount'] ?? 0,
            'likeCount': m['likeCount'] ?? 0,
            'commentCount': 0,
            'saveCount': 0,
            'isLiked': m['isLiked'] == true,
            'isSaved': type == 'saved' ? true : (m['isSaved'] == true),
            'price': m['price'],
            'isBoosted': false,
            'skillTags': const <String>[],
            'providerId': '',
          };
          return ReelModel.fromJson(mapped);
        }),
      );
    } else if (dataObj is Map) {
      final m = Map<String, dynamic>.from(dataObj);
      final list = m['reels'];
      if (list is List) {
        reels.addAll(
          list
              .whereType<Map>()
              .map((r) => ReelModel.fromJson(Map<String, dynamic>.from(r))),
        );
      }
    }

    String? nextCursor;
    bool hasMore = reels.length >= limit;

    final metaObj = rootMap['meta'];
    if (metaObj is Map) {
      final meta = Map<String, dynamic>.from(metaObj);
      if (type == 'my_provider') {
        final pageInfoObj = meta['pageInfo'];
        if (pageInfoObj is Map) {
          final pageInfo = Map<String, dynamic>.from(pageInfoObj);
          nextCursor = pageInfo['nextCursor']?.toString();
          hasMore = pageInfo['hasMore'] == true;
        }
      } else if (type == 'saved') {
        final pageInfoObj = meta['pageInfo'];
        if (pageInfoObj is Map) {
          final pageInfo = Map<String, dynamic>.from(pageInfoObj);
          nextCursor = pageInfo['nextCursor']?.toString();
          hasMore = pageInfo['hasMore'] == true;
        }
      } else {
        nextCursor =
            (meta['nextCursor'] ?? meta['next_cursor'] ?? meta['cursor'])
                ?.toString();
      }

      final pages = meta['pages'];
      final pageVal = meta['page'];
      if (pages is int && pageVal is int) {
        hasMore = pageVal < pages;
      }
      if (nextCursor != null && nextCursor.trim().isEmpty) {
        nextCursor = null;
      }
      if (nextCursor != null) {
        hasMore = true;
      }
    }

    return FeedPage(reels: reels, nextCursor: nextCursor, hasMore: hasMore);
  }

  Future<FeedPage> _getSearchQueryPage(
    String query, {
    required int page,
    required int limit,
  }) async {
    final res = await _apiClient.get(
      ApiConstants.search,
      params: {
        'q': query,
        'page': page,
        'limit': limit,
      },
    );
    final root = res.data;
    if (root is! Map) {
      throw StateError('Unexpected search response: ${root.runtimeType}');
    }

    final rootMap = Map<String, dynamic>.from(root);
    final dataObj = rootMap['data'];
    final reelsObj = dataObj is Map ? dataObj['reels'] : null;

    final reels = <ReelModel>[];
    if (reelsObj is List) {
      reels.addAll(
        reelsObj
            .whereType<Map>()
            .map((r) => ReelModel.fromJson(Map<String, dynamic>.from(r))),
      );
    }

    var hasMore = reels.length >= limit;
    final metaObj = rootMap['meta'];
    if (metaObj is Map) {
      final meta = Map<String, dynamic>.from(metaObj);
      final pages = meta['pages'];
      final pageVal = meta['page'];
      if (pages is int && pageVal is int) {
        hasMore = pageVal < pages;
      }
    }

    return FeedPage(reels: reels, nextCursor: null, hasMore: hasMore);
  }

  Future<FeedPage> _getSearchCategoryPage(
    String category, {
    required int page,
    required int limit,
  }) async {
    final res = await _apiClient.get(
      ApiConstants.searchReelsByCategory,
      params: {
        'category': category,
        'page': page,
        'limit': limit,
      },
    );
    final root = res.data;
    if (root is! Map) {
      throw StateError(
        'Unexpected category reels response: ${root.runtimeType}',
      );
    }

    final rootMap = Map<String, dynamic>.from(root);
    final dataObj = rootMap['data'];

    final reels = <ReelModel>[];
    if (dataObj is List) {
      reels.addAll(
        dataObj
            .whereType<Map>()
            .map((r) => ReelModel.fromJson(Map<String, dynamic>.from(r))),
      );
    }

    var hasMore = reels.length >= limit;
    final metaObj = rootMap['meta'];
    if (metaObj is Map) {
      final meta = Map<String, dynamic>.from(metaObj);
      final pages = meta['pages'];
      final pageVal = meta['page'];
      if (pages is int && pageVal is int) {
        hasMore = pageVal < pages;
      }
    }

    return FeedPage(reels: reels, nextCursor: null, hasMore: hasMore);
  }

  String _safeDecode(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return '';
    try {
      return Uri.decodeComponent(r);
    } catch (_) {
      return r;
    }
  }

  Future<FeedModel> getFeed(
    String type, {
    int page = 1,
    int limit = 20,
    double? latitude,
    double? longitude,
  }) async {
    final path = switch (type) {
      'trending' => ApiConstants.feedTrending,
      'nearby' => ApiConstants.feedNearby,
      'following' => ApiConstants.feedFollowing,
      _ => ApiConstants.feedHome,
    };

    final params = <String, dynamic>{'page': page, 'limit': limit};
    if (type == 'nearby') {
      if (latitude != null) params['lat'] = latitude;
      if (longitude != null) params['lng'] = longitude;
    }

    final res = await _apiClient.get(path, params: params);
    final root = res.data;
    if (root is! Map) {
      throw StateError('Unexpected feed response: ${root.runtimeType}');
    }

    final rootMap = Map<String, dynamic>.from(root);
    final dataObj = rootMap['data'];

    // New API shape: { success, message, data: [ ...reels ], meta }
    if (dataObj is List) {
      final reels = dataObj
          .whereType<Map>()
          .map((r) => ReelModel.fromJson(Map<String, dynamic>.from(r)))
          .toList();

      final providersById = <String, ProviderModel>{};
      for (final item in dataObj.whereType<Map>()) {
        final providerObj = item['providerId'];
        if (providerObj is Map) {
          final provider =
              ProviderModel.fromJson(Map<String, dynamic>.from(providerObj));
          if (provider.id.isNotEmpty) {
            providersById[provider.id] = provider;
          }
        }
      }

      return FeedModel(reels: reels, providers: providersById.values.toList());
    }

    // Old API shape: { data: { reels: [...], providers: [...] } } or already-flat.
    if (dataObj is Map) {
      return FeedModel.fromJson(Map<String, dynamic>.from(dataObj));
    }

    return FeedModel.fromJson(rootMap);
  }
}
