import '../../utils/url_utils.dart';

class AppBootstrapResponse {
  final bool success;
  final String message;
  final AppBootstrapData data;
  final dynamic meta;

  const AppBootstrapResponse({
    required this.success,
    required this.message,
    required this.data,
    this.meta,
  });

  factory AppBootstrapResponse.fromJson(Map<String, dynamic> j) {
    return AppBootstrapResponse(
      success: j['success'] == true,
      message: (j['message'] ?? '').toString(),
      data: AppBootstrapData.fromJson(_asMap(j['data'])),
      meta: j['meta'],
    );
  }
}

class AppBootstrapData {
  final BootstrapUser user;
  final BootstrapProvider provider;
  final BootstrapSubscription subscription;
  final BootstrapRestriction restriction;
  final BootstrapModeSummary modeSummary;

  const AppBootstrapData({
    required this.user,
    required this.provider,
    required this.subscription,
    required this.restriction,
    required this.modeSummary,
  });

  factory AppBootstrapData.fromJson(Map<String, dynamic> j) {
    return AppBootstrapData(
      user: BootstrapUser.fromJson(_asMap(j['user'])),
      provider: BootstrapProvider.fromJson(_asMap(j['provider'])),
      subscription: BootstrapSubscription.fromJson(_asMap(j['subscription'])),
      restriction: BootstrapRestriction.fromJson(_asMap(j['restriction'])),
      modeSummary: BootstrapModeSummary.fromJson(_asMap(j['modeSummary'])),
    );
  }
}

class BootstrapUser {
  final String id;
  final String role;
  final String mode;
  final String name;
  final String mobile;
  final String avatar;
  final String bio;
  final BootstrapLocation location;
  final List<String> savedReels;
  final int profileCompleteness;
  final String createdAt;
  final String updatedAt;
  final String email;

  const BootstrapUser({
    required this.id,
    required this.role,
    required this.mode,
    required this.name,
    required this.mobile,
    required this.avatar,
    required this.bio,
    required this.location,
    required this.savedReels,
    required this.profileCompleteness,
    required this.createdAt,
    required this.updatedAt,
    required this.email,
  });

