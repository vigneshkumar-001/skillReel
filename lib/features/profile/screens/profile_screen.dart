import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/my_provider_photos_provider.dart';
import '../providers/my_provider_reels_provider.dart';
import '../providers/my_saved_reels_provider.dart';
import '../providers/profile_provider.dart';
import '../../../core/network/models/my_provider_photos_model.dart';
import '../../../core/network/models/my_provider_reels_model.dart';
import '../../../core/network/models/my_saved_reels_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/utils/url_utils.dart';

enum _MyProfileSection {
  about,
  photos,
  reels,
  saved,
  availability,
  experience,
  reviews,
}

const List<_MyProfileSection> _myProfileSections = <_MyProfileSection>[
  _MyProfileSection.about,
  _MyProfileSection.photos,
  _MyProfileSection.reels,
  _MyProfileSection.saved,
  _MyProfileSection.availability,
  _MyProfileSection.experience,
  _MyProfileSection.reviews,
];

const double _kMyPinnedTabsExtent = 98;

class _MyProfilePalette {
  // Same warm premium system as `user_profile_screen.dart`.
  static const bg = Color(0xFFF5EDE3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceTint = Color(0xFFFCF8F2);
  static const border = Color(0xFFEAE2D7);

  static const accent = Color(0xFFF6A23A);
  static const accentSoft = Color(0xFFFFF1DF);
  static const cardShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 30,
      offset: Offset(0, 12),
    ),
  ];
  static const softShadow = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 22,
      offset: Offset(0, 10),
    ),
  ];
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(myProfileProvider);
    return userAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CupertinoActivityIndicator(radius: 14)),
      ),
      error: (_, __) =>
          const _PremiumProfileView(user: _demoUser, isPreview: true),
      data: (user) => _PremiumProfileView(user: user as Map),
    );
  }
}

class _PremiumProfileView extends StatelessWidget {
  final Map user;
  final bool isPreview;
  const _PremiumProfileView({required this.user, this.isPreview = false});

  int _count(List<String> keys, int fallback) {
    for (final k in keys) {
      final v = user[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      final n = int.tryParse((v ?? '').toString());
      if (n != null) return n;
    }
    return fallback;
  }

  void _openMenu(BuildContext context) {
    final rootContext = context;
    final raw = user['isProvider'];
    final isProvider = raw == true ||
        raw == 1 ||
        (raw is String && raw.toLowerCase().trim() == 'true');

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.border.withAlpha(120)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 26,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                  child: Builder(
                    builder: (context) {
                      final tiles = <Widget>[
                        _MenuTile(
                          icon: Icons.bookmark_add_outlined,
                          title: 'Saved reels',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            rootContext.push('/profile/saved');
                          },
                        ),
                        _MenuTile(
                          icon: Icons.question_answer_outlined,
                          title: 'My enquiries',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            rootContext.push('/enquiries/mine');
                          },
                        ),
                        _MenuTile(
                          icon: Icons.notifications_active_outlined,
                          title: 'Notifications',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            rootContext.push('/notifications');
                          },
                        ),
                        _MenuTile(
                          icon: Icons.edit_outlined,
                          title: 'Edit profile',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            rootContext.push('/profile/edit');
                          },
                        ),
                        if (!isProvider)
                          _MenuTile(
                            icon: Icons.verified_outlined,
                            title: 'Become a Provider',
                            onTap: () {
                              Navigator.of(ctx).pop();
                              rootContext.push('/provider/become');
                            },
                          ),
                        if (isProvider)
                          _MenuTile(
                            icon: Icons.settings_outlined,
                            title: 'Become a Provider',
                            onTap: () {
                              Navigator.of(ctx).pop();
                              rootContext.push('/provider/settings');
                            },
                          ),
                        _MenuTile(
                          icon: Icons.logout_rounded,
                          title: 'Logout',
                          tint: AppColors.error,
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            await Future<void>.delayed(
                              const Duration(milliseconds: 140),
                            );
                            if (!rootContext.mounted) return;
                            HapticFeedback.selectionClick();
                            final ok = await _confirmLogout(rootContext);
                            if (!ok) return;
                            await StorageService.instance.clear();
                            if (rootContext.mounted) {
                              rootContext.go('/auth/otp');
                            }
                          },
                        ),
                      ];

                      return ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: tiles.length,
                        itemBuilder: (_, i) => tiles[i],
                        separatorBuilder: (_, i) => Divider(
                          height: 1,
                          thickness: 1,
                          indent: 60,
                          endIndent: 12,
                          color: AppColors.border.withAlpha(120),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Logout',
      barrierColor: Colors.black.withAlpha(120),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, __, ___) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border.withAlpha(160)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 34,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.error.withAlpha(18),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.error.withAlpha(70),
                          ),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: AppColors.error,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Logout?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Are you sure you want to logout from SkilReel?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                Navigator.of(ctx).pop(false);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                side: BorderSide(
                                  color: AppColors.border.withAlpha(160),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                Navigator.of(ctx).pop(true);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.error,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Logout',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = UrlUtils.normalizeMediaUrl(user['avatar']?.toString());
    final name = (user['name'] ?? 'Your Name').toString();
    final headline = (user['headline'] ?? '').toString().trim();
    final bio = (user['bio'] ?? user['about'] ?? 'Premium profile preview')
        .toString()
        .trim();

    final followers = _count(
      const ['followersCount', 'followers', 'followerCount'],
      684000,
    );
    final following = _count(
      const ['followingCount', 'following', 'followings'],
      2514,
    );
    final posts = _count(
      const ['postsCount', 'posts', 'postCount'],
      254,
    );
    final providerObj = user['provider'];
    final enquiriesRaw =
        providerObj is Map ? providerObj['enquiryCount'] : user['enquiryCount'];
    final enquiries = enquiriesRaw is int
        ? enquiriesRaw
        : (enquiriesRaw is num
            ? enquiriesRaw.round()
            : int.tryParse(enquiriesRaw?.toString() ?? '') ?? 0);

    return _PremiumProfileScaffold(
      user: user,
      isPreview: isPreview,
      avatarUrl: avatarUrl,
      name: name,
      headline: headline,
      bio: bio,
      followers: followers,
      following: following,
      posts: posts,
      likes: _count(const ['likesCount', 'likes', 'likeCount'], 234000),
      enquiries: enquiries,
      onOpenMenu: () => _openMenu(context),
    );
  }
}

