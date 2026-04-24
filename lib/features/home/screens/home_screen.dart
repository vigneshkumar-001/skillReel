import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/router/route_observer.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/url_utils.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../../reels/models/reel_model.dart';
import '../../reels/providers/reels_viewer_provider.dart';
import '../../search/models/search_category_model.dart';
import '../../search/providers/search_provider.dart';

class _HomePalette {
  // Keep identical to Profile screen palette for consistent UI.
  static const bg = Color(0xFFF5EDE3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceTint = Color(0xFFFCF8F2);
  static const border = Color(0xFFEAE2D7);
  static const accent = Color(0xFFF6A23A);
  static const accentSoft = Color(0xFFFFF1DF);
}

class _HomeAssets {
  static const banner1 = 'assets/images/banner1.png';
  static const boostReelsBanner = 'assets/images/boostReelsBanner.png';
  static const boostProdutcBanner = 'assets/images/boostProdutcBanner.png';
  static const specialOffer = 'assets/images/specialOffer.png';
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with RouteAware {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _reelsKey = GlobalKey();
  final ValueNotifier<double> _reelsProximity = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _isScrolling = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _routeIsCurrent = ValueNotifier<bool>(true);
  bool _routeSubscribed = false;
  String? _lastViewedReelId;

  void _onScrollStateChanged() {
    if (!_scrollController.hasClients) return;
    final next = _scrollController.position.isScrollingNotifier.value;
    if (_isScrolling.value != next) _isScrolling.value = next;
  }

  void _bindScrollState() {
    if (!_scrollController.hasClients) return;
    _scrollController.position.isScrollingNotifier
        .addListener(_onScrollStateChanged);
    _onScrollStateChanged();
  }

  void _updateReelsProximity() {
    final ctx = _reelsKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final offset = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.of(ctx).size.height;
    final centerY = offset.dy + (box.size.height / 2);
    final dist = (centerY - (screenH * 0.58)).abs();
    final t = (1.0 - (dist / (screenH * 0.55))).clamp(0.0, 1.0);
    if ((_reelsProximity.value - t).abs() > 0.02) {
      _reelsProximity.value = t;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateReelsProximity);
    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      _bindScrollState();
      _updateReelsProximity();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeSubscribed && route != null) {
      routeObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didPushNext() {
    // Another route covered Home; ensure any inline reel preview pauses.
    _routeIsCurrent.value = false;
  }

  @override
  void didPopNext() {
    // Returned to Home; allow inline reel preview to resume if visible.
    _routeIsCurrent.value = true;
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    if (_scrollController.hasClients) {
      _scrollController.position.isScrollingNotifier
          .removeListener(_onScrollStateChanged);
    }
    _scrollController
      ..removeListener(_updateReelsProximity)
      ..dispose();
    _reelsProximity.dispose();
    _isScrolling.dispose();
    _routeIsCurrent.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    ref.invalidate(myProfileProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(searchCategoriesProvider);
    ref.invalidate(
        reelsViewerControllerProvider(const ReelsFeedConfig(type: 'trending')));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final notifsAsync = ref.watch(notificationsProvider);
    final categoriesAsync = ref.watch(searchCategoriesProvider);
    final reelsAsync = ref.watch(
      reelsViewerControllerProvider(const ReelsFeedConfig(type: 'trending')),
    );

    final username = profileAsync.valueOrNull?['name']?.toString().trim();
    final handle = profileAsync.valueOrNull?['username']?.toString().trim();
    final avatarUrl = UrlUtils.normalizeMediaUrl(
      profileAsync.valueOrNull?['avatar']?.toString(),
    );

    final unreadCount = notifsAsync.valueOrNull
            ?.where((n) => (n is Map) ? (n['isRead'] != true) : false)
            .length ??
        0;

    final categories = categoriesAsync.valueOrNull ?? const [];
    final reels = reelsAsync.valueOrNull?.reels ?? const <ReelModel>[];
    ReelModel? previewReel;
    if (reels.isNotEmpty) {
      final preferredId = (_lastViewedReelId ?? '').trim();
      if (preferredId.isNotEmpty) {
        previewReel = reels.firstWhere(
          (r) => r.id == preferredId,
          orElse: () => reels.first,
        );
      } else {
        previewReel = reels.firstWhere(
          (r) =>
              r.mediaType.toLowerCase() == 'video' &&
              r.mediaUrl.trim().isNotEmpty,
          orElse: () => reels.first,
        );
      }
    }
    final previewIndex = (previewReel == null || previewReel.id.isEmpty)
        ? -1
        : reels.indexWhere((x) => x.id == previewReel!.id);
    final nextPreviewReel =
        (previewIndex >= 0 && previewIndex + 1 < reels.length)
            ? reels[previewIndex + 1]
            : (reels.length > 1 ? reels[1] : null);

    return Scaffold(
      backgroundColor: _HomePalette.bg,
      body: RefreshIndicator.adaptive(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: HomeHeader(
                    avatarUrl: avatarUrl,
                    username:
                        (username?.isNotEmpty ?? false) ? username! : 'Hi!',
                    subtitle: (handle?.isNotEmpty ?? false)
                        ? '@$handle'
                        : 'Welcome back',
                    unreadCount: unreadCount,
                    onTapBell: () => context.push('/notifications'),
                    onTapProfile: () => context.push('/profile'),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: const _HomeHero(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: BannerCarousel(
                  height: 160,
                  autoScroll: true,
                  items: const [
                    BannerItem(
                      title: 'Premium creators',
                      subtitle: 'Find verified providers near you',
                      assetImagePath: _HomeAssets.banner1,
                    ),
                    BannerItem(
                      title: 'Boost your reel',
                      subtitle: 'Get more enquiries in minutes',
                      assetImagePath: _HomeAssets.boostReelsBanner,
                    ),
                    BannerItem(
                      title: 'Save & share',
                      subtitle: 'Build your shortlist fast',
                      assetImagePath: _HomeAssets.boostProdutcBanner,
                    ),
                    BannerItem(
                      title: 'Special offer',
                      subtitle: 'Limited time only',
                      assetImagePath: _HomeAssets.specialOffer,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: DiscoverHeader(
                  onViewAll: () => context.push('/search'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: CategorySection(
                  categories: categories.take(8).toList(growable: false),
                  loading: categoriesAsync.isLoading,
                  onTapCategory: (c) {
                    HapticFeedback.selectionClick();
                    context.push(
                      '/search/category/${Uri.encodeComponent(c.category.trim())}',
                      extra: c.category.trim(),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _routeIsCurrent,
                  builder: (context, routeCurrent, _) =>
                      ValueListenableBuilder<double>(
                    valueListenable: _reelsProximity,
                    builder: (context, t, __) => ValueListenableBuilder<bool>(
                      valueListenable: _isScrolling,
                      builder: (context, scrolling, ___) {
                        final scale = scrolling
                            ? 1.0
                            : (lerpDouble(0.98, 1.0, t) ?? 1.0);
                        final active = routeCurrent && t > 0.35;
                        final allowPlayback = routeCurrent && !scrolling;
                        // Show the "next reel" peek whenever the card is in view,
                        // but hide it while scrolling so it doesn't distract.
                        final showPeek = routeCurrent && !scrolling && t > 0.38;
                        return Transform.scale(
                          scale: scale,
                          alignment: Alignment.center,
                          child: ReelsPreviewCard(
                            key: _reelsKey,
                            reel: previewReel,
                            nextReel: nextPreviewReel,
                            isActive: active,
                            allowPlayback: allowPlayback,
                            showPeek: showPeek,
                            onOpen: (reelId, heroTag) async {
                              final cleanReelId = reelId.trim();
                              if (cleanReelId.isEmpty) return;
                              HapticFeedback.selectionClick();
                              final res = await context.push(
                                '/reels',
                                extra: {
                                  'initialReelId': cleanReelId,
                                  'heroTag': heroTag,
                                },
                              );
                              if (!mounted) return;
                              final viewedId = (res is Map)
                                  ? res['reelId']?.toString()
                                  : res?.toString();
                              final clean = (viewedId ?? '').trim();
                              if (clean.isNotEmpty &&
                                  clean != (_lastViewedReelId ?? '').trim()) {
                                setState(() => _lastViewedReelId = clean);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child:
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 110),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeHeader extends StatelessWidget {
  final String avatarUrl;
  final String username;
  final String subtitle;
  final int unreadCount;
  final VoidCallback onTapBell;
  final VoidCallback onTapProfile;

  const HomeHeader({
    super.key,
    required this.avatarUrl,
    required this.username,
    required this.subtitle,
    required this.unreadCount,
    required this.onTapBell,
    required this.onTapProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onTapProfile,
          borderRadius: BorderRadius.circular(999),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 44,
              height: 44,
              color: _HomePalette.surfaceTint,
              child: avatarUrl.trim().isEmpty
                  ? const Icon(Icons.person, color: AppColors.textSecondary)
                  : CachedNetworkImage(
                      imageUrl: avatarUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: onTapProfile,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary.withAlpha(220),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedNotificationBell(
          unreadCount: unreadCount,
          onTap: onTapBell,
        ),
      ],
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Discover, Connect,\nAnd Create Together.',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 32,
            height: 1.05,
            color: AppColors.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class AnimatedNotificationBell extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onTap;
  const AnimatedNotificationBell({
    super.key,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  State<AnimatedNotificationBell> createState() =>
      _AnimatedNotificationBellState();
}

class _AnimatedNotificationBellState extends State<AnimatedNotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = widget.unreadCount > 0;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value;
          final pulse =
              hasUnread ? (1.0 + (0.05 * (1 - (2 * (t - 0.5)).abs()))) : 1.0;
          return Transform.scale(
            scale: pulse,
            child: child,
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _HomePalette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _HomePalette.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(10),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.textPrimary,
              ),
            ),
            if (hasUnread)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _HomePalette.accent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.white.withAlpha(190), width: 1),
                  ),
                  child: Text(
                    widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BannerItem {
  final String title;
  final String subtitle;
  final String? assetImagePath;
  const BannerItem({
    required this.title,
    required this.subtitle,
    this.assetImagePath,
  });
}

class BannerCarousel extends StatefulWidget {
  final double height;
  final List<BannerItem> items;
  final bool autoScroll;
  const BannerCarousel({
    super.key,
    required this.height,
    required this.items,
    this.autoScroll = true,
  });

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late final PageController _pc;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final len = widget.items.length;
    final startPage = len == 0 ? 0 : len * 1000; // start on item[0], but allow infinite forward scroll
    _pc = PageController(viewportFraction: 0.92, initialPage: startPage);
    if (widget.autoScroll) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted || !_pc.hasClients) return;
        if (widget.items.length <= 1) return;
        _pc.nextPage(
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final len = widget.items.length;
    return SizedBox(
      height: widget.height,
      child: Semantics(
        label: len == 0 ? 'Banners' : 'Banner ${_index + 1} of $len',
        child: PageView.builder(
          controller: _pc,
          onPageChanged: (p) {
            if (len == 0) return;
            setState(() => _index = p % len);
          },
          itemCount: len == 0 ? 0 : null,
          itemBuilder: (context, i) {
            if (len == 0) return const SizedBox.shrink();
            final item = widget.items[i % len];
            final imageAsset = (item.assetImagePath ?? '').trim();
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _HomePalette.accentSoft,
                        _HomePalette.surfaceTint,
                        _HomePalette.surface,
                      ],
                    ),
                    border: Border.all(color: _HomePalette.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 26,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      if (imageAsset.isNotEmpty)
                        Positioned.fill(
                          child: ColoredBox(
                            color: _HomePalette.surface,
                            child: Image.asset(
                              imageAsset,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) => CustomPaint(
                                painter: _BannerWavePainter(),
                              ),
                            ),
                          ),
                        ),
                      if (imageAsset.isEmpty)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _BannerWavePainter(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BannerWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _HomePalette.accent.withAlpha(24),
          _HomePalette.accent.withAlpha(0),
        ],
      ).createShader(Offset.zero & size);

    final path = Path()
      ..moveTo(0, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.30,
        size.height * 0.62,
        size.width * 0.58,
        size.height * 0.72,
      )
      ..quadraticBezierTo(
        size.width * 0.80,
        size.height * 0.80,
        size.width,
        size.height * 0.70,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DiscoverHeader extends StatelessWidget {
  final VoidCallback onViewAll;
  const DiscoverHeader({super.key, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Discover',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        TextButton(
          onPressed: onViewAll,
          style: TextButton.styleFrom(
            foregroundColor: _HomePalette.accent,
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
          child: const Text('View All'),
        ),
      ],
    );
  }
}

class CategorySection extends StatelessWidget {
  final List<SearchCategoryModel> categories;
  final bool loading;
  final void Function(SearchCategoryModel category) onTapCategory;

  const CategorySection({
    super.key,
    required this.categories,
    required this.loading,
    required this.onTapCategory,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && categories.isEmpty) {
      return const _CategorySkeletonRow();
    }

    final show = categories.take(8).toList(growable: false);
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: show.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = show[i];
          final name = c.category.toString().trim();
          final img = UrlUtils.normalizeMediaUrl(c.imageUrl ?? '').trim();
          return GestureDetector(
            onTap: () => onTapCategory(c),
            child: SizedBox(
              width: 70,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 70,
                      height: 70,
                      color: _HomePalette.surfaceTint,
                      child: img.isEmpty
                          ? Icon(
                              Icons.category_outlined,
                              size: 20,
                              color: AppColors.textSecondary.withAlpha(200),
                            )
                          : CachedNetworkImage(
                              imageUrl: img,
                              fit: BoxFit.cover,
                              fadeInDuration: const Duration(milliseconds: 120),
                              placeholder: (_, __) => const SizedBox.shrink(),
                              errorWidget: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name.isEmpty ? 'Category' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      color: AppColors.textPrimary.withAlpha(240),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategorySkeletonRow extends StatelessWidget {
  const _CategorySkeletonRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: _HomePalette.surfaceTint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _HomePalette.border),
          ),
          child: const Center(child: CupertinoActivityIndicator(radius: 10)),
        ),
      ),
    );
  }
}

class ReelsPreviewCard extends StatefulWidget {
  final ReelModel? reel;
  final ReelModel? nextReel;
  final bool isActive;
  final bool allowPlayback;
  final bool showPeek;
  final void Function(String reelId, String heroTag)? onOpen;

  const ReelsPreviewCard({
    super.key,
    required this.reel,
    required this.nextReel,
    required this.isActive,
    required this.allowPlayback,
    required this.showPeek,
    required this.onOpen,
  });

  @override
  State<ReelsPreviewCard> createState() => _ReelsPreviewCardState();
}

class _ReelsPreviewCardState extends State<ReelsPreviewCard> {
  double _hDrag = 0.0;
  bool _frontIsNext = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.reel;
    final n = widget.nextReel;
    final hasNext = (n?.id ?? '').trim().isNotEmpty;
    final front = (_frontIsNext && hasNext) ? n : r;
    final back = (_frontIsNext && hasNext) ? r : n;
    final frontId = (front?.id ?? '').trim();
    final frontHeroTag = frontId.isNotEmpty ? 'home_reel_$frontId' : '';
    final canOpen = widget.onOpen != null && frontId.isNotEmpty;

    Widget buildCard({
      required Widget child,
      required double height,
      required BorderRadius radius,
    }) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: _HomePalette.surface,
          borderRadius: radius,
          border: Border.all(color: _HomePalette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(12),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }

    Widget buildMediaLayer({
      required ReelModel? reel,
      required bool isFront,
      required String heroTag,
    }) {
      final isNextFullCard = isFront && hasNext && _frontIsNext && reel == n;
      final thumbUrl = UrlUtils.normalizeMediaUrl(
        (reel?.thumbnailUrl ?? reel?.mediaUrl ?? '').toString(),
      );
      final mediaUrl = (reel?.mediaUrl ?? '').toString().trim();
      final previewUrl = UrlUtils.normalizeMediaUrl(mediaUrl);

      final mediaWidget = isNextFullCard
          ? (thumbUrl.isEmpty
              ? const ColoredBox(color: _HomePalette.surfaceTint)
              : CachedNetworkImage(
                  imageUrl: thumbUrl,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 120),
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ))
          : (previewUrl.isEmpty
              ? const ColoredBox(color: _HomePalette.surfaceTint)
              : ReelsInlinePreview(
                  url: previewUrl,
                  isActive: widget.isActive && widget.allowPlayback && isFront,
                ));
      if (isFront && heroTag.isNotEmpty) {
        return Positioned.fill(
          child: Hero(tag: heroTag, child: mediaWidget),
        );
      }
      return Positioned.fill(child: mediaWidget);
    }

    Widget buildFrontCard(ReelModel? reel) {
      final providerName = (reel?.providerName ?? '').trim();
      final providerAvatar = UrlUtils.normalizeMediaUrl(reel?.providerAvatar);
      final isOwn = reel?.isOwnReel == true;
      final heroTag =
          ((reel?.id ?? '').trim().isNotEmpty) ? 'home_reel_${reel!.id}' : '';

      return buildCard(
        height: 260,
        radius: BorderRadius.circular(28),
        child: Stack(
          children: [
            buildMediaLayer(
              reel: reel,
              isFront: true,
              heroTag: heroTag,
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(0),
                      Colors.black.withAlpha(0),
                      Colors.black.withAlpha(130),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 10,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _HomePalette.accent.withAlpha(0),
                      _HomePalette.accent.withAlpha(160),
                      _HomePalette.accent.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withAlpha(24)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_fill_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Reels',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (reel?.isBoosted == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: _HomePalette.accent.withAlpha(220),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'BOOST',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (reel?.title ?? 'Reels').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(22),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withAlpha(26)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: providerAvatar.isEmpty
                            ? const Icon(Icons.person_rounded,
                                color: Colors.white)
                            : CachedNetworkImage(
                                imageUrl: providerAvatar,
                                fit: BoxFit.cover,
                                fadeInDuration:
                                    const Duration(milliseconds: 120),
                                placeholder: (_, __) => const SizedBox.shrink(),
                                errorWidget: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          providerName.isEmpty ? 'Creator' : providerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (!isOwn)
                        GestureDetector(
                          onTap: canOpen
                              ? () => widget.onOpen?.call(
                                    frontId,
                                    frontHeroTag,
                                  )
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _HomePalette.accent.withAlpha(235),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Text(
                              'Follow',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildPeekCard(ReelModel? reel) {
      final backId = (reel?.id ?? '').trim();
      final thumbUrl = UrlUtils.normalizeMediaUrl(
          (reel?.thumbnailUrl ?? reel?.mediaUrl ?? '').toString());
      final providerName = (reel?.providerName ?? '').trim();
      final providerAvatar = UrlUtils.normalizeMediaUrl(reel?.providerAvatar);
      final label = _frontIsNext ? 'Previous' : 'Next';

      return buildCard(
        height: 54,
        radius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _HomePalette.surface,
                      _HomePalette.surfaceTint,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 12,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary.withAlpha(210),
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  height: 1.0,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (backId.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                top: 6,
                bottom: 6,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 32,
                        height: 32,
                        color: _HomePalette.surfaceTint,
                        child: thumbUrl.isEmpty
                            ? Icon(Icons.play_arrow_rounded,
                                color: AppColors.textPrimary.withAlpha(230))
                            : CachedNetworkImage(
                                imageUrl: thumbUrl,
                                fit: BoxFit.cover,
                                fadeInDuration:
                                    const Duration(milliseconds: 120),
                                placeholder: (_, __) => const SizedBox.shrink(),
                                errorWidget: (_, __, ___) =>
                                    const SizedBox.shrink(),
                          ),
                        ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (reel?.title ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: _HomePalette.surface,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: _HomePalette.border),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: providerAvatar.isEmpty
                                    ? Icon(Icons.person_rounded,
                                        size: 11,
                                        color: AppColors.textPrimary
                                            .withAlpha(210))
                                    : CachedNetworkImage(
                                        imageUrl: providerAvatar,
                                        fit: BoxFit.cover,
                                        fadeInDuration:
                                            const Duration(milliseconds: 120),
                                        placeholder: (_, __) =>
                                            const SizedBox.shrink(),
                                        errorWidget: (_, __, ___) =>
                                            const SizedBox.shrink(),
                                      ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  providerName.isEmpty
                                      ? 'Creator'
                                      : providerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        AppColors.textSecondary.withAlpha(230),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: canOpen ? () => widget.onOpen?.call(frontId, frontHeroTag) : null,
      onHorizontalDragStart: hasNext ? (_) => _hDrag = 0.0 : null,
      onHorizontalDragUpdate:
          hasNext ? (d) => setState(() => _hDrag += d.delta.dx) : null,
      onHorizontalDragEnd: hasNext
          ? (d) {
              final v = d.velocity.pixelsPerSecond.dx;
              final shouldSwap = v.abs() > 420 || _hDrag.abs() > 52;
              if (!shouldSwap) return;
              HapticFeedback.selectionClick();
              setState(() {
                _frontIsNext = !_frontIsNext;
                _hDrag = 0.0;
              });
            }
          : null,
      child: SizedBox(
        height: 270,
        
        child: Stack(
          children: [
            if ((back?.id ?? '').trim().isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  opacity: (widget.showPeek && widget.isActive) ? 1 : 0,
                  child: Transform.scale(
                    scale: 0.96,
                    alignment: Alignment.bottomCenter,
                    child: buildPeekCard(back),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey(frontId),
                  child: buildFrontCard(front),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReelsInlinePreview extends StatefulWidget {
  final String url;
  final bool isActive;

  const ReelsInlinePreview({
    super.key,
    required this.url,
    required this.isActive,
  });

  @override
  State<ReelsInlinePreview> createState() => _ReelsInlinePreviewState();
}

class _ReelsInlinePreviewState extends State<ReelsInlinePreview>
    with WidgetsBindingObserver {
  VideoPlayerController? _ctrl;
  Future<void>? _init;

  Future<void> _create() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    final c = VideoPlayerController.networkUrl(uri);
    _ctrl = c;
    await c.initialize();
    await c.setLooping(true);
    await c.setVolume(0.0);
    if (widget.isActive) {
      await c.play();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init = _create();
  }

  @override
  void didUpdateWidget(covariant ReelsInlinePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _ctrl?.dispose();
      _ctrl = null;
      _init = _create();
      setState(() {});
      return;
    }

    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (widget.isActive && !c.value.isPlaying) {
      unawaited(c.play());
    } else if (!widget.isActive && c.value.isPlaying) {
      unawaited(c.pause());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      c.pause();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      c.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snap) {
        final c = _ctrl;
        if (c == null || !c.value.isInitialized) {
          return const Center(child: CupertinoActivityIndicator(radius: 14));
        }
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        );
      },
    );
  }
}
