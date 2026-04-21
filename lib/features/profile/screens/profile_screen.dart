import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
                            context.push('/profile/saved');
                          },
                        ),
                        _MenuTile(
                          icon: Icons.question_answer_outlined,
                          title: 'My enquiries',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            context.push('/enquiries/mine');
                          },
                        ),
                        _MenuTile(
                          icon: Icons.notifications_active_outlined,
                          title: 'Notifications',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            context.push('/notifications');
                          },
                        ),
                        _MenuTile(
                          icon: Icons.edit_outlined,
                          title: 'Edit profile',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            context.push('/profile/edit');
                          },
                        ),
                        if (!isProvider)
                          _MenuTile(
                            icon: Icons.verified_outlined,
                            title: 'Become a Provider',
                            onTap: () {
                              Navigator.of(ctx).pop();
                              context.push('/provider/become');
                            },
                          ),
                        if (isProvider)
                          _MenuTile(
                            icon: Icons.settings_outlined,
                            title: 'Provider settings',
                            onTap: () {
                              Navigator.of(ctx).pop();
                              context.push('/provider/settings');
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
                            if (!context.mounted) return;
                            HapticFeedback.selectionClick();
                            final ok = await _confirmLogout(context);
                            if (!ok) return;
                            await StorageService.instance.clear();
                            if (context.mounted) context.go('/auth/otp');
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
    required this.onOpenMenu,
  });

  @override
  ConsumerState<_PremiumProfileScaffold> createState() =>
      _PremiumProfileScaffoldState();
}

