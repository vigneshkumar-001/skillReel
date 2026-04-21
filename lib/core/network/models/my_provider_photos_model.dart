class MyProviderPhotosResponse {
  final bool success;
  final String message;
  final List<MyProviderPhotoItem> data;
  final MyProviderPhotosMeta meta;

  const MyProviderPhotosResponse({
    required this.success,
    required this.message,
    required this.data,
    required this.meta,
  });

  factory MyProviderPhotosResponse.fromJson(Map<String, dynamic> j) {
    return MyProviderPhotosResponse(
      success: j['success'] == true,
      message: (j['message'] ?? '').toString(),
      data: _asList(j['data'])
          .map((e) => MyProviderPhotoItem.fromJson(_asMap(e)))
          .toList(growable: false),
      meta: MyProviderPhotosMeta.fromJson(_asMap(j['meta'])),
    );
  }
}

class MyProviderPhotoItem {
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

  const MyProviderPhotoItem({
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

  factory MyProviderPhotoItem.fromJson(Map<String, dynamic> j) {
    return MyProviderPhotoItem(
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

class MyProviderPhotosMeta {
  final MyProviderPhotosPageInfo pageInfo;

  const MyProviderPhotosMeta({required this.pageInfo});

  factory MyProviderPhotosMeta.fromJson(Map<String, dynamic> j) {
    return MyProviderPhotosMeta(
      pageInfo: MyProviderPhotosPageInfo.fromJson(_asMap(j['pageInfo'])),
    );
  }
}

class MyProviderPhotosPageInfo {
  final bool hasMore;
  final String? nextCursor;
  final int limit;

  const MyProviderPhotosPageInfo({
    required this.hasMore,
    required this.nextCursor,
    required this.limit,
  });

  factory MyProviderPhotosPageInfo.fromJson(Map<String, dynamic> j) {
    return MyProviderPhotosPageInfo(
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

