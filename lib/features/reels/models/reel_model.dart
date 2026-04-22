import '../../../core/utils/url_utils.dart';

class ReelModel {
  final String id;
  final String title;
  final String? description;
  final String mediaUrl;
  final List<String> mediaUrls;
  final String thumbnailUrl;
  final String mediaType;
  final int likes;
  final int comments;
  final int saves;
  final int viewCount;
  final bool isLiked;
  final bool isSaved;
  final int? price;
  final bool isBoosted;
  final List<String> skillTags;
  final String providerId;
  final String? providerName;
  final String? providerAvatar;
  final String? providerCity;
  final String? providerState;
  final bool? providerIsVerified;
  final bool isOwnReel;

  ReelModel({
    required this.id,
    required this.title,
    this.description,
    required this.mediaUrl,
    this.mediaUrls = const [],
    required this.thumbnailUrl,
    required this.mediaType,
    required this.likes,
    required this.comments,
    required this.saves,
    this.viewCount = 0,
    this.isLiked = false,
    this.isSaved = false,
    this.price,
    required this.isBoosted,
    required this.skillTags,
    required this.providerId,
    this.providerName,
    this.providerAvatar,
    this.providerCity,
    this.providerState,
    this.providerIsVerified,
    this.isOwnReel = false,
  });

  factory ReelModel.fromJson(Map<String, dynamic> j) {
    final providerObj = j['providerId'];
    final provider =
        providerObj is Map ? Map<String, dynamic>.from(providerObj) : null;

    final rawMediaUrl = (j['mediaUrl'] ?? '') as String;
    final rawThumbUrl = (j['thumbnailUrl'] ?? '') as String;

    final mediaUrl = UrlUtils.normalizeMediaUrl(rawMediaUrl);
    final thumbnailUrl = UrlUtils.normalizeMediaUrl(
      rawThumbUrl.isNotEmpty ? rawThumbUrl : rawMediaUrl,
    );

    final mediaUrlsRaw = j['mediaUrls'] ?? j['media'] ?? j['gallery'];
    final mediaUrls = <String>[
      if (mediaUrlsRaw is List)
        ...mediaUrlsRaw
            .whereType<String>()
            .map(UrlUtils.normalizeMediaUrl)
            .where((u) => u.isNotEmpty),
      if (mediaUrl.isNotEmpty) mediaUrl,
    ];
    final uniqueMediaUrls = mediaUrls.toSet().toList(growable: false);

    return ReelModel(
      id: j['_id'] ?? j['id'] ?? '',
      title: j['title'] ?? '',
      description: j['description'],
      mediaUrl: mediaUrl,
      mediaUrls: uniqueMediaUrls,
      thumbnailUrl: thumbnailUrl,
      mediaType: j['mediaType'] ?? 'image',
      likes: j['likeCount'] ?? j['likes'] ?? 0,
      comments: j['commentCount'] ?? j['comments'] ?? 0,
      saves: j['saveCount'] ?? j['saves'] ?? 0,
      viewCount: j['viewCount'] ?? 0,
      isLiked: j['isLiked'] == true,
      isSaved: j['isSaved'] == true,
      price: j['price'],
      isBoosted: j['isBoosted'] ?? false,
      skillTags: List<String>.from(j['skillTags'] ?? const []),
      providerId: provider?['_id'] ?? j['providerId'] ?? '',
      providerName: provider?['displayName'] ?? j['providerName'],
      providerAvatar: UrlUtils.normalizeMediaUrl(
        (provider?['avatar'] ?? j['providerAvatar'])?.toString(),
      ),
      providerCity: (provider?['location'] is Map)
          ? (provider!['location'] as Map)['city']
          : null,
      providerState: (provider?['location'] is Map)
          ? (provider!['location'] as Map)['state']
          : null,
      providerIsVerified: provider?['isVerified'] is bool
          ? provider!['isVerified'] as bool
          : (j['providerIsVerified'] is bool
              ? j['providerIsVerified'] as bool
              : null),
      isOwnReel: j['isOwnReel'] == true,
    );
  }
}
