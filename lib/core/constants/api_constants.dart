class ApiConstants {
  static const String baseUrl =
      'https://qbkqz1b4-4000.inc1.devtunnels.ms/api/v1'; // Android emulator
  // static const String baseUrl = 'http://localhost:5000/api/v1'; // iOS simulator

  // App
  static const String bootstrap = '/app/bootstrap';
  static const String appMe = '/app/me';
  static const String appMeProfile = '/app/me/profile';
  static const String switchMode = '/app/me/switch-mode';
  static const String myProvider = '/app/me/provider';
  static const String myProviderReels = '/app/me/provider/reels';
  static const String myProviderPhotos = '/app/me/provider/photos';
  static const String myProviderSaved = '/app/me/provider/saved';

  // Auth
  static const String requestOtp = '/auth/request-otp';
  static const String verifyOtp = '/auth/verify-otp';

  // Users
  static const String me = '/users/me';
  static const String updateProfile = '/a/me/profile';

  // Providers
  static const String becomeProvider = '/providers/become';
  static const String providerById = '/providers'; // + /:id
  static const String userProviderOverview =
      '/app/userproviders'; // + /:id (public provider profile overview)

  // Skills
  static const String skills = '/skills';

  // Reels
  static const String reels = '/reels';

  // Feed
  static const String feedHome = '/feed/home';
  static const String feedTrending = '/feed/trending';
  static const String feedFollowing = '/feed/following';
  static const String feedNearby = '/feed/nearby';

  // Search
  static const String search = '/app/discover/search';
  static const String searchCategories = '/app/discover/search/categories';
  static const String searchReelsByCategory = '/app/discover/search/reels';

  // Enquiries
  static const String enquiries = '/enquiries';

  // Chats
  static const String threads = '/app/social/chats/threads';
  static const String messages = '/app/social/chats/threads'; // + /:id/messages

  // Follows
  static const String follows = '/follows'; // + /:providerId

  // Reviews
  static const String reviews = '/reviews';

  // Notifications
  static const String notifications = '/notifications';

  // Reports
  static const String reports = '/reports';

  // Interactions (single endpoint)
  static const String interactions = '/app/social/interactions';

  // Push notifications
  static const String pushToken = '/app/social/notifications/push-token';
}
