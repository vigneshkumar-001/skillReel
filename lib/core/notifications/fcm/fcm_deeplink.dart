String? fcmExtractRoute(Map<String, dynamic> data) {
  final rawRoute = data['route']?.toString();
  if (rawRoute != null && rawRoute.trim().isNotEmpty) {
    return rawRoute.trim();
  }

  final reelId = data['reelId']?.toString();
  if (reelId != null && reelId.trim().isNotEmpty) {
    return '/reel/${reelId.trim()}';
  }

  // Provider public profiles now route via /user/:providerId in the app.
  final providerId = data['providerId']?.toString();
  if (providerId != null && providerId.trim().isNotEmpty) {
    return '/user/${providerId.trim()}';
  }

  return null;
}

