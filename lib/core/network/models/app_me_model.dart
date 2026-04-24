import '../../utils/url_utils.dart';

class AppMeResponse {
  final bool success;
  final String message;
  final AppMeData data;
  final dynamic meta;

  const AppMeResponse({
    required this.success,
    required this.message,
    required this.data,
    this.meta,
  });

  factory AppMeResponse.fromJson(Map<String, dynamic> j) {
    return AppMeResponse(
      success: j['success'] == true,
      message: (j['message'] ?? '').toString(),
      data: AppMeData.fromJson(_asMap(j['data'])),
      meta: j['meta'],
    );
  }
}

/// Supports BOTH legacy shape:
///   { user: {...}, provider: {...}, modeSummary: {...} }
/// AND new unified shape:
///   { id, userId, displayName, name, email, ... modeSummary }
class AppMeData {
  final AppMeUnifiedProfile profile;

  const AppMeData({required this.profile});

  factory AppMeData.fromJson(Map<String, dynamic> j) {
    final hasLegacy = j.containsKey('user') || j.containsKey('provider');
    return AppMeData(
      profile: hasLegacy
          ? AppMeUnifiedProfile.fromLegacyJson(j)
          : AppMeUnifiedProfile.fromJson(j),
    );
  }
}

class AppMeUnifiedProfile {
  final String id;
  final String userId;
  final String displayName;
  final String name;
  final String email;
  final String mobile;
  final String avatarUrl;
  final String initials;
  final String headline;
  final String bio;
  final String websiteUrl;
  final String availability;
  final List<AppMeSkillLite> skills;
  final AppMeLocation location;
  final int serviceRadiusKm;
  final int profileCompleteness;
  final AppMeVerification verification;
  final AppMeCommunication communication;
  final AppMeViewer viewer;
  final AppMeStats stats;
  final List<AppMeTab> tabs;
  final AppMeModeSummary modeSummary;

