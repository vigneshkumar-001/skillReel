class MySavedReelsResponse {
  final bool success;
  final String message;
  final List<MySavedReelItem> data;
  final MySavedReelsMeta meta;

  const MySavedReelsResponse({
    required this.success,
    required this.message,
    required this.data,
    required this.meta,
  });

  factory MySavedReelsResponse.fromJson(Map<String, dynamic> j) {
    return MySavedReelsResponse(
      success: j['success'] == true,
      message: (j['message'] ?? '').toString(),
      data: _asList(j['data'])
          .map((e) => MySavedReelItem.fromJson(_asMap(e)))
          .toList(growable: false),
      meta: MySavedReelsMeta.fromJson(_asMap(j['meta'])),
    );
  }
}

class MySavedReelItem {
  final String id;
  final String title;
  final String mediaType;
  final String? coverUrl;
  final String? mediaUrl;
  final String? playbackUrl;
  final int viewCount;
  final int likeCount;
  final int? price;
  final List<String> badges;
  final String createdAt;

  const MySavedReelItem({
    required this.id,
    required this.title,
    required this.mediaType,
    required this.coverUrl,
    required this.mediaUrl,
    required this.playbackUrl,
    required this.viewCount,
    required this.likeCount,
    required this.price,
    required this.badges,
    required this.createdAt,
  });

  factory MySavedReelItem.fromJson(Map<String, dynamic> j) {
    return MySavedReelItem(
      id: (j['id'] ?? j['_id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      mediaType: (j['mediaType'] ?? '').toString(),
      coverUrl: j['coverUrl']?.toString(),
      mediaUrl: j['mediaUrl']?.toString(),
      playbackUrl: j['playbackUrl']?.toString(),
      viewCount: _asInt(j['viewCount']),
      likeCount: _asInt(j['likeCount']),
      price: (j['price'] is num) ? (j['price'] as num).round() : null,
      badges: _asStringList(j['badges']),
      createdAt: (j['createdAt'] ?? '').toString(),
    );
  }
}

class MySavedReelsMeta {
  final MySavedReelsPageInfo pageInfo;

  const MySavedReelsMeta({required this.pageInfo});

  factory MySavedReelsMeta.fromJson(Map<String, dynamic> j) {
    return MySavedReelsMeta(
      pageInfo: MySavedReelsPageInfo.fromJson(_asMap(j['pageInfo'])),
    );
  }
}

class MySavedReelsPageInfo {
  final bool hasMore;
  final String? nextCursor;
  final int limit;

  const MySavedReelsPageInfo({
    required this.hasMore,
    required this.nextCursor,
    required this.limit,
  });

  factory MySavedReelsPageInfo.fromJson(Map<String, dynamic> j) {
    return MySavedReelsPageInfo(
      hasMore: j['hasMore'] == true,
      nextCursor: j['nextCursor']?.toString(),
      limit: _asInt(j['limit']),
    );
  }
}

Map<String, dynamic> _asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return const <String, dynamic>{};
}

List _asList(Object? v) {
  if (v is List) return v;
  return const [];
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

List<String> _asStringList(Object? v) {
  if (v is List) {
    return v.map((e) => e.toString()).toList(growable: false);
  }
  return const [];
}
