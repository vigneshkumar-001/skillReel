import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/otp_request_screen.dart';
import '../../features/auth/screens/otp_verify_screen.dart';
import '../../features/chat/models/chat_header.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/screens/threads_screen.dart';
import '../../features/enquiries/screens/enquiry_form_screen.dart';
import '../../features/enquiries/screens/my_enquiries_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/saved_reels_screen.dart';
import '../../features/profile/screens/user_profile_screen.dart';
import '../../features/providers_module/screens/provider_profile_screen.dart';
import '../../features/providers_module/screens/provider_settings_screen.dart';
import '../../features/reels/screens/my_provider_photos_viewer_screen.dart';
import '../../features/reels/screens/my_provider_reels_player_screen.dart';
import '../../features/reels/screens/reel_detail_screen.dart';
import '../../features/reels/screens/reels_feed_screen.dart';
import '../../features/reels/screens/saved_reels_player_screen.dart';
import '../../features/reels/screens/upload_reel_screen.dart';
import '../../features/reviews/screens/review_screen.dart';
import '../../features/search/screens/category_reels_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/shell/screens/main_shell.dart';
import '../services/storage_service.dart';
import 'route_observer.dart';

GoRouter? _appRouterInstance;

/// Sets the shared router instance used by services (FCM/local notifications).
///
/// Note: we intentionally keep the router instance owned by the app widget
/// (see `App` in `lib/app.dart`) so hot-reload doesn't recreate it and cause
/// `GlobalKey` collisions in go_router's internal `Navigator`.
void setAppRouter(GoRouter router) {
  _appRouterInstance = router;
}

/// Access to the app's router for non-UI services.
///
/// This throws if called before the app has built at least once.
GoRouter get appRouter {
  final r = _appRouterInstance;
  if (r == null) {
    throw StateError('appRouter not initialized yet');
  }
  return r;
}

CustomTransitionPage<void> _slideFadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

GoRouter createAppRouter() {
  final shellNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'shellNavigator');

  return GoRouter(
    initialLocation: '/auth/otp',
    observers: [routeObserver],
    redirect: (context, state) async {
      final token = await StorageService.instance.getToken();
      final onAuth = state.fullPath?.startsWith('/auth') ?? false;
      if (token == null && !onAuth) return '/auth/otp';
      if (token != null && onAuth) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/otp',
        builder: (_, __) => const OtpRequestScreen(),
      ),
      GoRoute(
        path: '/auth/verify',
        builder: (_, state) {
          final mobile = state.extra as String;
          return OtpVerifyScreen(mobile: mobile);
        },
      ),
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, state) =>
                _slideFadePage(state, const HomeScreen()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (_, state) =>
                _slideFadePage(state, const SearchScreen()),
          ),
          GoRoute(path: '/reels', builder: (_, __) => const ReelsFeedScreen()),
          GoRoute(
            path: '/chats',
            pageBuilder: (_, state) =>
                _slideFadePage(state, const ThreadsScreen()),
          ),
          GoRoute(
            path: '/chat/:threadId',
            pageBuilder: (_, state) => _slideFadePage(
              state,
              ChatScreen(
                threadId: state.pathParameters['threadId']!,
                header: state.extra is ChatHeader
                    ? state.extra as ChatHeader
                    : null,
              ),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, state) =>
                _slideFadePage(state, const ProfileScreen()),
          ),
          GoRoute(
            path: '/profile/view',
            pageBuilder: (_, state) =>
                _slideFadePage(state, const ProfileScreen()),
          ),
          GoRoute(
            path: '/provider/become',
            pageBuilder: (_, state) => _slideFadePage(
              state,
              const ProviderSettingsScreen(mode: ProviderSettingsMode.create),
            ),
          ),
          GoRoute(
            path: '/provider/settings',
            pageBuilder: (_, state) => _slideFadePage(
              state,
              const ProviderSettingsScreen(mode: ProviderSettingsMode.edit),
            ),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (_, state) =>
                _slideFadePage(state, const NotificationsScreen()),
          ),
          GoRoute(
            path: '/enquiries/mine',
            pageBuilder: (_, state) =>
                _slideFadePage(state, const MyEnquiriesScreen()),
          ),
          GoRoute(
            path: '/profile/edit',
            pageBuilder: (_, state) =>
                _slideFadePage(state, const EditProfileScreen()),
          ),
          GoRoute(
            path: '/profile/saved',
            pageBuilder: (_, state) =>
                _slideFadePage(state, const SavedReelsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/user/:id',
        pageBuilder: (_, state) => _slideFadePage(
          state,
          UserProfileScreen(providerId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/provider/:id',
        pageBuilder: (_, state) => _slideFadePage(
          state,
          ProviderProfileScreen(providerId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/reel/upload',
        builder: (_, state) => UploadReelScreen(
          initialMediaType:
              (state.extra is String) ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/reel/:id',
        pageBuilder: (_, state) => _slideFadePage(
          state,
          ReelDetailScreen(
            reelId: state.pathParameters['id']!,
            feedType: state.extra is String ? state.extra as String : 'home',
          ),
        ),
      ),
      GoRoute(
        path: '/reels/my',
        pageBuilder: (_, state) => _slideFadePage(
          state,
          MyProviderReelsPlayerScreen(
            initialReelId: state.extra is String
                ? state.extra as String
                : (state.extra is Map
                    ? (state.extra as Map)['id']?.toString()
                    : null),
            heroTag: state.extra is Map
                ? (state.extra as Map)['heroTag']?.toString()
                : null,
            heroThumbUrl: state.extra is Map
                ? (state.extra as Map)['thumbUrl']?.toString()
                : null,
          ),
        ),
      ),
      GoRoute(
        path: '/photos/my',
        pageBuilder: (_, state) => _slideFadePage(
          state,
          MyProviderPhotosViewerScreen(
            initialPhotoId:
                state.extra is String ? state.extra as String : null,
          ),
        ),
      ),
      GoRoute(
        path: '/reels/saved',
        pageBuilder: (_, state) => _slideFadePage(
          state,
          SavedReelsPlayerScreen(
            initialReelId: state.extra is String
                ? state.extra as String
                : (state.extra is Map
                    ? (state.extra as Map)['id']?.toString()
                    : null),
            heroTag: state.extra is Map
                ? (state.extra as Map)['heroTag']?.toString()
                : null,
            heroThumbUrl: state.extra is Map
                ? (state.extra as Map)['thumbUrl']?.toString()
                : null,
          ),
        ),
      ),
      GoRoute(
        path: '/enquiry/new',
        builder: (_, state) {
          final providerId = state.extra as String;
          return EnquiryFormScreen(providerId: providerId);
        },
      ),
      GoRoute(
        path: '/review/new',
        builder: (_, state) {
          final providerId = state.extra as String;
          return ReviewScreen(providerId: providerId);
        },
      ),
      GoRoute(
        path: '/search/category/:key',
        pageBuilder: (_, state) => _slideFadePage(
          state,
          CategoryReelsScreen(
            categoryKey: state.pathParameters['key'] ?? '',
            title: state.extra is String ? state.extra as String : '',
          ),
        ),
      ),
    ],
  );
}