class _PremiumProfileScaffoldState
    extends ConsumerState<_PremiumProfileScaffold> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _titleProgress = ValueNotifier<double>(0);

  static const double _titleThreshold = 86;
  String _mode = 'user';
  bool _switchingMode = false;

  @override
  void initState() {
    super.initState();
    _mode = (widget.user['mode'] ?? 'user').toString();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _PremiumProfileScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = (widget.user['mode'] ?? 'user').toString();
    if (next != _mode) _mode = next;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final next = (_scrollController.offset / _titleThreshold).clamp(0.0, 1.0);
    _titleProgress.value = next;
  }

  Map<String, dynamic> _modeSummary() {
    final ms = widget.user['modeSummary'];
    if (ms is Map<String, dynamic>) return ms;
    if (ms is Map) return Map<String, dynamic>.from(ms);
    return const <String, dynamic>{};
  }

  int _tabCount(String key) {
    final raw = widget.user['tabs'];
    if (raw is! List) return 0;
    for (final e in raw) {
      if (e is! Map) continue;
      final k = (e['key'] ?? '').toString();
      if (k == key) {
        final c = e['count'];
        if (c is int) return c;
        if (c is num) return c.round();
        return int.tryParse(c?.toString() ?? '') ?? 0;
      }
    }
    return 0;
  }

  String _tabLabel(String label, int count) {
    if (count <= 0) return label;
    return '$label ($count)';
  }

  Future<bool> _confirmSwitchMode({
    required BuildContext context,
    required String toMode,
  }) async {
    final toProvider = toMode == 'provider';

    return (await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 26,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: toProvider
                                  ? const [
                                      AppColors.accent,
                                      AppColors.secondary
                                    ]
                                  : const [
                                      Color(0xFF111827),
                                      Color(0xFF0B1220),
                                    ],
                            ),
                          ),
                          child: Icon(
                            toProvider
                                ? Icons.verified_rounded
                                : Icons.person_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            toProvider
                                ? 'Switch to Provider mode'
                                : 'Switch to User mode',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.textSecondary,
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      toProvider
                          ? 'Provider mode is required to upload reels and photos.'
                          : 'User mode is for browsing and enquiries.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.border),
                              minimumSize: const Size.fromHeight(48),
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
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor: toProvider
                                  ? AppColors.accent
                                  : const Color(0xFF111827),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text(
                              'Switch',
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
        )) ??
        false;
  }

  Future<void> _toggleMode(BuildContext context, bool value) async {
    final target = value ? 'provider' : 'user';
    if (_switchingMode) return;
    if (target == _mode) return;

    final messenger = ScaffoldMessenger.of(context);
    final ms = _modeSummary();
    final canSwitchToProvider = (ms['canSwitchToProvider'] ?? false) == true;
    final switchReason = (ms['switchToProviderReason'] ?? '').toString().trim();

    if (target == 'provider' && !canSwitchToProvider) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            switchReason.isNotEmpty
                ? switchReason
                : 'Cannot switch to provider mode.',
          ),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final ok = await _confirmSwitchMode(context: context, toMode: target);
    if (!mounted || !ok) return;

    final prev = _mode;
    setState(() {
      _switchingMode = true;
      _mode = target;
    });

    try {
      await ref.read(appRepoProvider).switchMode(target);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _mode = prev);
      messenger.showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _switchingMode = false);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _titleProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.avatarUrl;
    final name = widget.name;
    final bio = widget.bio.trim();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _ProfilePalette.bg,
        body: ScrollConfiguration(
          behavior: const _BouncyScrollBehavior(),
          child: NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                pinned: true,
                expandedHeight: kToolbarHeight,
                clipBehavior: Clip.none,
                backgroundColor: _ProfilePalette.bg,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                centerTitle: false,
                automaticallyImplyLeading: true,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: IconButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).maybePop();
                    },
                    icon: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _ProfilePalette.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _ProfilePalette.border.withAlpha(140),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    tooltip: 'Back',
                  ),
                ),
                titleSpacing: 0,
                title: ValueListenableBuilder<double>(
                  valueListenable: _titleProgress,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  builder: (context, progress, child) {
                    final t = Curves.easeOut.transform(
                      ((progress - 0.35) / 0.65).clamp(0.0, 1.0),
                    );
                    return IgnorePointer(
                      ignoring: t < 0.05,
                      child: Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset((1 - t) * 10, (1 - t) * 12),
                          child: Transform.scale(
                            scale: 0.96 + (0.04 * t),
                            alignment: Alignment.centerLeft,
                            child: child,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _titleProgress,
                    builder: (context, progress, _) {
                      final t = Curves.easeOut
                          .transform((progress / 0.35).clamp(0, 1));
                      return Opacity(
                        opacity: t,
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: _ProfilePalette.border.withAlpha(120),
                        ),
                      );
                    },
                  ),
                ),
                actions: [
                  ValueListenableBuilder<double>(
                    valueListenable: _titleProgress,
                    builder: (context, progress, _) {
                      final t = Curves.easeOut.transform(
                        ((progress - 0.35) / 0.65).clamp(0.0, 1.0),
                      );
                      return IgnorePointer(
                        ignoring: t < 0.05,
                        child: Opacity(
                          opacity: t,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: IconButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                widget.onOpenMenu();
                              },
                              icon: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _ProfilePalette.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color:
                                        _ProfilePalette.border.withAlpha(140),
                                  ),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.more_horiz_rounded,
                                    size: 20,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              tooltip: 'Menu',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _titleProgress,
                    builder: (context, progress, _) {
                      return _HeaderCard(
                        avatarUrl: avatarUrl,
                        name: name,
                        headline: widget.headline,
                        handle: _handleFromUser(widget.user),
                        bio: bio.isEmpty ? 'Premium profile preview' : bio,
                        followers: widget.followers,
                        following: widget.following,
                        posts: widget.posts,
                        likes: widget.likes,
                        isPreview: widget.isPreview,
                        onEditTap: widget.isPreview
                            ? () {}
                            : () => context.push('/profile/edit'),
                        onMenuTap: widget.onOpenMenu,
                        titleProgress: progress,
                      );
                    },
                  ),
                ),
              ),
              if (!widget.isPreview)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _ProfilePalette.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _ProfilePalette.border),
                        boxShadow: [
                          BoxShadow(
                            color: _ProfilePalette.accent.withAlpha(10),
                            blurRadius: 22,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.accent,
                                    AppColors.secondary,
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.swap_horiz_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Provider mode',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _mode == 'provider'
                                        ? 'You can upload reels and posts'
                                        : 'Switch on to upload reels and posts',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IgnorePointer(
                              ignoring: _switchingMode,
                              child: Opacity(
                                opacity: _switchingMode ? 0.6 : 1,
                                child: Switch.adaptive(
                                  value: _mode == 'provider',
                                  onChanged: (v) => _toggleMode(context, v),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabHeaderDelegate(
                  TabBar(
                    indicatorColor: _ProfilePalette.accent,
                    dividerColor: Colors.transparent,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.photo_library_outlined),
                        text: _tabLabel('Photos', _tabCount('photos')),
                      ),
                      Tab(
                        icon: const Icon(Icons.videocam_outlined),
                        text: _tabLabel('Reels', _tabCount('reels')),
                      ),
                      const Tab(
                        icon: Icon(Icons.bookmark_border_rounded),
                        text: 'Saved reels',
                      ),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              children: [
                _MyProviderPhotosTab(isProviderMode: _mode == 'provider'),
                _MyProviderReelsTab(isProviderMode: _mode == 'provider'),
                _MySavedReelsTab(isProviderMode: _mode == 'provider'),
              ],
            ),
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

class _ProfileEmptyTab extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ProfileEmptyTab({
    required this.title,
    required this.subtitle,
    this.icon = Icons.inbox_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom + 110;
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + (bottomPad * 0.35)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyProviderReelsTab extends ConsumerWidget {
  final bool isProviderMode;
  const _MyProviderReelsTab({required this.isProviderMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isProviderMode) {
      return const _ProfileEmptyTab(
        icon: Icons.toggle_off_rounded,
        title: 'Provider mode is off',
        subtitle: 'Turn on Provider mode to see and manage your reels here.',
      );
    }

    final async = ref
        .watch(myProviderReelsProvider(const MyProviderReelsQuery(limit: 12)));

    return async.when(
      loading: () =>
          const Center(child: CupertinoActivityIndicator(radius: 14)),
      error: (e, _) => _ProfileEmptyTab(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load reels",
        subtitle: apiErrorMessage(e),
      ),
      data: (res) {
        final items = res.data;
        if (items.isEmpty) {
          return const _ProfileEmptyTab(
            icon: Icons.videocam_off_rounded,
            title: 'No reels yet',
            subtitle: 'Upload your first reel from the + button.',
          );
        }

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            MediaQuery.paddingOf(context).bottom + 120,
          ),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 9 / 16,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _ProviderReelTile(item: items[i]),
        );
      },
    );
  }
}

class _MyProviderPhotosTab extends ConsumerWidget {
  final bool isProviderMode;
  const _MyProviderPhotosTab({required this.isProviderMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isProviderMode) {
      return const _ProfileEmptyTab(
        icon: Icons.toggle_off_rounded,
        title: 'Provider mode is off',
        subtitle: 'Turn it on to view and manage your photos here.',
      );
    }

    final async = ref.watch(
      myProviderPhotosProvider(const MyProviderPhotosQuery(limit: 12)),
    );

    return async.when(
      loading: () =>
          const Center(child: CupertinoActivityIndicator(radius: 14)),
      error: (e, _) => _ProfileEmptyTab(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load photos",
        subtitle: apiErrorMessage(e),
      ),
      data: (res) {
        final items = res.data;
        if (items.isEmpty) {
          return const _ProfileEmptyTab(
            icon: Icons.photo_library_outlined,
            title: 'No photos yet',
            subtitle: 'Upload your first photo from the + button.',
          );
        }

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            MediaQuery.paddingOf(context).bottom + 120,
          ),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 9 / 16,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _ProviderPhotoTile(item: items[i]),
        );
      },
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

class _MySavedReelsTab extends ConsumerWidget {
  final bool isProviderMode;
  const _MySavedReelsTab({required this.isProviderMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isProviderMode) {
      return const _ProfileEmptyTab(
        icon: Icons.toggle_off_rounded,
        title: 'Provider mode is off',
        subtitle: 'Turn it on to see your saved reels here.',
      );
    }

    final async =
        ref.watch(mySavedReelsProvider(const MySavedReelsQuery(limit: 12)));

    return async.when(
      loading: () =>
          const Center(child: CupertinoActivityIndicator(radius: 14)),
      error: (e, _) => _ProfileEmptyTab(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load saved reels",
        subtitle: apiErrorMessage(e),
      ),
      data: (res) {
        final items = res.data;
        if (items.isEmpty) {
          return const _ProfileEmptyTab(
            icon: Icons.bookmark_border_rounded,
            title: 'Nothing saved yet',
            subtitle: 'Save reels to quickly find them here later.',
          );
        }

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            MediaQuery.paddingOf(context).bottom + 120,
          ),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 9 / 16,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _SavedReelTile(item: items[i]),
        );
      },
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
                      top: 10,
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
                        child: Text(
                          '${_compact(item.viewCount)} views',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
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
                      top: 10,
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
                        child: Text(
                          '${_compact(item.viewCount)} views',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
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

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabHeaderDelegate(this.tabBar);

  static const double _extent = 56;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: maxExtent,
      child: ColoredBox(
        color: _ProfilePalette.bg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _ProfilePalette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _ProfilePalette.border),
              boxShadow: [
                BoxShadow(
                  color: _ProfilePalette.accent.withAlpha(12),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: tabBar,
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

class _AvatarSquare extends StatelessWidget {
  final String avatarUrl;
  final String fallbackText;
  const _AvatarSquare({
    required this.avatarUrl,
    required this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: _ProfilePalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ProfilePalette.border, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: avatarUrl.trim().isEmpty
            ? _AvatarFallback(text: fallbackText)
            : CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 120),
                placeholder: (context, url) =>
                    _AvatarFallback(text: fallbackText),
                errorWidget: (context, url, error) =>
                    _AvatarFallback(text: fallbackText),
              ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String text;
  const _AvatarFallback({required this.text});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _ProfilePalette.accent.withAlpha(12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_rounded,
              color: _ProfilePalette.accent.withAlpha(170),
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.textSecondary.withAlpha(140),
                fontSize: 11,
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

class _StatsRow extends StatelessWidget {
  final int followers;
  final int following;
  final int posts;
  final int likes;

  const _StatsRow({
    required this.followers,
    required this.following,
    required this.posts,
    required this.likes,
  });

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: _ProfilePalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ProfilePalette.border),
        boxShadow: [
          BoxShadow(
            color: _ProfilePalette.accent.withAlpha(12),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCell(value: _fmt(posts), label: 'Posts'),
          ),
          Container(width: 1, height: 36, color: _ProfilePalette.border),
          Expanded(
            child: _StatCell(value: _fmt(followers), label: 'Followers'),
          ),
          Container(width: 1, height: 36, color: _ProfilePalette.border),
          Expanded(
            child: _StatCell(value: _fmt(following), label: 'Following'),
          ),
          Container(width: 1, height: 36, color: _ProfilePalette.border),
          Expanded(
            child: _StatCell(value: _fmt(likes), label: 'Likes'),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final String headline;
  final String handle;
  final String bio;
  final int followers;
  final int following;
  final int posts;
  final int likes;
  final bool isPreview;
  final VoidCallback onEditTap;
  final VoidCallback onMenuTap;
  final double titleProgress;

  const _HeaderCard({
    required this.avatarUrl,
    required this.name,
    required this.headline,
    required this.handle,
    required this.bio,
    required this.followers,
    required this.following,
    required this.posts,
    required this.likes,
    required this.isPreview,
    required this.onEditTap,
    required this.onMenuTap,
    required this.titleProgress,
  });

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeIn.transform(
      ((titleProgress - 0.15) / 0.50).clamp(0.0, 1.0),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _ProfilePalette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _ProfilePalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AvatarSquare(
                  avatarUrl: avatarUrl,
                  fallbackText: _initials(name),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        opacity: 1 - t,
                        child: Transform.translate(
                          offset: Offset(0, -16 * t),
                          child: Text(
                            name,
                            maxLines: 3,
                            overflow: TextOverflow.clip,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: AppColors.textPrimary,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                      if (headline.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Opacity(
                          opacity: 1 - t,
                          child: Transform.translate(
                            offset: Offset(0, -10 * t),
                            child: Text(
                              headline,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textPrimary.withAlpha(150),
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (handle.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Opacity(
                          opacity: 1 - t,
                          child: Transform.translate(
                            offset: Offset(0, -10 * t),
                            child: Text(
                              handle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PillButton(
                        label: isPreview ? 'Preview' : 'Edit',
                        filled: true,
                        onTap: onEditTap,
                      ),
                      _PillButton(
                        label: 'Menu',
                        onTap: onMenuTap,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _StatsRow(
              followers: followers,
              following: following,
              posts: posts,
              likes: likes,
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: _ProfilePalette.border.withAlpha(120),
            ),
            const SizedBox(height: 12),
            Text(
              bio,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: _ProfilePalette.border.withAlpha(120),
            ),
            const SizedBox(height: 10),
            const _WebsiteRow(url: 'https://skilreel.app'),
          ],
        ),
      ),
    );
  }
}

class _WebsiteRow extends StatelessWidget {
  final String url;
  const _WebsiteRow({required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Website link copied')),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            const Icon(
              Icons.link_rounded,
              size: 16,
              color: _ProfilePalette.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.copy_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? _ProfilePalette.accent : _ProfilePalette.surface;
    final fg = filled ? Colors.white : AppColors.textPrimary;
    final border = filled ? Colors.transparent : _ProfilePalette.border;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
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

class _ProfilePalette {
  // White-based, premium neutral palette (no pink).
  static const bg = AppColors.surface; // pure white background
  static const surface = AppColors.bg; // subtle contrast for cards/sections
  static const border = AppColors.border;

  static const accent = AppColors.primary;
}

const _demoUser = <String, dynamic>{
  'name': 'Your Name',
  'bio': 'Your premium profile preview will look like this.',
  'followersCount': 684000,
  'followingCount': 2514,
  'postsCount': 254,
};

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\\s+')).where((p) => p.isNotEmpty);
  final p = parts.toList();
  if (p.isEmpty) return 'SR';
  final a = p.first.isEmpty ? 'S' : p.first[0];
  final b = (p.length >= 2 && p[1].isNotEmpty)
      ? p[1][0]
      : (p.first.length >= 2 ? p.first[1] : 'R');
  return (a + b).toUpperCase();
}