class _PremiumProfileScaffold extends ConsumerStatefulWidget {
  final Map user;
  final bool isPreview;
  final String avatarUrl;
  final String name;
  final String headline;
  final String bio;
  final int followers;
  final int following;
  final int posts;
  final int likes;
  final int enquiries;
  final VoidCallback onOpenMenu;

  const _PremiumProfileScaffold({
    required this.user,
    required this.isPreview,
    required this.avatarUrl,
    required this.name,
    required this.headline,
    required this.bio,
    required this.followers,
    required this.following,
    required this.posts,
    required this.likes,
    required this.enquiries,
    required this.onOpenMenu,
  });

  @override
  ConsumerState<_PremiumProfileScaffold> createState() =>
      _PremiumProfileScaffoldState();
}

class _PremiumProfileScaffoldState
    extends ConsumerState<_PremiumProfileScaffold> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _activeSectionIndex = ValueNotifier<int>(0);
  final GlobalKey _sheetViewportKey = GlobalKey();

  final GlobalKey _aboutKey = GlobalKey();
  final GlobalKey _photosKey = GlobalKey();
  final GlobalKey _reelsKey = GlobalKey();
  final GlobalKey _savedKey = GlobalKey();
  final GlobalKey _availabilityKey = GlobalKey();
  final GlobalKey _experienceKey = GlobalKey();
  final GlobalKey _reviewsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _PremiumProfileScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _updateActiveSectionFromScroll(_scrollController.offset);
  }

  Future<void> _refresh() async {
    if (widget.isPreview) return;
    HapticFeedback.selectionClick();
    ref.invalidate(myProfileProvider);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  GlobalKey _keyForSection(_MyProfileSection section) {
    switch (section) {
      case _MyProfileSection.about:
        return _aboutKey;
      case _MyProfileSection.photos:
        return _photosKey;
      case _MyProfileSection.reels:
        return _reelsKey;
      case _MyProfileSection.saved:
        return _savedKey;
      case _MyProfileSection.availability:
        return _availabilityKey;
      case _MyProfileSection.experience:
        return _experienceKey;
      case _MyProfileSection.reviews:
        return _reviewsKey;
    }
  }

  double? _offsetForSection(_MyProfileSection section) {
    if (!_scrollController.hasClients) return null;
    final ctx = _keyForSection(section).currentContext;
    if (ctx == null) return null;
    final obj = ctx.findRenderObject();
    if (obj == null) return null;
    final viewport = RenderAbstractViewport.maybeOf(obj);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(obj, 0).offset;
  }

  void _updateActiveSectionFromScroll(double scrollOffset) {
    const pinnedHeader = _kMyPinnedTabsExtent;
    final probe = scrollOffset + pinnedHeader + 12;
    var nextIndex = 0;
    var foundAny = false;

    for (var i = 0; i < _myProfileSections.length; i++) {
      final off = _offsetForSection(_myProfileSections[i]);
      if (off == null) continue;
      foundAny = true;
      if (off <= probe) nextIndex = i;
    }

    if (!foundAny) return;
    if (_activeSectionIndex.value != nextIndex) {
      _activeSectionIndex.value = nextIndex;
    }
  }

  Future<void> _scrollToSection(_MyProfileSection section) async {
    if (!_scrollController.hasClients) return;
    // Wait one frame to ensure layout is stable.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final raw = _offsetForSection(section);
    if (raw == null) return;

    const pinnedHeader = _kMyPinnedTabsExtent;
    final target = (raw - pinnedHeader - 10).clamp(0.0, double.infinity);
    HapticFeedback.selectionClick();
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  Map<String, dynamic> _modeSummary() {
    final ms = widget.user['modeSummary'];
    if (ms is Map<String, dynamic>) return ms;
    if (ms is Map) return Map<String, dynamic>.from(ms);
    return const <String, dynamic>{};
  }

  bool _hasProviderProfile() {
    final ms = _modeSummary();
    final v = ms['hasProviderProfile'];
    if (v is bool) return v;

    final role = (ms['role'] ?? widget.user['role'] ?? '').toString();
    if (role.toLowerCase() == 'provider') return true;

    final provider = widget.user['provider'];
    return provider is Map;
  }

  // Provider mode switching intentionally removed.
  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _activeSectionIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.avatarUrl;
    final name = widget.name;
    final bio = widget.bio.trim();
    final hasProviderProfile = _hasProviderProfile();

    final handle = _handleFromUser(widget.user);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final subtitle = widget.headline.trim();
    final reviewsRaw = widget.user['reviews'];

    int readInt(List<Object?> candidates, {int fallback = 0}) {
      for (final c in candidates) {
        if (c is int) return c;
        if (c is num) return c.round();
        final n = int.tryParse((c ?? '').toString());
        if (n != null) return n;
      }
      return fallback;
    }

    String readStr(List<Object?> candidates) {
      for (final c in candidates) {
        final s = (c ?? '').toString().trim();
        if (s.isNotEmpty) return s;
      }
      return '';
    }

    final providerObj = widget.user['provider'];
    final provider = providerObj is Map
        ? Map<String, dynamic>.from(providerObj)
        : const <String, dynamic>{};

    final experienceYears = readInt([
      widget.user['experienceYears'],
      widget.user['experience'],
      provider['experienceYears'],
      provider['experience'],
      provider['yearsOfExperience'],
    ]);

    final happyClients = readInt([
      widget.user['happyClients'],
      widget.user['clients'],
      widget.user['customers'],
      provider['happyClients'],
      provider['clients'],
      provider['customerCount'],
      provider['customersCount'],
      provider['customers'],
    ]);

    final phone = readStr([
      widget.user['mobile'],
      widget.user['mobileNumber'],
      widget.user['phone'],
      widget.user['phoneNumber'],
      widget.user['contact'],
      provider['mobile'],
      provider['mobileNumber'],
      provider['phone'],
      provider['phoneNumber'],
      provider['contact'],
    ]);

    final website = readStr([
      widget.user['websiteUrl'],
      widget.user['website'],
      widget.user['url'],
      provider['websiteUrl'],
      provider['website'],
      provider['url'],
    ]);

    final availabilityText = readStr([
      widget.user['availability'],
      widget.user['availabilityText'],
      provider['availability'],
      provider['availabilityText'],
    ]);

    return Scaffold(
      backgroundColor: _MyProfilePalette.bg,
      body: RefreshIndicator.adaptive(
        onRefresh: _refresh,
        notificationPredicate: (n) => n.depth == 0,
        child: ScrollConfiguration(
          behavior: const _BouncyScrollBehavior(),
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: _MyProfileHeroSection(
                  avatarUrl: avatarUrl,
                  displayName: name,
                  subtitle: subtitle,
                  handle: handle,
                  bio: bio,
                  followers: widget.followers,
                  posts: widget.posts,
                  likes: widget.likes,
                  onBack: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).maybePop();
                  },
                  onEdit: widget.isPreview
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          context.push('/profile/edit');
                        },
                  onMenu: () {
                    HapticFeedback.selectionClick();
                    widget.onOpenMenu();
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  height: 6,
                  color: const Color(0xFFF7F7F7),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _MyStickyTabsHeaderDelegate(
                  activeIndex: _activeSectionIndex,
                  onTapSection: _scrollToSection,
                ),
              ),
              SliverToBoxAdapter(
                child: _MyProfileSheetBody(
                  sheetViewportKey: _sheetViewportKey,
                  aboutKey: _aboutKey,
                  photosKey: _photosKey,
                  reelsKey: _reelsKey,
                  savedKey: _savedKey,
                  availabilityKey: _availabilityKey,
                  experienceKey: _experienceKey,
                  reviewsKey: _reviewsKey,
                  displayName: name,
                  subtitle: subtitle,
                  avatarUrl: avatarUrl,
                  handle: handle,
                  bio: bio.isEmpty ? 'Tell people about yourself.' : bio,
                  phone: phone,
                  website: website,
                  availabilityText: availabilityText,
                  isProviderMode: hasProviderProfile,
                  reviewsRaw: reviewsRaw,
                  showDemoReviews: kDebugMode || widget.isPreview,
                  experienceYears: experienceYears,
                  happyClients: happyClients,
                  // Match `MainShell` bottom tabs (NavigationBar ~80 + outer padding 18),
                  // since `extendBody: true` lets content render behind it.
                  bottomPadding: 110 + bottomPad,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _handleFromUser(Map user) {
  final handle = (user['username'] ?? user['handle'] ?? '').toString().trim();
  if (handle.isEmpty) return '';
  return handle.startsWith('@') ? handle : '@$handle';
}

class _MyTopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _MyTopIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _MyProfilePalette.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _MyProfilePalette.softShadow,
          ),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _NetworkImageWithFallback extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final IconData icon;
  final BorderRadius borderRadius;

  const _NetworkImageWithFallback({
    required this.url,
    required this.fit,
    required this.icon,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: _MyProfilePalette.surfaceTint,
          borderRadius: borderRadius,
        ),
        child: Center(
          child: Icon(icon, color: AppColors.textSecondary, size: 40),
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (context, url) => DecoratedBox(
          decoration: BoxDecoration(
            color: _MyProfilePalette.surfaceTint,
            borderRadius: borderRadius,
          ),
        ),
        errorWidget: (context, url, error) => DecoratedBox(
          decoration: BoxDecoration(
            color: _MyProfilePalette.surfaceTint,
            borderRadius: borderRadius,
          ),
          child: Center(
            child: Icon(icon, color: AppColors.textSecondary, size: 40),
          ),
        ),
      ),
    );
  }
}

class _MyProfileHeroSection extends StatelessWidget {
  final String avatarUrl;
  final String displayName;
  final String subtitle;
  final String handle;
  final String bio;
  final int followers;
  final int posts;
  final int likes;
  final VoidCallback onBack;
  final VoidCallback? onEdit;
  final VoidCallback onMenu;

  const _MyProfileHeroSection({
    required this.avatarUrl,
    required this.displayName,
    required this.subtitle,
    required this.handle,
    required this.bio,
    required this.followers,
    required this.posts,
    required this.likes,
    required this.onBack,
    required this.onEdit,
    required this.onMenu,
  });

  String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final v = n / 1000.0;
      return v >= 10 ? '${v.toStringAsFixed(0)}k' : '${v.toStringAsFixed(1)}k';
    }
    final v = n / 1000000.0;
    return v >= 10 ? '${v.toStringAsFixed(0)}M' : '${v.toStringAsFixed(1)}M';
  }

  @override
  Widget build(BuildContext context) {
    final avatar = UrlUtils.normalizeMediaUrl(avatarUrl).trim();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF4E4),
            Color(0xFFF6D9B4),
            _MyProfilePalette.bg,
          ],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _MyTopIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: onBack,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MyTopIconButton(
                            icon: Icons.edit_outlined,
                            onTap: onEdit,
                          ),
                          const SizedBox(width: 10),
                          _MyTopIconButton(
                            icon: Icons.more_horiz_rounded,
                            onTap: onMenu,
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 116),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                color: AppColors.textPrimary,
                                height: 1.0,
                              ),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final imageWidth = (w * 0.44).clamp(120.0, 140.0).toDouble();
                  final imageHeight =
                      (imageWidth * 1.32).clamp(160.0, 180.0).toDouble();

                  return Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: imageWidth,
                            height: imageHeight,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: _MyProfilePalette.surface,
                                borderRadius: BorderRadius.circular(36),
                                boxShadow: _MyProfilePalette.softShadow,
                              ),
                              child: _NetworkImageWithFallback(
                                url: avatar,
                                fit: BoxFit.cover,
                                icon: Icons.person_rounded,
                                borderRadius: BorderRadius.circular(34),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.verified_outlined,
                                      size: 16,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        handle.isEmpty ? 'My profile' : handle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 19,
                                    color: AppColors.textPrimary,
                                    height: 1.05,
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                      height: 1.15,
                                    ),
                                  ),
                                ],
                                if (bio.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    bio.trim(),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _MyHeroStatsRow(
                        aBorder: _MyProfilePalette.accent,
                        bBorder: const Color(0xFF7C3AED),
                        cBorder: _MyProfilePalette.accent,
                        aIcon: Icons.grid_view_rounded,
                        bIcon: Icons.groups_2_rounded,
                        cIcon: Icons.favorite_rounded,
                        aValue: _compact(posts),
                        bValue: _compact(followers),
                        cValue: _compact(likes),
                        aLabel: 'Works',
                        bLabel: 'Followers',
                        cLabel: 'Likes',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyStickyTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final ValueNotifier<int> activeIndex;
  final ValueChanged<_MyProfileSection> onTapSection;

  _MyStickyTabsHeaderDelegate({
    required this.activeIndex,
    required this.onTapSection,
  });

  @override
  double get minExtent => _kMyPinnedTabsExtent;

  @override
  double get maxExtent => _kMyPinnedTabsExtent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final pinned = shrinkOffset > 0.0 || overlapsContent;
    final radius = pinned ? 0.0 : 34.0;
    final shadow = pinned
        ? const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ]
        : const <BoxShadow>[];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        boxShadow: shadow,
      ),
      child: SafeArea(
        top: pinned,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, pinned ? 0 : 10, 16, pinned ? 8 : 9),
          child: Column(
            mainAxisAlignment:
                pinned ? MainAxisAlignment.center : MainAxisAlignment.end,
            children: [
              if (!pinned) ...[
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _MyProfilePalette.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              _MyProfileTabsBar(
                activeIndex: activeIndex,
                onTapSection: onTapSection,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

class _MyProfileTabsBar extends StatefulWidget {
  final ValueNotifier<int> activeIndex;
  final ValueChanged<_MyProfileSection> onTapSection;

  const _MyProfileTabsBar({
    required this.activeIndex,
    required this.onTapSection,
  });

  @override
  State<_MyProfileTabsBar> createState() => _MyProfileTabsBarState();
}

class _MyProfileTabsBarState extends State<_MyProfileTabsBar> {
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _pillKeys =
      List<GlobalKey>.generate(_tabs.length, (_) => GlobalKey());
  final GlobalKey _viewportKey = GlobalKey();
  int? _lastEnsuredIndex;

  static const List<(String, _MyProfileSection)> _tabs =
      <(String, _MyProfileSection)>[
    ('About', _MyProfileSection.about),
    ('Photos', _MyProfileSection.photos),
    ('Reels', _MyProfileSection.reels),
    ('Saved reels', _MyProfileSection.saved),
    ('Availability', _MyProfileSection.availability),
    ('Experience', _MyProfileSection.experience),
    ('Reviews', _MyProfileSection.reviews),
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureActiveVisible(int index) {
    if (!mounted) return;
    if (index < 0 || index >= _pillKeys.length) return;
    if (!_scrollController.hasClients) return;

    final viewportCtx = _viewportKey.currentContext;
    final pillCtx = _pillKeys[index].currentContext;
    if (viewportCtx == null || pillCtx == null) return;

    final viewportObj = viewportCtx.findRenderObject();
    final pillObj = pillCtx.findRenderObject();
    if (viewportObj is! RenderBox || pillObj is! RenderBox) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final viewportWidth = viewportObj.size.width;
      final pillOffset =
          pillObj.localToGlobal(Offset.zero, ancestor: viewportObj);
      final left = pillOffset.dx;
      final right = left + pillObj.size.width;

      const pad = 14.0;
      var target = _scrollController.offset;
      if (left < pad) {
        target += left - pad;
      } else if (right > viewportWidth - pad) {
        target += (right - (viewportWidth - pad));
      } else {
        return;
      }

      final min = _scrollController.position.minScrollExtent;
      final max = _scrollController.position.maxScrollExtent;
      target = target.clamp(min, max);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.activeIndex,
      builder: (context, active, _) {
        if (_lastEnsuredIndex != active) {
          _lastEnsuredIndex = active;
          _ensureActiveVisible(active);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFFEFEFEF),
              borderRadius: BorderRadius.circular(22),
            ),
            child: SingleChildScrollView(
              key: _viewportKey,
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.hardEdge,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 26, 0),
                child: Row(
                  children: [
                    for (int i = 0; i < _tabs.length; i++) ...[
                      KeyedSubtree(
                        key: _pillKeys[i],
                        child: _MySheetTabPill(
                          label: _tabs[i].$1,
                          selected: i == active,
                          horizontalPadding: (i == 1 || i == 2) ? 10 : 12,
                          onTap: () {
                            widget.activeIndex.value = i;
                            widget.onTapSection(_tabs[i].$2);
                          },
                        ),
                      ),
                      if (i != _tabs.length - 1)
                        SizedBox(
                          width: (i == 1) ? 2 : 6, // Photos â†” Reels
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MySheetTabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final double horizontalPadding;
  final VoidCallback onTap;

  const _MySheetTabPill({
    required this.label,
    required this.selected,
    this.horizontalPadding = 12,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _MyProfilePalette.surface : Colors.transparent;
    final fg = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding:
              EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _MyProfileSheetBody extends StatelessWidget {
  final GlobalKey sheetViewportKey;
  final GlobalKey aboutKey;
  final GlobalKey photosKey;
  final GlobalKey reelsKey;
  final GlobalKey savedKey;
  final GlobalKey availabilityKey;
  final GlobalKey experienceKey;
  final GlobalKey reviewsKey;
  final String displayName;
  final String subtitle;
  final String avatarUrl;
  final String handle;
  final String bio;
  final String phone;
  final String website;
  final String availabilityText;
  final bool isProviderMode;
  final Object? reviewsRaw;
  final bool showDemoReviews;
  final int experienceYears;
  final int happyClients;
  final double bottomPadding;

  const _MyProfileSheetBody({
    required this.sheetViewportKey,
    required this.aboutKey,
    required this.photosKey,
    required this.reelsKey,
    required this.savedKey,
    required this.availabilityKey,
    required this.experienceKey,
    required this.reviewsKey,
    required this.displayName,
    required this.subtitle,
    required this.avatarUrl,
    required this.handle,
    required this.bio,
    required this.phone,
    required this.website,
    required this.availabilityText,
    required this.isProviderMode,
    required this.reviewsRaw,
    required this.showDemoReviews,
    required this.experienceYears,
    required this.happyClients,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: sheetViewportKey,
      color: const Color(0xFFF7F7F7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(
              key: aboutKey,
              child: _MyAboutSection(
                displayName: displayName,
                subtitle: subtitle,
                avatarUrl: avatarUrl,
                handle: handle,
                bio: bio,
                phone: phone,
                website: website,
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: photosKey,
              child: _MyPhotosSection(isProviderMode: isProviderMode),
            ),
            const SizedBox(height: 6),
            KeyedSubtree(
              key: reelsKey,
              child: _MyReelsSection(isProviderMode: isProviderMode),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: savedKey,
              child: const _MySavedReelsSection(),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: availabilityKey,
              child: _MyAvailabilitySection(availabilityText: availabilityText),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: experienceKey,
              child: _MyExperienceSection(
                experienceYears: experienceYears,
                happyClients: happyClients,
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: reviewsKey,
              child: _MyReviewsSection(
                reviewsRaw: reviewsRaw,
                showDemoIfEmpty: showDemoReviews,
              ),
            ),
            SizedBox(height: bottomPadding),
          ],
        ),
      ),
    );
  }
}

class _MySectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _MySectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _MyPremiumCard extends StatelessWidget {
  final Widget child;
  const _MyPremiumCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _MyProfilePalette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _MyProfilePalette.border),
        boxShadow: _MyProfilePalette.cardShadow,
      ),
      child: child,
    );
  }
}

class _MyHeroStatsRow extends StatelessWidget {
  final Color aBorder;
  final Color bBorder;
  final Color cBorder;
  final IconData aIcon;
  final IconData bIcon;
  final IconData cIcon;
  final String aValue;
  final String bValue;
  final String cValue;
  final String aLabel;
  final String bLabel;
  final String cLabel;

  const _MyHeroStatsRow({
    required this.aBorder,
    required this.bBorder,
    required this.cBorder,
    required this.aIcon,
    required this.bIcon,
    required this.cIcon,
    required this.aValue,
    required this.bValue,
    required this.cValue,
    required this.aLabel,
    required this.bLabel,
    required this.cLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MyFloatingStatCard(
            borderColor: aBorder,
            icon: aIcon,
            value: aValue,
            label: aLabel,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MyFloatingStatCard(
            borderColor: bBorder,
            icon: bIcon,
            value: bValue,
            label: bLabel,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MyFloatingStatCard(
            borderColor: cBorder,
            icon: cIcon,
            value: cValue,
            label: cLabel,
          ),
        ),
      ],
    );
  }
}

class _MyFloatingStatCard extends StatelessWidget {
  final Color borderColor;
  final IconData icon;
  final String value;
  final String label;
  const _MyFloatingStatCard({
    required this.borderColor,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: _MyProfilePalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor.withAlpha(180), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: borderColor.withAlpha(26),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: borderColor, size: 16),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: AppColors.textPrimary,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyAboutSection extends StatelessWidget {
  final String displayName;
  final String subtitle;
  final String avatarUrl;
  final String handle;
  final String bio;
  final String phone;
  final String website;

  const _MyAboutSection({
    required this.displayName,
    required this.subtitle,
    required this.avatarUrl,
    required this.handle,
    required this.bio,
    required this.phone,
    required this.website,
  });

  @override
  Widget build(BuildContext context) {
    final phoneTrim = phone.trim();
    final websiteTrim = website.trim();

    String displayWebsite(String raw) {
      var s = raw.trim();
      if (s.startsWith('http://')) s = s.substring(7);
      if (s.startsWith('https://')) s = s.substring(8);
      if (s.endsWith('/')) s = s.substring(0, s.length - 1);
      return s;
    }

    String websiteForCopy(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return '';
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      return 'https://$s';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MySectionHeader(title: 'About'),
        const SizedBox(height: 8),
        _MyPremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bio.trim(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              if (phoneTrim.isNotEmpty || websiteTrim.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(height: 1, color: _MyProfilePalette.border),
                const SizedBox(height: 12),
                const Text(
                  'Contact',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: _MyProfilePalette.surfaceTint,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _MyProfilePalette.border),
                  ),
                  child: Column(
                    children: [
                      if (phoneTrim.isNotEmpty)
                        _MyAboutInfoRow(
                          icon: Icons.call_rounded,
                          label: 'Mobile',
                          value: phoneTrim,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await Clipboard.setData(
                              ClipboardData(text: phoneTrim),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Mobile number copied'),
                              ),
                            );
                          },
                        ),
                      if (phoneTrim.isNotEmpty && websiteTrim.isNotEmpty)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          indent: 14,
                          endIndent: 14,
                          color: _MyProfilePalette.border,
                        ),
                      if (websiteTrim.isNotEmpty)
                        _MyAboutInfoRow(
                          icon: Icons.link_rounded,
                          label: 'Website',
                          value: displayWebsite(websiteTrim),
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            final value = websiteForCopy(websiteTrim);
                            await Clipboard.setData(
                              ClipboardData(text: value),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Website copied'),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MyAboutInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _MyAboutInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: _MyProfilePalette.surface,
                  border: Border.all(color: _MyProfilePalette.border),
                ),
                child: Icon(icon, size: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary.withAlpha(220),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.copy_rounded,
                size: 18,
                color: AppColors.textSecondary.withAlpha(190),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyPhotosSection extends ConsumerWidget {
  final bool isProviderMode;
  const _MyPhotosSection({required this.isProviderMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isProviderMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _MySectionHeader(title: 'Photos'),
          SizedBox(height: 10),
          _MyPremiumCard(
            child: Row(
              children: [
                Icon(Icons.workspace_premium_outlined,
                    color: AppColors.textSecondary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Create your provider profile to upload photos.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final async = ref.watch(
        myProviderPhotosProvider(const MyProviderPhotosQuery(limit: 12)));

    return async.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _MySectionHeader(title: 'Photos'),
          SizedBox(height: 6),
          Center(child: CupertinoActivityIndicator(radius: 14)),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MySectionHeader(title: 'Photos'),
          const SizedBox(height: 6),
          _MyPremiumCard(
            child: Text(
              apiErrorMessage(e),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      data: (res) {
        final items = res.data;
        final shown =
            items.length > 4 ? items.take(4).toList(growable: false) : items;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MySectionHeader(
              title: 'Photos',
              trailing: items.isEmpty
                  ? null
                  : Text(
                      '(${items.length})',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            if (items.isEmpty)
              const _MyPremiumCard(
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, color: AppColors.textSecondary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No photos yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: shown.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.04,
                ),
                itemBuilder: (context, i) => _ProviderPhotoTile(item: shown[i]),
              ),
          ],
        );
      },
    );
  }
}

class _MyReelsSection extends ConsumerWidget {
  final bool isProviderMode;
  const _MyReelsSection({required this.isProviderMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isProviderMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _MySectionHeader(title: 'Reels'),
          SizedBox(height: 10),
          _MyPremiumCard(
            child: Row(
              children: [
                Icon(Icons.workspace_premium_outlined,
                    color: AppColors.textSecondary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Create your provider profile to upload reels.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final async = ref
        .watch(myProviderReelsProvider(const MyProviderReelsQuery(limit: 12)));

    return async.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _MySectionHeader(title: 'Reels'),
          SizedBox(height: 6),
          Center(child: CupertinoActivityIndicator(radius: 14)),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MySectionHeader(title: 'Reels'),
          const SizedBox(height: 6),
          _MyPremiumCard(
            child: Text(
              apiErrorMessage(e),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      data: (res) {
        final items = res.data;
        final shown =
            items.length > 4 ? items.take(4).toList(growable: false) : items;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MySectionHeader(
              title: 'Reels',
              trailing: items.isEmpty
                  ? null
                  : Text(
                      '(${items.length})',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            if (items.isEmpty)
              const _MyPremiumCard(
                child: Row(
                  children: [
                    Icon(Icons.video_library_outlined,
                        color: AppColors.textSecondary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No reels yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 148,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => SizedBox(
                    width: 116,
                    height: 148,
                    child: _ProviderReelTile(item: shown[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MySavedReelsSection extends ConsumerWidget {
  const _MySavedReelsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async =
        ref.watch(mySavedReelsProvider(const MySavedReelsQuery(limit: 12)));

    return async.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _MySectionHeader(title: 'Saved reels'),
          SizedBox(height: 6),
          Center(child: CupertinoActivityIndicator(radius: 14)),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MySectionHeader(title: 'Saved reels'),
          const SizedBox(height: 6),
          _MyPremiumCard(
            child: Text(
              apiErrorMessage(e),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      data: (res) {
        final items = res.data;
        final shown =
            items.length > 4 ? items.take(4).toList(growable: false) : items;
        final showViewAll = items.length > shown.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MySectionHeader(
              title: 'Saved reels',
              trailing: showViewAll
                  ? _MyViewAllButton(
                      onTap: () => context.push('/profile/saved'),
                    )
                  : (items.isEmpty
                      ? null
                      : Text(
                          '(${items.length})',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        )),
            ),
            const SizedBox(height: 6),
            if (items.isEmpty)
              const _MyPremiumCard(
                child: Row(
                  children: [
                    Icon(Icons.bookmark_border_rounded,
                        color: AppColors.textSecondary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Nothing saved yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 148,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => SizedBox(
                    width: 116,
                    height: 148,
                    child: _SavedReelTile(item: shown[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MyAvailabilitySection extends StatelessWidget {
  final String availabilityText;
  const _MyAvailabilitySection({required this.availabilityText});

  String _nextAvailableText() {
    final now = DateTime.now();
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    if (isWeekend) return 'Next available on Monday at 10:00 AM';

    final next4pm = DateTime(now.year, now.month, now.day, 16);
    if (now.isBefore(next4pm)) return 'Next available today at 4:00 PM';
    return 'Next available tomorrow at 10:00 AM';
  }

  @override
  Widget build(BuildContext context) {
    final override = availabilityText.trim();
    final now = DateTime.now();
    final days = List<DateTime>.generate(
      7,
      (i) => DateTime(now.year, now.month, now.day).add(Duration(days: i)),
      growable: false,
    );

    String dow(DateTime d) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[(d.weekday - 1).clamp(0, 6)];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MySectionHeader(title: 'Availability'),
        const SizedBox(height: 8),
        _MyPremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _MyProfilePalette.accentSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      color: _MyProfilePalette.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      override.isNotEmpty ? override : _nextAvailableText(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: days.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final d = days[i];
                    final isToday = i == 0;
                    final bg = isToday
                        ? _MyProfilePalette.accentSoft
                        : _MyProfilePalette.surfaceTint;
                    final border = isToday
                        ? _MyProfilePalette.accent.withAlpha(160)
                        : _MyProfilePalette.border;
                    return Container(
                      width: 62,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dow(d),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${d.day}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MyExperienceSection extends StatelessWidget {
  final int experienceYears;
  final int happyClients;

  const _MyExperienceSection({
    required this.experienceYears,
    required this.happyClients,
  });

  @override
  Widget build(BuildContext context) {
    final yearsText = (experienceYears > 0) ? '$experienceYears' : '8';
    final clientsText = (happyClients > 0)
        ? (happyClients >= 100 ? '$happyClients+' : '$happyClients')
        : '150+';

    Widget tile({
      required IconData icon,
      required String value,
      required String label,
      required Color tint,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _MyProfilePalette.surfaceTint,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _MyProfilePalette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tint.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tint, size: 18),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MySectionHeader(title: 'Experience'),
        const SizedBox(height: 8),
        _MyPremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Years of experience & happy clients',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  tile(
                    icon: Icons.work_outline_rounded,
                    value: '$yearsText yrs',
                    label: 'Experience',
                    tint: _MyProfilePalette.accent,
                  ),
                  const SizedBox(width: 12),
                  tile(
                    icon: Icons.emoji_emotions_outlined,
                    value: clientsText,
                    label: 'Happy clients',
                    tint: const Color(0xFF7C3AED),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

typedef _MyReviewRow = ({
  String name,
  String dateLabel,
  String avatarUrl,
  String text,
  double rating,
});

class _MyReviewsSection extends StatelessWidget {
  final Object? reviewsRaw;
  final bool showDemoIfEmpty;

  const _MyReviewsSection({
    required this.reviewsRaw,
    required this.showDemoIfEmpty,
  });

  static const List<_MyReviewRow> _demo = <_MyReviewRow>[
    (
      name: 'Michael Brown',
      dateLabel: 'May 18, 2024',
      avatarUrl: '',
      text:
          'James did an amazing job with the wiring in my new home. Very professional and on time!',
      rating: 5.0,
    ),
    (
      name: 'Sarah Lee',
      dateLabel: 'Apr 03, 2024',
      avatarUrl: '',
      text:
          'Quick response and great quality work. Explained everything clearly and finished fast.',
      rating: 4.5,
    ),
    (
      name: 'Arjun Kumar',
      dateLabel: 'Mar 11, 2024',
      avatarUrl: '',
      text: 'Good service and friendly. Will book again.',
      rating: 4.0,
    ),
  ];

  List<_MyReviewRow> _parseReviews(Object? raw) {
    if (raw is! List) return const <_MyReviewRow>[];
    final out = <_MyReviewRow>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final name = (e['name'] ?? e['userName'] ?? e['author'] ?? 'User')
          .toString()
          .trim();
      final dateLabel = (e['date'] ?? e['createdAt'] ?? e['created_at'] ?? '')
          .toString()
          .trim();
      final avatarUrl = UrlUtils.normalizeMediaUrl(
        (e['avatarUrl'] ?? e['avatar'] ?? e['userAvatar'] ?? '').toString(),
      ).trim();
      final text =
          (e['text'] ?? e['message'] ?? e['review'] ?? e['comment'] ?? '')
              .toString()
              .trim();
      final r = e['rating'] ?? e['stars'] ?? e['value'];
      final rating = (r is num) ? r.toDouble() : double.tryParse('$r') ?? 0.0;
      if (text.isEmpty && rating <= 0) continue;
      out.add((
        name: name.isEmpty ? 'User' : name,
        dateLabel: dateLabel,
        avatarUrl: avatarUrl,
        text: text,
        rating: rating,
      ));
    }
    return out;
  }

  Widget _stars(double rating) {
    final r = rating.clamp(0.0, 5.0);
    final full = r.floor();
    final half = (r - full) >= 0.5 ? 1 : 0;
    const empty = 5;
    final icons = <IconData>[];
    for (var i = 0; i < full; i++) {
      icons.add(Icons.star_rounded);
    }
    if (half == 1) icons.add(Icons.star_half_rounded);
    while (icons.length < empty) {
      icons.add(Icons.star_border_rounded);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: icons
          .map(
            (ic) => Icon(
              ic,
              size: 16,
              color: _MyProfilePalette.accent,
            ),
          )
          .toList(growable: false),
    );
  }

  Map<int, int> _distribution(List<_MyReviewRow> reviews) {
    final out = <int, int>{};
    for (var i = 1; i <= 5; i++) {
      out[i] = 0;
    }
    for (final r in reviews) {
      final v = r.rating.round().clamp(1, 5);
      out[v] = (out[v] ?? 0) + 1;
    }
    return out;
  }

  Widget _histRow({
    required int stars,
    required double pct,
  }) {
    final percent = (pct * 100).round().clamp(0, 100);
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '$stars',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.star_rounded,
            size: 14, color: _MyProfilePalette.accent),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: _MyProfilePalette.border.withAlpha(140),
                    ),
                  ),
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: pct.clamp(0.0, 1.0),
                      child: const ColoredBox(color: _MyProfilePalette.accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text(
            '$percent%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parseReviews(reviewsRaw);
    final reviews = (parsed.isEmpty && showDemoIfEmpty) ? _demo : parsed;
    final avg = reviews.isEmpty
        ? 0.0
        : reviews.map((e) => e.rating).fold<double>(0, (a, b) => a + b) /
            reviews.length;
    final shown = reviews.take(1).toList(growable: false);
    final dist = _distribution(reviews);

    void openAll() {
      HapticFeedback.selectionClick();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _MyReviewsListPage(reviews: reviews),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MySectionHeader(
          title: 'Reviews',
          trailing: reviews.length > 1
              ? _MyViewAllButton(onTap: openAll)
              : (reviews.isEmpty
                  ? null
                  : Text(
                      '(${reviews.length})',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    )),
        ),
        const SizedBox(height: 8),
        if (reviews.isEmpty)
          const _MyPremiumCard(
            child: Row(
              children: [
                Icon(Icons.rate_review_outlined,
                    color: AppColors.textSecondary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No reviews yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          _MyPremiumCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        avg.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          fontSize: 34,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _stars(avg),
                      const SizedBox(height: 8),
                      Text(
                        '(${reviews.length} reviews)',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      for (var s = 5; s >= 1; s--) ...[
                        _histRow(
                          stars: s,
                          pct: reviews.isEmpty
                              ? 0.0
                              : (dist[s] ?? 0) / reviews.length,
                        ),
                        if (s != 1) const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final r in shown) ...[
            _MyPremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: _NetworkImageWithFallback(
                          url: r.avatarUrl,
                          fit: BoxFit.cover,
                          icon: Icons.person_rounded,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (r.dateLabel.trim().isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  Text(
                                    r.dateLabel.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      height: 1.0,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            _stars(r.rating),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    r.text.isEmpty ? 'Great experience.' : r.text,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _MyReviewsListPage extends StatelessWidget {
  final List<_MyReviewRow> reviews;
  const _MyReviewsListPage({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        elevation: 0,
        title: const Text(
          'Reviews',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: reviews.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final r = reviews[i];
          return _MyPremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: _NetworkImageWithFallback(
                        url: r.avatarUrl,
                        fit: BoxFit.cover,
                        icon: Icons.person_rounded,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (r.dateLabel.trim().isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        r.dateLabel.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  r.text.isEmpty ? 'Great experience.' : r.text,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MyViewAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MyViewAllButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(999),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'View All',
            style: TextStyle(
              color: _MyProfilePalette.accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderPhotoTile extends StatelessWidget {
  final MyProviderPhotoItem item;
  const _ProviderPhotoTile({required this.item});

  String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final v = n / 1000.0;
      final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
      return '${s}k';
    }
    final v = n / 1000000.0;
    final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${s}M';
  }

  @override
  Widget build(BuildContext context) {
    final thumb = (item.coverUrl ?? item.mediaUrl ?? item.playbackUrl ?? '')
        .toString()
        .trim();
    final url = UrlUtils.normalizeMediaUrl(thumb);
    final heroTag = 'photo_thumb_${item.id}';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          context.push('/photos/my', extra: item.id);
        },
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withAlpha(26),
                        AppColors.accent.withAlpha(18),
                        const Color(0xFF0B1220).withAlpha(16),
                      ],
                    ),
                  ),
                  child: url.trim().isEmpty
                      ? const Center(
                          child: Icon(
                            Icons.image_not_supported_rounded,
                            color: Colors.black38,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 120),
                          placeholder: (context, url) =>
                              const SizedBox.shrink(),
                          errorWidget: (context, url, error) => const Center(
                            child: Icon(
                              Icons.broken_image_rounded,
                              color: Colors.black38,
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title.trim().isEmpty
                                ? 'Untitled'
                                : item.title.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.remove_red_eye_outlined,
                          size: 14,
                          color: Colors.white.withAlpha(220),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _compact(item.viewCount),
                          style: TextStyle(
                            color: Colors.white.withAlpha(235),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
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

class _SavedReelTile extends StatelessWidget {
  final MySavedReelItem item;
  const _SavedReelTile({required this.item});

  bool _looksLikeVideoUrl(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') ||
        u.endsWith('.mov') ||
        u.endsWith('.m3u8') ||
        u.contains('.mp4?') ||
        u.contains('.mov?') ||
        u.contains('.m3u8?');
  }

  String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final v = n / 1000.0;
      final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
      return '${s}k';
    }
    final v = n / 1000000.0;
    final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${s}M';
  }

  @override
  Widget build(BuildContext context) {
    final thumb = (item.coverUrl ?? item.playbackUrl ?? item.mediaUrl ?? '')
        .toString()
        .trim();
    final showPlaceholder = thumb.isEmpty || _looksLikeVideoUrl(thumb);
    final heroTag = 'saved_reel_thumb_${item.id}';
    final thumbUrl = UrlUtils.normalizeMediaUrl(thumb);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          context.push(
            '/reels/saved',
            extra: <String, dynamic>{
              'id': item.id,
              'heroTag': heroTag,
              'thumbUrl': thumbUrl,
            },
          );
        },
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Hero(
                        tag: heroTag,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primary.withAlpha(18),
                                AppColors.accent.withAlpha(16),
                                const Color(0xFF0B1220).withAlpha(26),
                              ],
                            ),
                          ),
                          child: showPlaceholder
                              ? const Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white70,
                                    size: 42,
                                  ),
                                )
                              : CachedNetworkImage(
                                  imageUrl: thumbUrl,
                                  fit: BoxFit.cover,
                                  fadeInDuration:
                                      const Duration(milliseconds: 120),
                                  placeholder: (context, url) =>
                                      const SizedBox.shrink(),
                                  errorWidget: (context, url, error) =>
                                      const Center(
                                    child: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: Colors.white70,
                                      size: 42,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(150),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withAlpha(30)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.remove_red_eye_outlined,
                              size: 14,
                              color: Colors.white.withAlpha(220),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _compact(item.viewCount),
                              style: TextStyle(
                                color: Colors.white.withAlpha(235),
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(150),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withAlpha(30)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFFF4D67),
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _compact(item.likeCount),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title.trim().isEmpty ? 'Untitled' : item.title.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderReelTile extends StatelessWidget {
  final MyProviderReelItem item;
  const _ProviderReelTile({required this.item});

  bool _looksLikeVideoUrl(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') ||
        u.endsWith('.mov') ||
        u.endsWith('.m3u8') ||
        u.contains('.mp4?') ||
        u.contains('.mov?') ||
        u.contains('.m3u8?');
  }

  String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final v = n / 1000.0;
      final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
      return '${s}k';
    }
    final v = n / 1000000.0;
    final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${s}M';
  }

  @override
  Widget build(BuildContext context) {
    final thumb = (item.coverUrl ?? item.playbackUrl ?? item.mediaUrl ?? '')
        .toString()
        .trim();
    final showPlaceholder = thumb.isEmpty || _looksLikeVideoUrl(thumb);
    final heroTag = 'reel_thumb_${item.id}';
    final thumbUrl = UrlUtils.normalizeMediaUrl(thumb);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          context.push(
            '/reels/my',
            extra: <String, dynamic>{
              'id': item.id,
              'heroTag': heroTag,
              'thumbUrl': thumbUrl,
            },
          );
        },
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Hero(
                        tag: heroTag,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.accent.withAlpha(26),
                                AppColors.secondary.withAlpha(18),
                                const Color(0xFF0B1220).withAlpha(22),
                              ],
                            ),
                          ),
                          child: showPlaceholder
                              ? const Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white70,
                                    size: 42,
                                  ),
                                )
                              : CachedNetworkImage(
                                  imageUrl: thumbUrl,
                                  fit: BoxFit.cover,
                                  fadeInDuration:
                                      const Duration(milliseconds: 120),
                                  placeholder: (context, url) =>
                                      const SizedBox.shrink(),
                                  errorWidget: (context, url, error) =>
                                      const Center(
                                    child: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: Colors.white70,
                                      size: 42,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(150),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withAlpha(30),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.remove_red_eye_outlined,
                              size: 14,
                              color: Colors.white.withAlpha(220),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _compact(item.viewCount),
                              style: TextStyle(
                                color: Colors.white.withAlpha(235),
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(150),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withAlpha(30),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFFF4D67),
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _compact(item.likeCount),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title.trim().isEmpty ? 'Untitled' : item.title.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BouncyScrollBehavior extends MaterialScrollBehavior {
  const _BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color tint;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    this.tint = AppColors.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withAlpha(18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _demoUser = <String, dynamic>{
  'name': 'Your Name',
  'bio': 'Your premium profile preview will look like this.',
  'followersCount': 684000,
  'followingCount': 2514,
  'postsCount': 254,
};