  const AppMeUnifiedProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.name,
    required this.email,
    required this.mobile,
    required this.avatarUrl,
    required this.initials,
    required this.headline,
    required this.bio,
    required this.websiteUrl,
    required this.availability,
    required this.skills,
    required this.location,
    required this.serviceRadiusKm,
    required this.profileCompleteness,
    required this.verification,
    required this.communication,
    required this.viewer,
    required this.stats,
    required this.tabs,
    required this.modeSummary,
  });

  factory AppMeUnifiedProfile.fromJson(Map<String, dynamic> j) {
    return AppMeUnifiedProfile(
      id: (j['id'] ?? j['_id'] ?? '').toString(),
      userId: (j['userId'] ?? '').toString(),
      displayName: (j['displayName'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      mobile: (j['mobile'] ?? '').toString(),
      avatarUrl: UrlUtils.normalizeMediaUrl(j['avatarUrl']?.toString()),
      initials: (j['initials'] ?? '').toString(),
      headline: (j['headline'] ?? '').toString(),
      bio: (j['bio'] ?? '').toString(),
      websiteUrl: (j['websiteUrl'] ?? '').toString(),
      availability: (j['availability'] ?? j['availabilityText'] ?? '').toString(),
      skills: _asList(j['skills'])
          .map((e) => AppMeSkillLite.fromJson(_asMap(e)))
          .toList(growable: false),
      location: AppMeLocation.fromJson(_asMap(j['location'])),
      serviceRadiusKm: _asInt(j['serviceRadiusKm']),
      profileCompleteness: _asInt(j['profileCompleteness']),
      verification: AppMeVerification.fromJson(_asMap(j['verification'])),
      communication: AppMeCommunication.fromJson(_asMap(j['communication'])),
      viewer: AppMeViewer.fromJson(_asMap(j['viewer'])),
      stats: AppMeStats.fromJson(_asMap(j['stats'])),
      tabs: _asList(j['tabs'])
          .map((e) => AppMeTab.fromJson(_asMap(e)))
          .toList(growable: false),
      modeSummary: AppMeModeSummary.fromJson(_asMap(j['modeSummary'])),
    );
  }

  factory AppMeUnifiedProfile.fromLegacyJson(Map<String, dynamic> legacy) {
    final user = _asMap(legacy['user']);
    final provider = _asMap(legacy['provider']);
    final modeSummary = _asMap(legacy['modeSummary']);

    final userLocation = _asMap(user['location']);
    final userId = (user['_id'] ?? user['id'] ?? '').toString();

    final providerId = (provider['_id'] ?? provider['id'] ?? '').toString();
    final displayName = (provider['displayName'] ?? '').toString();

    final skillsRaw = provider['skills'];
    final skills = (skillsRaw is List)
        ? skillsRaw
            .map((e) => AppMeSkillLite.fromLegacyJson(_asMap(e)))
            .toList(growable: false)
        : const <AppMeSkillLite>[];

    final providerLocation = _asMap(provider['location']);
    final location = providerLocation.isNotEmpty
        ? AppMeLocation.fromLegacyJson(providerLocation)
        : AppMeLocation.fromLegacyJson(userLocation);

    final verification = AppMeVerification(
      isVerified: provider['isVerified'] == true,
      trustScore: _asDouble(provider['trustScore']),
      averageRating: _asDouble(provider['averageRating']),
      totalReviews: _asInt(provider['totalReviews']),
      badges: _asStringList(provider['badges']),
    );

    final communication = AppMeCommunication(
      callEnabled: provider['callEnabled'] == true,
      chatOnlyMode: provider['chatOnlyMode'] == true,
    );

    final mode = (user['mode'] ?? modeSummary['mode'] ?? '').toString();
    final role = (user['role'] ?? modeSummary['role'] ?? '').toString();

    return AppMeUnifiedProfile(
      id: providerId,
      userId: userId,
      displayName: displayName,
      name: (user['name'] ?? '').toString(),
      email: (user['email'] ?? '').toString(),
      mobile: (user['mobile'] ?? '').toString(),
      avatarUrl: UrlUtils.normalizeMediaUrl(
        (user['avatar'] ?? provider['avatar'])?.toString(),
      ),
      initials: '',
      headline: '',
      bio: (provider['bio'] ?? user['bio'] ?? '').toString(),
      websiteUrl:
          (provider['websiteUrl'] ?? user['websiteUrl'] ?? '').toString(),
      availability: (provider['availability'] ??
              provider['availabilityText'] ??
              user['availability'] ??
              user['availabilityText'] ??
              '')
          .toString(),
      skills: skills,
      location: location,
      serviceRadiusKm: _asInt(provider['serviceRadiusKm']),
      profileCompleteness: _asInt(user['profileCompleteness']),
      verification: verification,
      communication: communication,
      viewer:
          const AppMeViewer(isOwner: true, isFollowing: false, canEdit: true),
      stats: const AppMeStats(
        posts: AppMeStatItem(value: 0, label: '0'),
        followers: AppMeStatItem(value: 0, label: '0'),
        following: AppMeStatItem(value: 0, label: '0'),
        likes: AppMeStatItem(value: 0, label: '0'),
        views: AppMeStatItem(value: 0, label: '0'),
      ),
      tabs: const [],
      modeSummary: AppMeModeSummary(
        role: role,
        mode: mode,
        hasProviderProfile: _asBool(modeSummary['hasProviderProfile']),
        providerApprovalStatus:
            (modeSummary['providerApprovalStatus'] ?? '').toString(),
        canSwitchToProvider: _asBool(modeSummary['canSwitchToProvider']),
        switchToProviderReason:
            modeSummary['switchToProviderReason']?.toString(),
      ),
    );
  }

  Map<String, dynamic> toProfileMap() {
    final mode = modeSummary.mode.isNotEmpty ? modeSummary.mode : 'user';
    final role = modeSummary.role;
    final isProvider = modeSummary.hasProviderProfile || mode == 'provider';
    final computedHeadline = headline.trim().isNotEmpty
        ? headline.trim()
        : (skills.isNotEmpty ? skills.first.name.trim() : '');

    return <String, dynamic>{
      '_id': userId,
      'mode': mode,
      'role': role,

      // Display in ProfileScreen.
      'name': displayName.trim().isNotEmpty ? displayName.trim() : name,
      'userName': name,
      'email': email,
      'mobile': mobile,
      'avatar': avatarUrl,
      'headline': computedHeadline,
      'bio': bio,
      'websiteUrl': websiteUrl,
      'availability': availability,
      'location': {
        'city': location.city,
        'state': location.state,
        'country': location.country,
        'lat': location.lat,
        'lng': location.lng,
      },

      // Provider summary used by menus + toggles.
      'isProvider': isProvider,
      'provider': {
        'id': id,
        'displayName': displayName,
        'availability': availability,
        'isVerified': verification.isVerified,
        'trustScore': verification.trustScore,
        'totalReviews': verification.totalReviews,
        'averageRating': verification.averageRating,
        'badges': verification.badges,
        'callEnabled': communication.callEnabled,
        'chatOnlyMode': communication.chatOnlyMode,
        'skillCount': skills.length,
      },

      // Counts used by ProfileScreen helpers.
      'postsCount': stats.posts.value,
      'followersCount': stats.followers.value,
      'followingCount': stats.following.value,
      'likesCount': stats.likes.value,
      'viewsCount': stats.views.value,

      // Mode summary for switch-mode gating.
      'modeSummary': {
        'role': modeSummary.role,
        'mode': modeSummary.mode,
        'hasProviderProfile': modeSummary.hasProviderProfile,
        'providerApprovalStatus': modeSummary.providerApprovalStatus,
        'canSwitchToProvider': modeSummary.canSwitchToProvider,
        'switchToProviderReason': modeSummary.switchToProviderReason,
      },

      // Tab counts (photos/reels) if backend provides it.
      'tabs': tabs
          .map(
            (t) => <String, dynamic>{
              'key': t.key,
              'label': t.label,
              'count': t.count,
            },
          )
          .toList(growable: false),
    };
  }
}

class AppMeSkillLite {
  final String id;
  final String name;
  final String slug;
  final String? category;

  const AppMeSkillLite({
    required this.id,
    required this.name,
    required this.slug,
    this.category,
  });

  factory AppMeSkillLite.fromJson(Map<String, dynamic> j) {
    return AppMeSkillLite(
      id: (j['id'] ?? j['_id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      slug: (j['slug'] ?? '').toString(),
      category: j['category']?.toString(),
    );
  }

  factory AppMeSkillLite.fromLegacyJson(Map<String, dynamic> j) {
    return AppMeSkillLite(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      slug: (j['slug'] ?? '').toString(),
      category: j['category']?.toString(),
    );
  }
}

class AppMeLocation {
  final String city;
  final String state;
  final String country;
  final double lat;
  final double lng;

  const AppMeLocation({
    required this.city,
    required this.state,
    required this.country,
    required this.lat,
    required this.lng,
  });

  factory AppMeLocation.fromJson(Map<String, dynamic> j) {
    return AppMeLocation(
      city: (j['city'] ?? '').toString(),
      state: (j['state'] ?? '').toString(),
      country: (j['country'] ?? '').toString(),
      lat: _asDouble(j['lat']),
      lng: _asDouble(j['lng']),
    );
  }

  factory AppMeLocation.fromLegacyJson(Map<String, dynamic> j) {
    return AppMeLocation(
      city: (j['city'] ?? '').toString(),
      state: (j['state'] ?? '').toString(),
      country: (j['country'] ?? '').toString(),
      lat: _asDouble(j['lat']),
      lng: _asDouble(j['lng']),
    );
  }
}

class AppMeVerification {
  final bool isVerified;
  final double trustScore;
  final double averageRating;
  final int totalReviews;
  final List<String> badges;

  const AppMeVerification({
    required this.isVerified,
    required this.trustScore,
    required this.averageRating,
    required this.totalReviews,
    required this.badges,
  });

  factory AppMeVerification.fromJson(Map<String, dynamic> j) {
    return AppMeVerification(
      isVerified: j['isVerified'] == true,
      trustScore: _asDouble(j['trustScore']),
      averageRating: _asDouble(j['averageRating']),
      totalReviews: _asInt(j['totalReviews']),
      badges: _asStringList(j['badges']),
    );
  }
}

class AppMeCommunication {
  final bool callEnabled;
  final bool chatOnlyMode;

  const AppMeCommunication({
    required this.callEnabled,
    required this.chatOnlyMode,
  });

  factory AppMeCommunication.fromJson(Map<String, dynamic> j) {
    return AppMeCommunication(
      callEnabled: j['callEnabled'] == true,
      chatOnlyMode: j['chatOnlyMode'] == true,
    );
  }
}

class AppMeViewer {
  final bool isOwner;
  final bool isFollowing;
  final bool canEdit;

  const AppMeViewer({
    required this.isOwner,
    required this.isFollowing,
    required this.canEdit,
  });

  factory AppMeViewer.fromJson(Map<String, dynamic> j) {
    return AppMeViewer(
      isOwner: j['isOwner'] == true,
      isFollowing: j['isFollowing'] == true,
      canEdit: j['canEdit'] == true,
    );
  }
}

class AppMeStats {
  final AppMeStatItem posts;
  final AppMeStatItem followers;
  final AppMeStatItem following;
  final AppMeStatItem likes;
  final AppMeStatItem views;

  const AppMeStats({
    required this.posts,
    required this.followers,
    required this.following,
    required this.likes,
    required this.views,
  });

  factory AppMeStats.fromJson(Map<String, dynamic> j) {
    return AppMeStats(
      posts: AppMeStatItem.fromJson(_asMap(_asMap(j['posts']))),
      followers: AppMeStatItem.fromJson(_asMap(_asMap(j['followers']))),
      following: AppMeStatItem.fromJson(_asMap(_asMap(j['following']))),
      likes: AppMeStatItem.fromJson(_asMap(_asMap(j['likes']))),
      views: AppMeStatItem.fromJson(_asMap(_asMap(j['views']))),
    );
  }
}

class AppMeStatItem {
  final int value;
  final String label;

  const AppMeStatItem({required this.value, required this.label});

  factory AppMeStatItem.fromJson(Map<String, dynamic> j) {
    return AppMeStatItem(
      value: _asInt(j['value']),
      label: (j['label'] ?? '').toString(),
    );
  }
}

class AppMeTab {
  final String key;
  final String label;
  final int count;

  const AppMeTab({required this.key, required this.label, required this.count});

  factory AppMeTab.fromJson(Map<String, dynamic> j) {
    return AppMeTab(
      key: (j['key'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      count: _asInt(j['count']),
    );
  }
}

class AppMeModeSummary {
  final String role;
  final String mode;
  final bool hasProviderProfile;
  final String providerApprovalStatus;
  final bool canSwitchToProvider;
  final String? switchToProviderReason;

  const AppMeModeSummary({
    required this.role,
    required this.mode,
    required this.hasProviderProfile,
    required this.providerApprovalStatus,
    required this.canSwitchToProvider,
    this.switchToProviderReason,
  });

  factory AppMeModeSummary.fromJson(Map<String, dynamic> j) {
    return AppMeModeSummary(
      role: (j['role'] ?? '').toString(),
      mode: (j['mode'] ?? '').toString(),
      hasProviderProfile: _asBool(j['hasProviderProfile']),
      providerApprovalStatus: (j['providerApprovalStatus'] ?? '').toString(),
      canSwitchToProvider: _asBool(j['canSwitchToProvider']),
      switchToProviderReason: j['switchToProviderReason']?.toString(),
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

double _asDouble(Object? v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

bool _asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v?.toString().trim().toLowerCase();
  if (s == null || s.isEmpty) return false;
  return s == 'true' || s == '1' || s == 'yes' || s == 'y';
}

List<String> _asStringList(Object? v) {
  if (v is List) {
    return v.map((e) => e.toString()).toList(growable: false);
  }
  return const [];
}