  factory BootstrapUser.fromJson(Map<String, dynamic> j) {
    return BootstrapUser(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      role: (j['role'] ?? '').toString(),
      mode: (j['mode'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      mobile: (j['mobile'] ?? '').toString(),
      avatar: UrlUtils.normalizeMediaUrl(j['avatar']?.toString()),
      bio: (j['bio'] ?? '').toString(),
      location: BootstrapLocation.fromJson(_asMap(j['location'])),
      savedReels: _asStringList(j['savedReels']),
      profileCompleteness: _asInt(j['profileCompleteness']),
      createdAt: (j['createdAt'] ?? '').toString(),
      updatedAt: (j['updatedAt'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
    );
  }
}

class BootstrapProvider {
  final String id;
  final BootstrapProviderUserLite user;
  final String displayName;
  final List<BootstrapSkill> skills;
  final int experienceYears;
  final String bio;
  final BootstrapLocation location;
  final int serviceRadiusKm;
  final bool callEnabled;
  final bool chatOnlyMode;
  final bool isVerified;
  final bool isActive;
  final double trustScore;
  final double averageRating;
  final int totalReviews;
  final int followerCount;
  final int enquiryCount;
  final double visibilityScore;
  final List<String> badges;
  final String createdAt;
  final String updatedAt;
  final String approvalStatus;

  const BootstrapProvider({
    required this.id,
    required this.user,
    required this.displayName,
    required this.skills,
    required this.experienceYears,
    required this.bio,
    required this.location,
    required this.serviceRadiusKm,
    required this.callEnabled,
    required this.chatOnlyMode,
    required this.isVerified,
    required this.isActive,
    required this.trustScore,
    required this.averageRating,
    required this.totalReviews,
    required this.followerCount,
    required this.enquiryCount,
    required this.visibilityScore,
    required this.badges,
    required this.createdAt,
    required this.updatedAt,
    required this.approvalStatus,
  });

  factory BootstrapProvider.fromJson(Map<String, dynamic> j) {
    return BootstrapProvider(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      user: BootstrapProviderUserLite.fromJson(_asMap(j['userId'])),
      displayName: (j['displayName'] ?? '').toString(),
      skills: _asList(j['skills'])
          .map((e) => BootstrapSkill.fromJson(_asMap(e)))
          .toList(growable: false),
      experienceYears: _asInt(j['experienceYears']),
      bio: (j['bio'] ?? '').toString(),
      location: BootstrapLocation.fromJson(_asMap(j['location'])),
      serviceRadiusKm: _asInt(j['serviceRadiusKm']),
      callEnabled: j['callEnabled'] == true,
      chatOnlyMode: j['chatOnlyMode'] == true,
      isVerified: j['isVerified'] == true,
      isActive: j['isActive'] == true,
      trustScore: _asDouble(j['trustScore']),
      averageRating: _asDouble(j['averageRating']),
      totalReviews: _asInt(j['totalReviews']),
      followerCount: _asInt(j['followerCount']),
      enquiryCount: _asInt(j['enquiryCount']),
      visibilityScore: _asDouble(j['visibilityScore']),
      badges: _asStringList(j['badges']),
      createdAt: (j['createdAt'] ?? '').toString(),
      updatedAt: (j['updatedAt'] ?? '').toString(),
      approvalStatus: (j['approvalStatus'] ?? '').toString(),
    );
  }
}

class BootstrapProviderUserLite {
  final String id;
  final String name;
  final String avatar;
  final String bio;

  const BootstrapProviderUserLite({
    required this.id,
    required this.name,
    required this.avatar,
    required this.bio,
  });

  factory BootstrapProviderUserLite.fromJson(Map<String, dynamic> j) {
    return BootstrapProviderUserLite(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      avatar: UrlUtils.normalizeMediaUrl(j['avatar']?.toString()),
      bio: (j['bio'] ?? '').toString(),
    );
  }
}

class BootstrapSkill {
  final String id;
  final String name;
  final String slug;
  final bool isActive;
  final List<String> aliases;
  final String createdAt;
  final String updatedAt;
  final String? imageUrl;
  final String? category;

  const BootstrapSkill({
    required this.id,
    required this.name,
    required this.slug,
    required this.isActive,
    required this.aliases,
    required this.createdAt,
    required this.updatedAt,
    this.imageUrl,
    this.category,
  });

  factory BootstrapSkill.fromJson(Map<String, dynamic> j) {
    return BootstrapSkill(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      slug: (j['slug'] ?? '').toString(),
      isActive: j['isActive'] == true,
      aliases: _asStringList(j['aliases']),
      createdAt: (j['createdAt'] ?? '').toString(),
      updatedAt: (j['updatedAt'] ?? '').toString(),
      imageUrl: (j['imageUrl'] == null)
          ? null
          : UrlUtils.normalizeMediaUrl(j['imageUrl']?.toString()),
      category: j['category']?.toString(),
    );
  }
}

class BootstrapSubscription {
  final String id;
  final String userId;
  final String planCode;
  final String status;
  final String startsAt;
  final String endsAt;
  final String createdAt;
  final String updatedAt;

  const BootstrapSubscription({
    required this.id,
    required this.userId,
    required this.planCode,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BootstrapSubscription.fromJson(Map<String, dynamic> j) {
    return BootstrapSubscription(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      userId: (j['userId'] ?? '').toString(),
      planCode: (j['planCode'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      startsAt: (j['startsAt'] ?? '').toString(),
      endsAt: (j['endsAt'] ?? '').toString(),
      createdAt: (j['createdAt'] ?? '').toString(),
      updatedAt: (j['updatedAt'] ?? '').toString(),
    );
  }
}

class BootstrapRestriction {
  final String id;
  final String scopeType;
  final String scopeId;
  final int enquiryLimitPerDay;
  final int uploadLimitPerDay;
  final bool isRestricted;
  final int reportCount;
  final int spamScore;
  final int visibilityPenalty;
  final String createdAt;
  final String updatedAt;
  final String? restrictionReason;

  const BootstrapRestriction({
    required this.id,
    required this.scopeType,
    required this.scopeId,
    required this.enquiryLimitPerDay,
    required this.uploadLimitPerDay,
    required this.isRestricted,
    required this.reportCount,
    required this.spamScore,
    required this.visibilityPenalty,
    required this.createdAt,
    required this.updatedAt,
    this.restrictionReason,
  });

  factory BootstrapRestriction.fromJson(Map<String, dynamic> j) {
    return BootstrapRestriction(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      scopeType: (j['scopeType'] ?? '').toString(),
      scopeId: (j['scopeId'] ?? '').toString(),
      enquiryLimitPerDay: _asInt(j['enquiryLimitPerDay']),
      uploadLimitPerDay: _asInt(j['uploadLimitPerDay']),
      isRestricted: j['isRestricted'] == true,
      reportCount: _asInt(j['reportCount']),
      spamScore: _asInt(j['spamScore']),
      visibilityPenalty: _asInt(j['visibilityPenalty']),
      createdAt: (j['createdAt'] ?? '').toString(),
      updatedAt: (j['updatedAt'] ?? '').toString(),
      restrictionReason: j['restrictionReason']?.toString(),
    );
  }
}

class BootstrapModeSummary {
  final String role;
  final String mode;
  final bool hasProviderProfile;
  final String providerApprovalStatus;
  final bool canSwitchToProvider;
  final String? switchToProviderReason;

  const BootstrapModeSummary({
    required this.role,
    required this.mode,
    required this.hasProviderProfile,
    required this.providerApprovalStatus,
    required this.canSwitchToProvider,
    this.switchToProviderReason,
  });

  factory BootstrapModeSummary.fromJson(Map<String, dynamic> j) {
    return BootstrapModeSummary(
      role: (j['role'] ?? '').toString(),
      mode: (j['mode'] ?? '').toString(),
      hasProviderProfile: j['hasProviderProfile'] == true,
      providerApprovalStatus: (j['providerApprovalStatus'] ?? '').toString(),
      canSwitchToProvider: j['canSwitchToProvider'] == true,
      switchToProviderReason: j['switchToProviderReason']?.toString(),
    );
  }
}

class BootstrapLocation {
  final String city;
  final String state;
  final String country;
  final double lat;
  final double lng;
  final BootstrapGeoPoint? coordinates;

  const BootstrapLocation({
    required this.city,
    required this.state,
    required this.country,
    required this.lat,
    required this.lng,
    this.coordinates,
  });

  factory BootstrapLocation.fromJson(Map<String, dynamic> j) {
    return BootstrapLocation(
      city: (j['city'] ?? '').toString(),
      state: (j['state'] ?? '').toString(),
      country: (j['country'] ?? '').toString(),
      lat: _asDouble(j['lat']),
      lng: _asDouble(j['lng']),
      coordinates: (j['coordinates'] is Map)
          ? BootstrapGeoPoint.fromJson(_asMap(j['coordinates']))
          : null,
    );
  }
}

class BootstrapGeoPoint {
  final String type;
  final List<double> coordinates;

  const BootstrapGeoPoint({required this.type, required this.coordinates});

  factory BootstrapGeoPoint.fromJson(Map<String, dynamic> j) {
    final coords = _asList(j['coordinates'])
        .map((e) => _asDouble(e))
        .toList(growable: false);
    return BootstrapGeoPoint(
      type: (j['type'] ?? '').toString(),
      coordinates: coords,
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

List<String> _asStringList(Object? v) {
  if (v is List) {
    return v.map((e) => e.toString()).toList(growable: false);
  }
  return const [];
}
