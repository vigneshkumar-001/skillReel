class ProviderModel {
  final String id;
  final String? userId;
  final String displayName;
  final String? avatar;
  final List<String> skills;
  final String? bio;
  final String? city;
  final String? state;
  final String? country;
  final double averageRating;
  final int totalReviews;
  final int followerCount;
  final int enquiryCount;
  final bool isVerified;
  final bool isActive;
  final double trustScore;
  final bool callEnabled;

  ProviderModel({
    required this.id,
    this.userId,
    required this.displayName,
    this.avatar,
    required this.skills,
    this.bio,
    this.city,
    this.state,
    this.country,
    required this.averageRating,
    required this.totalReviews,
    required this.followerCount,
    required this.enquiryCount,
    required this.isVerified,
    required this.isActive,
    required this.trustScore,
    required this.callEnabled,
  });

  factory ProviderModel.fromJson(Map<String, dynamic> j) {
    final userObj = j['userId'];
    final user = userObj is Map ? Map<String, dynamic>.from(userObj) : const <String, dynamic>{};
    final userId = userObj is String
        ? userObj
        : (userObj is Map ? (user['_id'] ?? user['id'])?.toString() : null);

    final locationObj = j['location'];
    final location = locationObj is Map
        ? Map<String, dynamic>.from(locationObj)
        : const <String, dynamic>{};

    return ProviderModel(
      id: j['_id'] ?? j['id'] ?? '',
      userId: (userId ?? '').trim().isEmpty ? null : userId,
      displayName: j['displayName'] ?? '',
      avatar: j['avatar'] ?? user['avatar'],
      skills: _parseSkills(j['skills']),
      bio: j['bio'],
      city: location['city'],
      state: location['state'],
      country: location['country'],
      averageRating: (j['averageRating'] ?? 0).toDouble(),
      totalReviews: j['totalReviews'] ?? 0,
      followerCount: j['followerCount'] ?? 0,
      enquiryCount: j['enquiryCount'] ?? 0,
      isVerified: j['isVerified'] ?? false,
      isActive: j['isActive'] ?? true,
      trustScore: (j['trustScore'] ?? 0).toDouble(),
      callEnabled: j['callEnabled'] ?? true,
    );
  }

  static List<String> _parseSkills(dynamic raw) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    for (final e in raw) {
      if (e is String) {
        final t = e.trim();
        if (t.isNotEmpty) out.add(t);
        continue;
      }
      if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        final name = (m['name'] ?? '').toString().trim();
        final id = (m['_id'] ?? m['id'] ?? '').toString().trim();
        final best = name.isNotEmpty ? name : id;
        if (best.isNotEmpty) out.add(best);
        continue;
      }
      final t = e.toString().trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }
}
