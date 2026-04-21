import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/otp_request_screen.dart';
import '../../features/auth/screens/otp_verify_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/search/screens/category_reels_screen.dart';
import '../../features/reels/screens/reels_feed_screen.dart';
import '../../features/reels/screens/reel_detail_screen.dart';
import '../../features/reels/screens/upload_reel_screen.dart';
import '../../features/reels/screens/my_provider_reels_player_screen.dart';
import '../../features/reels/screens/my_provider_photos_viewer_screen.dart';
import '../../features/reels/screens/saved_reels_player_screen.dart';
import '../../features/chat/screens/threads_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/models/chat_header.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/saved_reels_screen.dart';
import '../../features/profile/screens/user_profile_screen.dart';
import '../../features/providers_module/screens/provider_profile_screen.dart';
import '../../features/providers_module/screens/provider_settings_screen.dart';
import '../../features/enquiries/screens/enquiry_form_screen.dart';
import '../../features/enquiries/screens/my_enquiries_screen.dart';
import '../../features/reviews/screens/review_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/shell/screens/main_shell.dart';
import '../services/storage_service.dart';
import 'route_observer.dart';

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

final appRouter = GoRouter(
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
      builder: (_, __, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (_, state) => _slideFadePage(state, const HomeScreen()),
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
              header:
                  state.extra is ChatHeader ? state.extra as ChatHeader : null,
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
          path: '/provider/:id',
          pageBuilder: (_, state) => _slideFadePage(
            state,
            ProviderProfileScreen(providerId: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/user/:id',
          redirect: (_, state) async {
            final requestedId = state.pathParameters['id']?.trim();
            if (requestedId == null || requestedId.isEmpty) return null;
            final myId = (await StorageService.instance.getUserId())?.trim();
            if (myId == null || myId.isEmpty) return null;
            if (requestedId == myId) return '/profile/view';
            return null;
          },
          pageBuilder: (_, state) => _slideFadePage(
            state,
            UserProfileScreen(
              userId: state.pathParameters['id']!,
              seed: state.extra is UserProfileSeed
                  ? state.extra as UserProfileSeed
                  : null,
            ),
          ),
        ),
      ],
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
          initialPhotoId: state.extra is String ? state.extra as String : null,
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
      path: '/provider/become',
      builder: (_, __) => ProviderSettingsScreen(mode: ProviderSettingsMode.create),
    ),
    GoRoute(
      path: '/provider/settings',
      builder: (_, __) => ProviderSettingsScreen(mode: ProviderSettingsMode.edit),
    ),
    GoRoute(
      path: '/enquiry/new',
      builder: (_, state) {
        final providerId = state.extra as String;
        return EnquiryFormScreen(providerId: providerId);
      },
    ),
    GoRoute(
        path: '/enquiries/mine', builder: (_, __) => const MyEnquiriesScreen()),
    GoRoute(
      path: '/review/new',
      builder: (_, state) {
        final providerId = state.extra as String;
        return ReviewScreen(providerId: providerId);
      },
    ),
    GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen()),
    GoRoute(
        path: '/profile/edit', builder: (_, __) => const EditProfileScreen()),
    GoRoute(
        path: '/profile/saved', builder: (_, __) => const SavedReelsScreen()),
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
