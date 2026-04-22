import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../reels/providers/reels_viewer_provider.dart';
import '../../../core/notifications/permission/notification_permission_banner.dart';

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = [
    (
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      route: '/home'
    ),
    (
      label: 'Search',
      icon: Icons.search,
      activeIcon: Icons.search,
      route: '/search'
    ),
    (
      label: 'Post',
      icon: Icons.add,
      activeIcon: Icons.add,
      route: '/reel/upload'
    ),
    (
      label: 'Chats',
      icon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      route: '/chats'
    ),
    (
      label: 'Profile',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      route: '/profile'
    ),
  ];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    // Don't "select" the Post (+) tab route.
    if (loc.startsWith('/reel')) return 0;
    if (loc.startsWith('/chat')) {
      return _tabs.indexWhere((t) => t.route == '/chats');
    }
    if (loc.startsWith('/user/') || loc.startsWith('/provider/')) {
      return _tabs.indexWhere((t) => t.route == '/profile');
    }
    final idx = _tabs.indexWhere(
        (t) => t.route != '/reel/upload' && loc.startsWith(t.route));
    return idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = _currentIndex(context).clamp(0, 4);
    final loc = GoRouterState.of(context).uri.toString();
    final isFullScreenRoute = loc.startsWith('/chat/') ||
        loc.startsWith('/user/') ||
        loc.startsWith('/provider/') ||
        loc.startsWith('/profile/view') ||
        loc.startsWith('/profile/edit') ||
        loc.startsWith('/profile/saved') ||
        loc.startsWith('/notifications') ||
        loc.startsWith('/enquiries/mine');
    if (isFullScreenRoute) {
      // Some routes should be full-screen (no bottom tabs).
      return Scaffold(
        body: Stack(
          children: [
            child,
            const NotificationPermissionBanner(),
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          child,
          const NotificationPermissionBanner(),
        ],
      ),
      bottomNavigationBar: _GlassBottomNav(
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              final selectedColor =
                  Color.lerp(Colors.white, AppColors.accent, 0.42)!;
              return TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: selected ? selectedColor : Colors.white70,
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: selected ? 26 : 24,
              );
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return AppColors.accent.withAlpha(28);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return AppColors.accent.withAlpha(14);
              }
              return Colors.transparent;
            }),
            indicatorColor: Colors.transparent,
          ),
          child: NavigationBar(
            selectedIndex: idx,
            elevation: 0,
            shadowColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            onDestinationSelected: (i) {
              if (i == 2) {
                HapticFeedback.mediumImpact();
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  barrierColor: Colors.black.withAlpha(110),
                  builder: (ctx) => SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          color: Colors.white,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 10),
                              const Text(
                                'Create',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Divider(
                                  height: 1, color: Color(0xFFF1F5F9)),
                              _CreateOption(
                                icon: Icons.file_upload_outlined,
                                tint: const Color(0xFFFF4D67),
                                title: 'Upload a Video',
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.of(ctx).pop();
                                  context.push('/reel/upload', extra: 'video');
                                },
                              ),
                              _CreateOption(
                                icon: Icons.image_outlined,
                                tint: const Color(0xFFFF4D67),
                                title: 'Upload an Image',
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.of(ctx).pop();
                                  context.push('/reel/upload', extra: 'image');
                                },
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              } else {
                if (i != idx) {
                  HapticFeedback.selectionClick();
                  context.go(_tabs[i].route);
                  return;
                }

                // Reselect behavior: tapping "Home" again refreshes the feed.
                if (i == 0) {
                  HapticFeedback.selectionClick();
                  ref
                      .read(
                        reelsViewerControllerProvider(
                          const ReelsFeedConfig(type: 'trending'),
                        ).notifier,
                      )
                      .refresh();
                }
                // Other tabs: no-op on reselect for now.
              }
            },
            destinations: _tabs
                .map(
                  (t) => NavigationDestination(
                    label: t.label,
                    icon: t.route == '/reel/upload'
                        ? const _PostNavButton(selected: false)
                        : _NavIcon(icon: t.icon, selected: false),
                    selectedIcon: t.route == '/reel/upload'
                        ? const _PostNavButton(selected: true)
                        : _NavIcon(icon: t.activeIcon, selected: true),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;

  const _NavIcon({required this.icon, required this.selected});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Colors.white70;

    if (!selected) {
      return Icon(icon, color: fg);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final scale = lerpDouble(0.94, 1.0, t)!;
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: 44,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.accent,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(72),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: fg, size: 22),
      ),
    );
  }
}

class _PostNavButton extends StatelessWidget {
  final bool selected;
  const _PostNavButton({required this.selected});

  @override
  Widget build(BuildContext context) {
    final iconSize = selected ? 24.0 : 22.0;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.primary,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primary.withAlpha(90),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.add_rounded,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }
}

class _GlassBottomNav extends StatelessWidget {
  final Widget child;
  const _GlassBottomNav({required this.child});

  @override
  Widget build(BuildContext context) {
    const radius = 28.0;
    const base = Color(0xFF0B1220);
    final tintA = Color.alphaBlend(AppColors.accent.withAlpha(22), base);
    final tintB = Color.alphaBlend(AppColors.secondary.withAlpha(18), base);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            // Liquid-glass feel (no white sheen): heavy blur + tinted gradient.
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Darken the blurred content behind to avoid "washed/white" look.
                      color: base.withAlpha(230),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          tintA.withAlpha(210),
                          base.withAlpha(230),
                          tintB.withAlpha(215),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(
                        color: AppColors.primary.withAlpha(28),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(95),
                          blurRadius: 32,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primary.withAlpha(20),
                            Colors.transparent,
                            AppColors.secondary.withAlpha(14),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateOption extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final VoidCallback onTap;

  const _CreateOption({
    required this.icon,
    required this.tint,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const titleColor = Color(0xFF111827);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEF2),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: titleColor,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
