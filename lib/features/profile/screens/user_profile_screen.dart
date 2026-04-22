import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/url_utils.dart';
import '../../providers_module/providers/provider_state_provider.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/network/models/my_provider_photos_model.dart';
import '../../../core/network/models/my_provider_reels_model.dart';
import '../../interactions/repositories/interactions_repository.dart';
import '../../reviews/repositories/review_repository.dart';

typedef UserProfileSeed = ({
  String name,
  String? avatarUrl,
  bool verified,
  String heroTag,
  bool isFollowed,
});

final _reviewRepoProvider = Provider((_) => ReviewRepository());

enum _ProfileSection { about, reels, photos, availability, experience, reviews }

const List<_ProfileSection> _profileSections = <_ProfileSection>[
  _ProfileSection.about,
  _ProfileSection.reels,
  _ProfileSection.photos,
  _ProfileSection.availability,
  _ProfileSection.experience,
  _ProfileSection.reviews,
];

const double _kStickyProfileHeaderExtent = 124;
const double _kPinnedTabsExtent = 92;

class UserProfileScreen extends ConsumerStatefulWidget {
  final String providerId;
  final UserProfileSeed? seed;

  const UserProfileScreen({
    super.key,
    required this.providerId,
    this.seed,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  late bool _isFollowed = widget.seed?.isFollowed ?? false;
  final ValueNotifier<double> _titleProgress = ValueNotifier<double>(0);
  final ValueNotifier<int> _activeSectionIndex = ValueNotifier<int>(0);
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _sheetViewportKey = GlobalKey();
  bool _didSeedFollowFromApi = false;
  bool _didInitialSectionFromApi = false;
  bool _scheduledOffsetRecalc = false;
  int _followOpTick = 0;
  _ProfileSection? _pendingScrollToSection;

  final GlobalKey _aboutKey = GlobalKey();
  final GlobalKey _reelsKey = GlobalKey();
  final GlobalKey _photosKey = GlobalKey();
  final GlobalKey _availabilityKey = GlobalKey();
  final GlobalKey _experienceKey = GlobalKey();
  final GlobalKey _reviewsKey = GlobalKey();

  final Map<_ProfileSection, double> _sectionOffsets = <_ProfileSection, double>{};

  static const double _titleThreshold = 86;

  Future<void> _toggleFollow() async {
    final id = widget.providerId.trim();
    if (id.isEmpty) return;

    HapticFeedback.selectionClick();
    final nextFollowed = !_isFollowed;
    final tick = _followOpTick + 1;
    _followOpTick = tick;

    setState(() => _isFollowed = nextFollowed);

    try {
      await ref.read(interactionsRepoProvider).postInteraction(
            action: nextFollowed ? 'follow' : 'unfollow',
            providerId: id,
            surface: 'profile',
            screen: 'UserProfileScreen',
          );
    } catch (e) {
      if (!mounted) return;
      if (_followOpTick != tick) return;
      setState(() => _isFollowed = !nextFollowed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    }
  }

  Future<void> _openWriteReview({
    required String providerId,
    required String providerName,
    required String profession,
    required String avatarUrl,
  }) async {
    if (providerId.trim().isEmpty) return;
    HapticFeedback.selectionClick();
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WriteReviewPage(
          providerId: providerId,
          providerName: providerName,
          profession: profession,
          avatarUrl: avatarUrl,
        ),
      ),
    );
    if (!mounted) return;
    if (submitted == true) {
      ref.invalidate(providerPublicOverviewProvider(providerId));
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      _onSheetScroll(_scrollController.position);
    });
  }

  void _onSheetScroll(ScrollMetrics metrics) {
    final next = (metrics.pixels / _titleThreshold).clamp(0.0, 1.0);
    _titleProgress.value = next;
    _maybeLoadMoreMedia(metrics);
    _updateActiveSectionFromScroll(metrics.pixels);
  }

  void _maybeLoadMoreMedia(ScrollMetrics metrics) {
    final remaining = metrics.maxScrollExtent - metrics.pixels;
    if (remaining > 720) return;

    final id = widget.providerId.trim();
    if (id.isEmpty) return;
    ref.read(providerPublicPhotosControllerProvider(id).notifier).loadMore();
    ref.read(providerPublicReelsControllerProvider(id).notifier).loadMore();
  }

  void _scheduleOffsetRecalculation() {
    if (_scheduledOffsetRecalc) return;
    _scheduledOffsetRecalc = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduledOffsetRecalc = false;
      if (!mounted) return;
      _recalculateSectionOffsets();
      if (_scrollController.hasClients) {
        _updateActiveSectionFromScroll(_scrollController.offset);
      }
    });
  }

  void _recalculateSectionOffsets() {
    final entries = <_ProfileSection, GlobalKey>{
      _ProfileSection.about: _aboutKey,
      _ProfileSection.reels: _reelsKey,
      _ProfileSection.photos: _photosKey,
      _ProfileSection.availability: _availabilityKey,
      _ProfileSection.experience: _experienceKey,
      _ProfileSection.reviews: _reviewsKey,
    };

    final rootObj = _sheetViewportKey.currentContext?.findRenderObject();
    final rootBox = rootObj is RenderBox ? rootObj : null;
    final ctrl = _scrollController;

    for (final e in entries.entries) {
      final ctx = e.value.currentContext;
      if (ctx == null) continue;
      final obj = ctx.findRenderObject();
      if (obj == null) continue;
      if (rootBox != null && ctrl.hasClients && obj is RenderBox) {
        final dy = obj.localToGlobal(Offset.zero, ancestor: rootBox).dy;
        _sectionOffsets[e.key] = (ctrl.offset + dy).clamp(0.0, double.infinity);
        continue;
      }
      final viewport = RenderAbstractViewport.maybeOf(obj);
      if (viewport == null) continue;
      _sectionOffsets[e.key] = viewport.getOffsetToReveal(obj, 0).offset;
    }
  }

  void _updateActiveSectionFromScroll(double scrollOffset) {
    if (_sectionOffsets.length < _profileSections.length) return;

    // Tabs are pinned (SliverPersistentHeader), so probe beyond it.
    const pinnedHeader = _kPinnedTabsExtent;
    final probe = scrollOffset + pinnedHeader + 12;
    var nextIndex = 0;
    for (var i = 0; i < _profileSections.length; i++) {
      final off = _sectionOffsets[_profileSections[i]] ?? double.negativeInfinity;
      if (off <= probe) nextIndex = i;
    }
    if (_activeSectionIndex.value != nextIndex) {
      _activeSectionIndex.value = nextIndex;
    }
  }

  Future<void> _scrollToSection(_ProfileSection section, {bool haptic = true}) async {
    final ctrl = _scrollController;
    if (!ctrl.hasClients) return;
    _scheduleOffsetRecalculation();

    var raw = _sectionOffsets[section];
    if (raw == null) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      raw = _sectionOffsets[section];
    }
    if (raw == null) return;
    // Account for the pinned sticky tabs header so section titles don't land
    // underneath it.
    const pinnedHeader = _kPinnedTabsExtent;
    final target =
        (raw - pinnedHeader - 10).clamp(0.0, double.infinity);

    if (haptic) HapticFeedback.selectionClick();
    await ctrl.animateTo(
      target,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  String _nextAvailableText() {
    final now = DateTime.now();
    // Simple premium-friendly heuristic until availability is backed by API.
    // Weekdays: next slot today 4 PM if earlier, otherwise tomorrow 10 AM.
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    if (isWeekend) return 'Next available on Monday at 10:00 AM';

    final next4pm = DateTime(now.year, now.month, now.day, 16);
    if (now.isBefore(next4pm)) return 'Next available today at 4:00 PM';
    return 'Next available tomorrow at 10:00 AM';
  }

  @override
  void dispose() {
    _titleProgress.dispose();
    _activeSectionIndex.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync =
        ref.watch(providerPublicOverviewProvider(widget.providerId));

    return overviewAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _buildContent(context, profile: const <String, dynamic>{}),
      data: (overview) => _buildContent(context, profile: overview),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required Map<String, dynamic> profile,
  }) {
    final seed = widget.seed;
    final apiProfileObj = profile['profile'];
    final apiProfile = apiProfileObj is Map
        ? Map<String, dynamic>.from(apiProfileObj)
        : const <String, dynamic>{};

    final verificationObj = apiProfile['verification'];
    final verification = verificationObj is Map
        ? Map<String, dynamic>.from(verificationObj)
        : const <String, dynamic>{};

    final viewerObj = profile['viewer'];
    final viewer = viewerObj is Map
        ? Map<String, dynamic>.from(viewerObj)
        : const <String, dynamic>{};

    final activeTab = (profile['activeTab'] ?? '').toString().trim();

    final seededName = (seed?.name ?? '').trim();
    final apiName = (apiProfile['displayName'] ?? '').toString().trim();
    final displayName = apiName.isNotEmpty
        ? apiName
        : (seededName.isEmpty ? 'Profile' : seededName);

    final avatarUrl = UrlUtils.normalizeMediaUrl(
      apiProfile['avatarUrl']?.toString() ?? seed?.avatarUrl,
    );

    final headline = (apiProfile['headline'] ?? '').toString().trim();

    final apiIsFollowing = viewer['isFollowing'] == true;
    if (!_didSeedFollowFromApi && widget.seed == null) {
      _didSeedFollowFromApi = true;
      if (_isFollowed != apiIsFollowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _isFollowed = apiIsFollowing);
        });
      }
    }

    final statsObj = profile['stats'];
    final stats = statsObj is Map ? Map<String, dynamic>.from(statsObj) : const <String, dynamic>{};
    int statValue(String key) {
      final o = stats[key];
      if (o is Map) {
        final v = o['value'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse((v ?? '').toString()) ?? 0;
      }
      return 0;
    }

    final id = widget.providerId.trim();
    final reelsState =
        id.isEmpty ? null : ref.watch(providerPublicReelsControllerProvider(id));
    final reelsCtrl =
        id.isEmpty ? null : ref.read(providerPublicReelsControllerProvider(id).notifier);
    final photosState =
        id.isEmpty ? null : ref.watch(providerPublicPhotosControllerProvider(id));
    final photosCtrl =
        id.isEmpty ? null : ref.read(providerPublicPhotosControllerProvider(id).notifier);


    int? startingPrice;
    int considerPrice(int? p) {
      final v = p ?? 0;
      if (v <= 0) return startingPrice ?? 0;
      if (startingPrice == null) {
        startingPrice = v;
      } else if (v < startingPrice!) {
        startingPrice = v;
      }
      return startingPrice ?? v;
    }

    if (reelsState != null) {
      for (final r in reelsState.items) {
        considerPrice(r.price);
      }
    }
    if (photosState != null) {
      for (final p in photosState.items) {
        considerPrice(p.price);
      }
    }

    final expObj = apiProfile['experienceYears'] ?? apiProfile['experience'];
    final experienceYears = (expObj is num)
        ? expObj.round()
        : int.tryParse((expObj ?? '').toString()) ?? 0;

    final avgRating = (verification['averageRating'] is num)
        ? (verification['averageRating'] as num).toDouble()
        : double.tryParse((verification['averageRating'] ?? '').toString()) ?? 0.0;
    final totalReviews = (verification['totalReviews'] is num)
        ? (verification['totalReviews'] as num).round()
        : int.tryParse((verification['totalReviews'] ?? '').toString()) ?? 0;
    final reviewsObj = profile['reviews'];
    final reviewsRaw = reviewsObj is List ? reviewsObj : const <dynamic>[];
    final reviews = reviewsRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(_ReviewRow.fromJson)
        .toList(growable: false);
    final bio = (apiProfile['bio'] ?? '').toString().trim();
    final skillsObj = apiProfile['skills'];
    final skillsList = skillsObj is List ? skillsObj : const <dynamic>[];
    final skills = skillsList
        .map((e) {
          if (e is Map && e['name'] != null) return e['name'].toString();
          return e?.toString() ?? '';
        })
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    _scheduleOffsetRecalculation();

    final initialSection = switch (activeTab) {
      'reels' => _ProfileSection.reels,
      'photos' => _ProfileSection.photos,
      'availability' => _ProfileSection.availability,
      'experience' => _ProfileSection.experience,
      'reviews' => _ProfileSection.reviews,
      _ => null,
    };
    if (!_didInitialSectionFromApi && initialSection != null) {
      _didInitialSectionFromApi = true;
      _pendingScrollToSection = initialSection;
    }

    Future<void> refreshAll() async {
      if (id.isNotEmpty) {
        ref.invalidate(providerPublicOverviewProvider(id));
        await Future.wait([
          if (photosCtrl != null) photosCtrl.refresh(),
          if (reelsCtrl != null) reelsCtrl.refresh(),
        ]);
      }
    }

    final profession = headline.isNotEmpty
        ? headline
        : (skills.isNotEmpty ? skills.first : 'photographer');

    final followerCount = statValue('followers');
    final reviewCount = totalReviews > 0 ? totalReviews : reviews.length;

    final pending = _pendingScrollToSection;
    if (pending != null) {
      _pendingScrollToSection = null;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _scrollToSection(pending, haptic: false);
      });
    }

    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _UserProfilePalette.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refreshAll,
          child: ScrollConfiguration(
            behavior: const _BouncyScrollBehavior(),
            child: CustomScrollView(
              key: _sheetViewportKey,
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: HeroProfileWithStatsSection(
                    avatarUrl: avatarUrl,
                    displayName: displayName,
                    profession: profession,
                    experienceYears: experienceYears,
                    hourlyLabel: (startingPrice != null && startingPrice! > 0)
                        ? '₹$startingPrice/hr'
                        : '₹159/hr',
                    ratingText:
                        avgRating <= 0 ? '5.0' : avgRating.toStringAsFixed(1),
                    customersText: followerCount > 0 ? '$followerCount+' : '150+',
                    onBack: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).maybePop();
                    },
                    onShare: () {
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Share coming soon')),
                      );
                    },
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyAnimatedTabsHeaderDelegate(
                    activeIndex: _activeSectionIndex,
                    onTapSection: _scrollToSection,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _ProfileSheetBody(
                    aboutKey: _aboutKey,
                    reelsKey: _reelsKey,
                    photosKey: _photosKey,
                    availabilityKey: _availabilityKey,
                    experienceKey: _experienceKey,
                    reviewsKey: _reviewsKey,
                    providerName: displayName,
                    profession: profession,
                    avatarUrl: avatarUrl,
                    aboutText: bio.isEmpty ? 'Iam waiting for shoot' : bio,
                    experienceYears: experienceYears,
                    reels: reelsState?.items ?? const <MyProviderReelItem>[],
                    photos: photosState?.items ?? const <MyProviderPhotoItem>[],
                    hourlyFee: (startingPrice != null && startingPrice! > 0)
                        ? '₹${startingPrice!.toString()}.00'
                        : '₹159.00',
                    teamWorkFee: (startingPrice != null && startingPrice! > 0)
                        ? '₹${(startingPrice! * 7).toString()}.00'
                        : '₹1059.00',
                    reviews: reviews,
                    avgRating: avgRating,
                    totalReviews: reviewCount,
                    bottomPadding: 80 + bottomPad,
                    nextAvailableText: _nextAvailableText(),
                    onChatTap: () {
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Chat coming soon')),
                      );
                    },
                    onCallTap: () {
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Call coming soon')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: StickyBottomBookingBar(
        label: 'Schedule now',
        onPrimaryTap: () {
          if (id.isEmpty) return;
          HapticFeedback.selectionClick();
          context.push('/enquiry/new', extra: id);
        },
        onFavTap: () => _openWriteReview(
          providerId: id,
          providerName: displayName,
          profession: profession,
          avatarUrl: avatarUrl,
        ),
        favOn: false,
      ),
    );
  }
}
class _ProviderPublicPhotoTile extends StatelessWidget {
  final List<MyProviderPhotoItem> photos;
  final int index;
  const _ProviderPublicPhotoTile({required this.photos, required this.index});

  @override
  Widget build(BuildContext context) {
    final item = (index >= 0 && index < photos.length) ? photos[index] : null;
    final thumb = (item?.coverUrl ?? item?.mediaUrl ?? item?.playbackUrl ?? '')
        .toString()
        .trim();
    final url = UrlUtils.normalizeMediaUrl(thumb);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          if (photos.isEmpty) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PhotoViewerPage(
                photos: photos,
                initialIndex: index.clamp(0, photos.length - 1),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetworkThumbnailWithFallback(url: url),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withAlpha(90),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(
                  (item?.title ?? '').trim().isEmpty
                      ? 'Untitled'
                      : item!.title.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
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

class _ProviderPublicReelTile extends StatelessWidget {
  final MyProviderReelItem item;
  const _ProviderPublicReelTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final thumb = (item.coverUrl ?? item.mediaUrl ?? item.playbackUrl ?? '')
        .toString()
        .trim();
    final url = UrlUtils.normalizeMediaUrl(thumb);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          if (item.id.trim().isEmpty) return;
          context.push('/reel/${item.id}', extra: 'profile');
        },
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetworkThumbnailWithFallback(url: url),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withAlpha(90),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withAlpha(80)),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const Positioned(
                right: 10,
                top: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x7A000000),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title.trim().isEmpty ? 'Untitled' : item.title.trim(),
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
                      Icons.favorite_rounded,
                      size: 14,
                      color: Colors.white.withAlpha(220),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item.likeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ProfileEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
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

class _UserProfilePalette {
  // Premium warm system (Figma-like): beige background + elevated white surfaces + orange accent.
  static const bg = Color(0xFFF5EDE3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceTint = Color(0xFFFCF8F2);
  static const panel = Color(0xFFF2EEE7);
  static const border = Color(0xFFEAE2D7);

  static const accent = Color(0xFFF6A23A);
  static const accentSoft = Color(0xFFFFF1DF);
  static const brand = accent;

  static const rCard = 24.0;
  static const rSmall = 18.0;
  static const rPill = 999.0;

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

class _BouncyScrollBehavior extends MaterialScrollBehavior {
  const _BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class ProfileTopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final bool compact;
  final double height;

  const ProfileTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onShare,
    this.compact = false,
    this.height = 68,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = compact
        ? const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: AppColors.textPrimary,
            height: 1.0,
          )
        : const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 34,
            color: AppColors.textPrimary,
            height: 1.0,
          );
    final subtitleStyle = compact
        ? const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            height: 1.0,
          )
        : const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            height: 1.0,
          );

    return SizedBox(
      height: height,
      child: Row(
        children: [
          _TopIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _TopIconButton(
            icon: Icons.ios_share_rounded,
            onTap: onShare,
          ),
        ],
      ),
    );
  }
}

class CompactProfileHeader extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final bool verified;
  final String kmChip;
  final int experienceYears;
  final String subtitle;
  final String fromPrice;
  final String ratingText;
  final String customersText;
  final VoidCallback onBack;
  final VoidCallback onShare;

  const CompactProfileHeader({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.verified,
    required this.kmChip,
    required this.experienceYears,
    required this.subtitle,
    required this.fromPrice,
    required this.ratingText,
    required this.customersText,
    required this.onBack,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = UrlUtils.normalizeMediaUrl(avatarUrl).trim();
    final w = MediaQuery.sizeOf(context).width;
    final avatarSize = (w * 0.20).clamp(72.0, 82.0).toDouble();

    final expText =
        experienceYears > 0 ? '$experienceYears years of experience' : subtitle;
    final priceLabel =
        fromPrice.isNotEmpty ? fromPrice.replaceFirst('From ₹', '₹') : '₹159/hr';

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFDDB4), _UserProfilePalette.bg],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                _TopIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: onBack,
                ),
                const Spacer(),
                _TopIconButton(
                  icon: Icons.ios_share_rounded,
                  onTap: onShare,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: _UserProfilePalette.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: _UserProfilePalette.border),
                    boxShadow: _UserProfilePalette.softShadow,
                  ),
                  child: ClipOval(
                    child:
                        NetworkAvatarWithFallback(url: avatar, size: avatarSize),
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
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                color: AppColors.textPrimary,
                                height: 1.1,
                              ),
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              color: _UserProfilePalette.accent,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        expText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final maxChipWidth = constraints.maxWidth;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: maxChipWidth),
                                child: const ServiceChip(
                                  icon: Icons.handyman_outlined,
                                  label: 'Professional service',
                                ),
                              ),
                              if (kmChip.trim().isNotEmpty)
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: maxChipWidth),
                                  child: ServiceChip(
                                    icon: Icons.place_outlined,
                                    label: kmChip,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(width: avatarSize + 12),
                Flexible(child: _PriceBadge(label: priceLabel)),
              ],
            ),
            const SizedBox(height: 14),
            HeroStatsRow(
              experienceYears: experienceYears,
              ratingText: ratingText,
              customersText: customersText,
            ),
          ],
        ),
      ),
    );
  }
}

class HeroProfileWithStatsSection extends StatelessWidget {
  final String avatarUrl;
  final String displayName;
  final String profession;
  final int experienceYears;
  final String hourlyLabel;
  final String ratingText;
  final String customersText;
  final VoidCallback onBack;
  final VoidCallback onShare;

  const HeroProfileWithStatsSection({
    super.key,
    required this.avatarUrl,
    required this.displayName,
    required this.profession,
    required this.experienceYears,
    required this.hourlyLabel,
    required this.ratingText,
    required this.customersText,
    required this.onBack,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = UrlUtils.normalizeMediaUrl(avatarUrl).trim();
    final expLine = experienceYears > 0
        ? '$experienceYears years of experience'
        : '8 years of experience';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF4E4),
            Color(0xFFF6D9B4),
            _UserProfilePalette.bg,
          ],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
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
                  child: _TopIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: onBack,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _TopIconButton(
                    icon: Icons.ios_share_rounded,
                    onTap: onShare,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 62),
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
                        const SizedBox(height: 4),
                        Text(
                          profession,
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
                              color: _UserProfilePalette.surface,
                              borderRadius: BorderRadius.circular(36),
                              boxShadow: _UserProfilePalette.softShadow,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(34),
                              child: _NetworkImageWithFallback(
                                url: avatar,
                                fit: BoxFit.cover,
                                icon: Icons.person_rounded,
                              ),
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
                                  Icon(
                                    Icons.handyman_outlined,
                                    size: 16,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      'Professional Repair Man',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
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
                              const SizedBox(height: 4),
                              Text(
                                profession,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                expLine,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _OrangePriceBadge(label: hourlyLabel),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FloatingStatsRow(
                      experienceYears: experienceYears,
                      ratingText: ratingText,
                      customersText: customersText,
                      height: 92,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class FloatingStatsRow extends StatelessWidget {
  final int experienceYears;
  final String ratingText;
  final String customersText;
  final double height;

  const FloatingStatsRow({
    super.key,
    required this.experienceYears,
    required this.ratingText,
    required this.customersText,
    this.height = 94,
  });

  @override
  Widget build(BuildContext context) {
    final expValue = experienceYears > 0 ? '$experienceYears years' : '8 years';
    return Row(
      children: [
        Expanded(
          child: _FloatingStatCard(
            height: height,
            borderColor: _UserProfilePalette.accent,
            icon: Icons.work_outline_rounded,
            value: expValue,
            label: 'Experience',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FloatingStatCard(
            height: height,
            borderColor: const Color(0xFF7C3AED),
            icon: Icons.star_rounded,
            value: ratingText,
            label: 'Rating',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FloatingStatCard(
            height: height,
            borderColor: _UserProfilePalette.accent,
            icon: Icons.groups_2_rounded,
            value: customersText,
            label: 'Customers',
          ),
        ),
      ],
    );
  }
}

class _FloatingStatCard extends StatelessWidget {
  final double height;
  final Color borderColor;
  final IconData icon;
  final String value;
  final String label;

  const _FloatingStatCard({
    required this.height,
    required this.borderColor,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
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

class _StickyAnimatedTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final ValueNotifier<int> activeIndex;
  final ValueChanged<_ProfileSection> onTapSection;

  _StickyAnimatedTabsHeaderDelegate({
    required this.activeIndex,
    required this.onTapSection,
  });

  @override
  double get minExtent => _kPinnedTabsExtent;

  @override
  double get maxExtent => _kPinnedTabsExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
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
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, pinned ? 8 : 12, 16, pinned ? 8 : 10),
        child: Column(
          mainAxisAlignment: pinned ? MainAxisAlignment.center : MainAxisAlignment.end,
          children: [
            if (!pinned) ...[
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: _UserProfilePalette.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
            ],
            ProfileTabsBar(activeIndex: activeIndex, onTapSection: onTapSection),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

class _ProfileSheetBody extends StatelessWidget {
  final GlobalKey aboutKey;
  final GlobalKey reelsKey;
  final GlobalKey photosKey;
  final GlobalKey availabilityKey;
  final GlobalKey experienceKey;
  final GlobalKey reviewsKey;
  final String providerName;
  final String profession;
  final String avatarUrl;
  final String aboutText;
  final int experienceYears;
  final List<MyProviderReelItem> reels;
  final List<MyProviderPhotoItem> photos;
  final String hourlyFee;
  final String teamWorkFee;
  final List<_ReviewRow> reviews;
  final double avgRating;
  final int totalReviews;
  final double bottomPadding;
  final String nextAvailableText;
  final VoidCallback onChatTap;
  final VoidCallback onCallTap;

  const _ProfileSheetBody({
    required this.aboutKey,
    required this.reelsKey,
    required this.photosKey,
    required this.availabilityKey,
    required this.experienceKey,
    required this.reviewsKey,
    required this.providerName,
    required this.profession,
    required this.avatarUrl,
    required this.aboutText,
    required this.experienceYears,
    required this.reels,
    required this.photos,
    required this.hourlyFee,
    required this.teamWorkFee,
    required this.reviews,
    required this.avgRating,
    required this.totalReviews,
    required this.bottomPadding,
    required this.nextAvailableText,
    required this.onChatTap,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F7F7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(
              key: aboutKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AboutReferenceSection(
                    providerName: providerName,
                    aboutText: aboutText,
                  ),
                  const SizedBox(height: 14),
                  MiniProfileActionRow(
                    avatarUrl: avatarUrl,
                    name: providerName,
                    subtitle: profession,
                    onMessageTap: onChatTap,
                    onCallTap: onCallTap,
                  ),
                  const SizedBox(height: 14),
                  InfoCardsRow(
                    hourlyFee: hourlyFee,
                    teamWorkFee: teamWorkFee,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            KeyedSubtree(
              key: reelsKey,
              child: ReelsSection(reels: reels),
            ),
            const SizedBox(height: 18),
            KeyedSubtree(
              key: photosKey,
              child: PhotosSection(photos: photos),
            ),
            const SizedBox(height: 18),
            KeyedSubtree(
              key: availabilityKey,
              child: _AvailabilitySection(nextText: nextAvailableText),
            ),
            const SizedBox(height: 18),
            KeyedSubtree(
              key: experienceKey,
              child: _ExperienceSection(experienceYears: experienceYears),
            ),
            const SizedBox(height: 18),
            KeyedSubtree(
              key: reviewsKey,
              child: ReviewsSection(
                reviews: reviews,
                avgRating: avgRating,
                totalReviews: totalReviews,
              ),
            ),
            SizedBox(height: bottomPadding),
          ],
        ),
      ),
    );
  }
}

class ReelsSection extends StatelessWidget {
  final List<MyProviderReelItem> reels;
  const ReelsSection({super.key, required this.reels});

  @override
  Widget build(BuildContext context) {
    final showViewAll = reels.length > 5;
    final shown = showViewAll ? reels.take(5).toList(growable: false) : reels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Reels',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (showViewAll)
              _ViewAllButton(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReelsListPage(reels: reels),
                    ),
                  );
                },
              )
            else if (reels.isNotEmpty)
              Text(
                '(${reels.length})',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (reels.isEmpty)
          _PremiumCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _UserProfilePalette.surfaceTint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _UserProfilePalette.border),
                  ),
                  child: const Icon(
                    Icons.video_library_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
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
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                return SizedBox(
                  width: 132,
                  child: _ProviderPublicReelTile(item: shown[i]),
                );
              },
            ),
          ),
      ],
    );
  }
}

class PhotosSection extends StatelessWidget {
  final List<MyProviderPhotoItem> photos;
  const PhotosSection({super.key, required this.photos});

  @override
  Widget build(BuildContext context) {
    final showViewAll = photos.length > 5;
    final shown = (showViewAll && photos.length > 6)
        ? photos.take(6).toList(growable: false)
        : photos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Photos',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (showViewAll)
              _ViewAllButton(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PhotosGalleryPage(photos: photos),
                    ),
                  );
                },
              )
            else if (photos.isNotEmpty)
              Text(
                '(${photos.length})',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (photos.isEmpty)
          _PremiumCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _UserProfilePalette.surfaceTint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _UserProfilePalette.border),
                  ),
                  child: const Icon(
                    Icons.image_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
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
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.04,
            ),
            itemBuilder: (context, i) =>
                _ProviderPublicPhotoTile(photos: photos, index: i),
          ),
      ],
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewAllButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'View All',
            style: TextStyle(
              color: _UserProfilePalette.accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class ReelsListPage extends StatelessWidget {
  final List<MyProviderReelItem> reels;
  const ReelsListPage({super.key, required this.reels});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Reels (${reels.length})'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: reels.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemBuilder: (context, i) => _ProviderPublicReelTile(item: reels[i]),
      ),
    );
  }
}

class PhotosGalleryPage extends StatelessWidget {
  final List<MyProviderPhotoItem> photos;
  const PhotosGalleryPage({super.key, required this.photos});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Photos (${photos.length})'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: photos.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.02,
        ),
        itemBuilder: (context, i) => _ProviderPublicPhotoTile(
          photos: photos,
          index: i,
        ),
      ),
    );
  }
}

class PhotoViewerPage extends StatefulWidget {
  final List<MyProviderPhotoItem> photos;
  final int initialIndex;
  const PhotoViewerPage({
    super.key,
    required this.photos,
    this.initialIndex = 0,
  });

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    final safeIndex = widget.photos.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.photos.length - 1);
    _index = safeIndex;
    _pageController = PageController(initialPage: safeIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              const Center(
                child: Icon(Icons.image_outlined, color: Colors.white54, size: 44),
              ),
              Positioned(
                top: 10,
                left: 12,
                child: Material(
                  color: Colors.white.withAlpha(26),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final total = widget.photos.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                itemCount: total,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final item = widget.photos[i];
                  final url = UrlUtils.normalizeMediaUrl(
                    (item.mediaUrl ?? item.coverUrl ?? item.playbackUrl ?? '').toString(),
                  ).trim();
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: _NetworkImageWithFallback(
                          url: url,
                          fit: BoxFit.contain,
                          icon: Icons.image_outlined,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 10,
              left: 12,
              child: Material(
                color: Colors.white.withAlpha(26),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withAlpha(40)),
                ),
                child: Text(
                  '${_index + 1}/$total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: _PhotoViewerFooter(
                item: widget.photos[_index],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewerFooter extends StatelessWidget {
  final MyProviderPhotoItem item;
  const _PhotoViewerFooter({required this.item});

  @override
  Widget build(BuildContext context) {
    final title = item.title.trim().isEmpty ? 'Photo' : item.title.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.favorite_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 4),
          Text(
            '${item.likeCount}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class WriteReviewPage extends ConsumerStatefulWidget {
  final String providerId;
  final String providerName;
  final String profession;
  final String avatarUrl;
  const WriteReviewPage({
    super.key,
    required this.providerId,
    required this.providerName,
    required this.profession,
    required this.avatarUrl,
  });

  @override
  ConsumerState<WriteReviewPage> createState() => _WriteReviewPageState();
}

class _WriteReviewPageState extends ConsumerState<WriteReviewPage> {
  int _rating = 0;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _commentCtrl = TextEditingController();
  bool _submitting = false;
  final Set<String> _tags = <String>{};

  @override
  void dispose() {
    _titleCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final comment = _commentCtrl.text.trim();
    if (_rating <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
      return;
    }
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a review')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(_reviewRepoProvider).createReview(
            widget.providerId,
            _rating,
            _composeComment(comment),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review submitted!')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _composeComment(String comment) {
    final title = _titleCtrl.text.trim();
    if (_tags.isEmpty && title.isEmpty) return comment;
    final parts = <String>[];
    if (title.isNotEmpty) parts.add(title);
    if (_tags.isNotEmpty) parts.add(_tags.join(' • '));
    parts.add(comment);
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final avatar = UrlUtils.normalizeMediaUrl(widget.avatarUrl).trim();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Write Review'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PremiumCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _UserProfilePalette.surface,
                      border: Border.all(color: _UserProfilePalette.border),
                    ),
                    child: ClipOval(
                      child: _NetworkImageWithFallback(
                        url: avatar,
                        fit: BoxFit.cover,
                        icon: Icons.person_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.providerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.profession,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Rating',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            _StarRatingPicker(
              rating: _rating,
              onChanged: (v) => setState(() => _rating = v),
            ),
            const SizedBox(height: 14),
            const Text(
              'Highlights',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final tag in const [
                  'Professional',
                  'On time',
                  'Friendly',
                  'Quality work',
                  'Value',
                ])
                  _SelectableChip(
                    label: tag,
                    selected: _tags.contains(tag),
                    onTap: () {
                      setState(() {
                        if (_tags.contains(tag)) {
                          _tags.remove(tag);
                        } else {
                          _tags.add(tag);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Title (optional)',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Great experience',
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Color(0xFFF2F2F2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Review',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Write your experience...',
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Color(0xFFF2F2F2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _UserProfilePalette.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Submit review',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _UserProfilePalette.accentSoft : _UserProfilePalette.surface;
    final border = selected ? _UserProfilePalette.accent.withAlpha(140) : _UserProfilePalette.border;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _StarRatingPicker extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onChanged;
  const _StarRatingPicker({required this.rating, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        5,
        (i) {
          final selected = i < rating;
          return GestureDetector(
            onTap: () => onChanged(i + 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(4),
              child: Icon(
                selected ? Icons.star_rounded : Icons.star_border_rounded,
                color: selected ? _UserProfilePalette.accent : AppColors.textSecondary,
                size: 34,
              ),
            ),
          );
        },
      ),
    );
  }
}

class ProfileContentSheet extends StatelessWidget {
  final ValueNotifier<int> activeIndex;
  final ValueChanged<_ProfileSection> onTapSection;
  final GlobalKey aboutKey;
  final GlobalKey availabilityKey;
  final GlobalKey experienceKey;
  final GlobalKey reviewsKey;
  final String providerName;
  final String profession;
  final String avatarUrl;
  final String aboutText;
  final int experienceYears;
  final String hourlyFee;
  final String teamWorkFee;
  final List<_ReviewRow> reviews;
  final double avgRating;
  final int totalReviews;
  final double bottomPadding;
  final String nextAvailableText;
  final VoidCallback onChatTap;
  final VoidCallback onCallTap;

  const ProfileContentSheet({
    super.key,
    required this.activeIndex,
    required this.onTapSection,
    required this.aboutKey,
    required this.availabilityKey,
    required this.experienceKey,
    required this.reviewsKey,
    required this.providerName,
    required this.profession,
    required this.avatarUrl,
    required this.aboutText,
    required this.experienceYears,
    required this.hourlyFee,
    required this.teamWorkFee,
    required this.reviews,
    required this.avgRating,
    required this.totalReviews,
    required this.bottomPadding,
    required this.nextAvailableText,
    required this.onChatTap,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 22,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: _UserProfilePalette.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            ProfileTabsBar(activeIndex: activeIndex, onTapSection: onTapSection),
            const SizedBox(height: 14),
            KeyedSubtree(
              key: aboutKey,
              child: _AboutReferenceSection(
                providerName: providerName,
                aboutText: aboutText,
              ),
            ),
            const SizedBox(height: 14),
            MiniProfileActionRow(
              avatarUrl: avatarUrl,
              name: providerName,
              subtitle: profession,
              onMessageTap: onChatTap,
              onCallTap: onCallTap,
            ),
            const SizedBox(height: 14),
            InfoCardsRow(
              hourlyFee: hourlyFee,
              teamWorkFee: teamWorkFee,
            ),
            const SizedBox(height: 18),
            KeyedSubtree(
              key: availabilityKey,
              child: _AvailabilitySection(nextText: nextAvailableText),
            ),
            const SizedBox(height: 18),
            KeyedSubtree(
              key: experienceKey,
              child: _ExperienceSection(experienceYears: experienceYears),
            ),
            const SizedBox(height: 18),
            KeyedSubtree(
              key: reviewsKey,
              child: ReviewsSection(
                reviews: reviews,
                avgRating: avgRating,
                totalReviews: totalReviews,
              ),
            ),
            SizedBox(height: bottomPadding),
          ],
        ),
      ),
    );
  }
}

class ProfileTabsBar extends StatefulWidget {
  final ValueNotifier<int> activeIndex;
  final ValueChanged<_ProfileSection> onTapSection;

  const ProfileTabsBar({
    super.key,
    required this.activeIndex,
    required this.onTapSection,
  });

  @override
  State<ProfileTabsBar> createState() => _ProfileTabsBarState();
}

class _ProfileTabsBarState extends State<ProfileTabsBar> {
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _pillKeys =
      List<GlobalKey>.generate(_tabs.length, (_) => GlobalKey());
  final GlobalKey _viewportKey = GlobalKey();
  int? _lastEnsuredIndex;

  static const List<(String, _ProfileSection)> _tabs = <(String, _ProfileSection)>[
    ('About', _ProfileSection.about),
    ('Reels', _ProfileSection.reels),
    ('Photos', _ProfileSection.photos),
    ('Availability', _ProfileSection.availability),
    ('Experience', _ProfileSection.experience),
    ('Reviews', _ProfileSection.reviews),
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
      final pillOffset = pillObj.localToGlobal(Offset.zero, ancestor: viewportObj);
      final left = pillOffset.dx;
      final right = left + pillObj.size.width;

      final pad = 14.0;
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
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFEF),
            borderRadius: BorderRadius.circular(22),
          ),
          child: SingleChildScrollView(
            key: _viewportKey,
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.none,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 18, 0),
              child: Row(
                children: [
                  for (int i = 0; i < _tabs.length; i++) ...[
                    KeyedSubtree(
                      key: _pillKeys[i],
                      child: _SheetTabPill(
                        expand: false,
                        label: _tabs[i].$1,
                        selected: i == active,
                        onTap: () {
                          widget.activeIndex.value = i;
                          widget.onTapSection(_tabs[i].$2);
                        },
                      ),
                    ),
                    if (i != _tabs.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetTabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  const _SheetTabPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _UserProfilePalette.surface : Colors.transparent;
    final fg = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
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
                : null,
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: fg,
                fontSize: 12.5,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutReferenceSection extends StatelessWidget {
  final String providerName;
  final String aboutText;

  const _AboutReferenceSection({
    required this.providerName,
    required this.aboutText,
  });

  @override
  Widget build(BuildContext context) {
    final body = aboutText.trim().isEmpty
        ? 'Certified professional with proven on-site experience.'
        : aboutText.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: body),
              const TextSpan(text: ' '),
              const TextSpan(
                text: 'Read More',
                style: TextStyle(
                  color: _UserProfilePalette.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class MiniProfileActionRow extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final String subtitle;
  final VoidCallback onMessageTap;
  final VoidCallback onCallTap;

  const MiniProfileActionRow({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.subtitle,
    required this.onMessageTap,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = UrlUtils.normalizeMediaUrl(avatarUrl).trim();
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _UserProfilePalette.surface,
            border: Border.all(color: _UserProfilePalette.border),
          ),
          child: ClipOval(
            child: _NetworkImageWithFallback(
              url: avatar,
              fit: BoxFit.cover,
              icon: Icons.person_rounded,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _OutlinedCircleIconButton(
          icon: Icons.chat_bubble_outline_rounded,
          onTap: onMessageTap,
        ),
        const SizedBox(width: 10),
        _OutlinedCircleIconButton(
          icon: Icons.call_outlined,
          onTap: onCallTap,
        ),
      ],
    );
  }
}

class _OutlinedCircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _OutlinedCircleIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(color: _UserProfilePalette.accent.withAlpha(120)),
          ),
          child: Icon(
            icon,
            color: _UserProfilePalette.accent,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class InfoCardsRow extends StatelessWidget {
  final String hourlyFee;
  final String teamWorkFee;

  const InfoCardsRow({
    super.key,
    required this.hourlyFee,
    required this.teamWorkFee,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _InfoValueCard(
            icon: Icons.attach_money_rounded,
            label: 'Hourly Fee',
            value: hourlyFee,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoValueCard(
            icon: Icons.groups_2_outlined,
            label: 'Team Work',
            value: teamWorkFee,
            subtext: '(4-7 hrs)',
          ),
        ),
      ],
    );
  }
}

class _InfoValueCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtext;

  const _InfoValueCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _UserProfilePalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _UserProfilePalette.surfaceTint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _UserProfilePalette.border),
                ),
                child: Icon(icon, color: AppColors.textPrimary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (subtext != null) ...[
                const SizedBox(width: 6),
                Text(
                  subtext!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AvailabilitySection extends StatelessWidget {
  final String nextText;
  const _AvailabilitySection({required this.nextText});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Availability',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _AvailabilityCard(nextText: nextText),
      ],
    );
  }
}

class _ExperienceSection extends StatelessWidget {
  final int experienceYears;
  const _ExperienceSection({required this.experienceYears});

  @override
  Widget build(BuildContext context) {
    final label = experienceYears > 0
        ? '$experienceYears years of experience'
        : '8 years of experience';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Experience',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _PremiumCard(
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _UserProfilePalette.surfaceTint,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _UserProfilePalette.border),
                ),
                child: const Icon(
                  Icons.work_outline_rounded,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrangePriceBadge extends StatelessWidget {
  final String label;
  const _OrangePriceBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _UserProfilePalette.accent,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1.0,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _NetworkImageWithFallback extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final IconData icon;

  const _NetworkImageWithFallback({
    required this.url,
    required this.fit,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    Widget fallback() {
      return Container(
        color: _UserProfilePalette.surfaceTint,
        alignment: Alignment.center,
        child: Icon(icon, size: 46, color: Colors.black26),
      );
    }

    final normalized = url.trim();
    if (normalized.isEmpty) return fallback();
    return CachedNetworkImage(
      imageUrl: normalized,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => fallback(),
      errorWidget: (_, __, ___) => fallback(),
    );
  }
}

class ProfileHeaderInfo extends StatelessWidget {
  final String name;
  final bool verified;
  final String kmChip;
  final String expText;
  final String fromPrice;

  const ProfileHeaderInfo({
    super.key,
    required this.name,
    required this.verified,
    required this.kmChip,
    required this.expText,
    required this.fromPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ServiceChip(
                icon: Icons.handyman_outlined,
                label: 'Professional service',
              ),
              if (kmChip.isNotEmpty) ...[
                const SizedBox(width: 10),
                ServiceChip(icon: Icons.place_outlined, label: kmChip),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: AppColors.textPrimary,
                  height: 1.1,
                ),
              ),
            ),
            if (verified) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.verified,
                color: _UserProfilePalette.accent,
                size: 18,
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          expText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 14),
        if (fromPrice.isNotEmpty)
          _PriceBadge(label: fromPrice.replaceFirst('From ₹', '₹')),
      ],
    );
  }
}

class NetworkAvatarWithFallback extends StatelessWidget {
  final String url;
  final double size;
  final BorderRadius? borderRadius;

  const NetworkAvatarWithFallback({
    super.key,
    required this.url,
    required this.size,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget fallback() {
      return Container(
        width: size,
        height: size,
        color: _UserProfilePalette.surfaceTint,
        alignment: Alignment.center,
        child: Icon(
          Icons.person_rounded,
          size: size * 0.46,
          color: Colors.black26,
        ),
      );
    }

    final normalized = url.trim();
    final content = normalized.isEmpty
        ? fallback()
        : CachedNetworkImage(
            imageUrl: normalized,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, __) => fallback(),
            errorWidget: (_, __, ___) => fallback(),
          );

    final r = borderRadius;
    if (r == null) return SizedBox(width: size, height: size, child: content);
    return ClipRRect(
      borderRadius: r,
      child: SizedBox(width: size, height: size, child: content),
    );
  }
}

class NetworkThumbnailWithFallback extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const NetworkThumbnailWithFallback({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  @override
  Widget build(BuildContext context) {
    Widget fallback() {
      return Container(
        width: width,
        height: height,
        color: _UserProfilePalette.surfaceTint,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_outlined,
          size: 26,
          color: Colors.black26,
        ),
      );
    }

    final normalized = url.trim();
    final content = normalized.isEmpty
        ? fallback()
        : CachedNetworkImage(
            imageUrl: normalized,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, __) => fallback(),
            errorWidget: (_, __, ___) => fallback(),
          );

    return ClipRRect(
      borderRadius: borderRadius,
      child: content,
    );
  }
}

class StickyProfileSummaryHeader extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final String subtitle;
  final bool verified;
  final VoidCallback onChatTap;
  final VoidCallback onCallTap;

  const StickyProfileSummaryHeader({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.subtitle,
    required this.verified,
    required this.onChatTap,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = UrlUtils.normalizeMediaUrl(avatarUrl).trim();
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _UserProfilePalette.surfaceTint,
            borderRadius: BorderRadius.circular(_UserProfilePalette.rSmall),
            border: Border.all(color: _UserProfilePalette.border),
          ),
          child: NetworkAvatarWithFallback(
            url: normalized,
            size: 44,
            borderRadius: BorderRadius.circular(_UserProfilePalette.rSmall - 1),
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
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified,
                      color: _UserProfilePalette.accent,
                      size: 18,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _CircleIconButton(icon: Icons.chat_bubble_outline_rounded, onTap: onChatTap),
        const SizedBox(width: 10),
        _CircleIconButton(icon: Icons.call_outlined, onTap: onCallTap),
      ],
    );
  }
}

class ProfileTopHeader extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final String role;
  final bool verified;
  final String priceText;
  final VoidCallback onBack;
  final VoidCallback onShare;

  const ProfileTopHeader({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.role,
    required this.verified,
    required this.priceText,
    required this.onBack,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final imageSize = (w * 0.22).clamp(76.0, 92.0).toDouble();
    final normalized = UrlUtils.normalizeMediaUrl(avatarUrl).trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _TopIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: onBack,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _TopIconButton(
                    icon: Icons.ios_share_rounded,
                    onTap: onShare,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: name),
                if (verified) ...[
                  const WidgetSpan(child: SizedBox(width: 6)),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(
                      Icons.verified,
                      color: _UserProfilePalette.accent,
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24,
              color: AppColors.textPrimary,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            role,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              color: _UserProfilePalette.surface,
              shape: BoxShape.circle,
              border: Border.all(color: _UserProfilePalette.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 26,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: ClipOval(
              child: NetworkAvatarWithFallback(url: normalized, size: imageSize),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _UserProfilePalette.accent,
              borderRadius: BorderRadius.circular(_UserProfilePalette.rPill),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 20,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Text(
              priceText,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class HeroStatsRow extends StatelessWidget {
  final int experienceYears;
  final String ratingText;
  final String customersText;

  const HeroStatsRow({
    super.key,
    required this.experienceYears,
    required this.ratingText,
    required this.customersText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FigmaStatCard(
            accent: _UserProfilePalette.accent,
            icon: Icons.work_outline_rounded,
            value: experienceYears > 0 ? '$experienceYears yrs' : '8 yrs',
            label: 'Experience',
            compact: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FigmaStatCard(
            accent: const Color(0xFF7C3AED),
            icon: Icons.star_rounded,
            value: ratingText,
            label: 'Rating',
            compact: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FigmaStatCard(
            accent: _UserProfilePalette.accent,
            icon: Icons.groups_2_rounded,
            value: customersText,
            label: 'Customers',
            compact: true,
          ),
        ),
      ],
    );
  }
}

class FloatingStatsCardsRow extends StatelessWidget {
  final int experienceYears;
  final String ratingText;
  final String customersText;

  const FloatingStatsCardsRow({
    super.key,
    required this.experienceYears,
    required this.ratingText,
    required this.customersText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FigmaStatCard(
            accent: _UserProfilePalette.accent,
            icon: Icons.work_outline_rounded,
            value: experienceYears > 0 ? '$experienceYears years' : '8 years',
            label: 'Experience',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _FigmaStatCard(
            accent: const Color(0xFF7C3AED),
            icon: Icons.star_rounded,
            value: ratingText,
            label: 'Rating',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _FigmaStatCard(
            accent: _UserProfilePalette.accent,
            icon: Icons.groups_2_rounded,
            value: customersText,
            label: 'Customers',
          ),
        ),
      ],
    );
  }
}

class _FigmaStatCard extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String value;
  final String label;
  final bool compact;

  const _FigmaStatCard({
    required this.accent,
    required this.icon,
    required this.value,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 94 : 108,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        border: Border.all(color: accent.withAlpha(150), width: compact ? 1.5 : 2.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0x14000000),
            blurRadius: compact ? 18 : 25,
            offset: Offset(0, compact ? 10 : 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: compact ? 28 : 34,
              height: compact ? 28 : 34,
              decoration: BoxDecoration(
                color: accent.withAlpha(28),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: compact ? 16 : 18),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 18 : 22,
                      color: AppColors.textPrimary,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 11 : 14,
                    ),
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

class _SheetTab {
  final String label;
  final _ProfileSection section;
  const _SheetTab({required this.label, required this.section});
}

class _TabsScroller extends StatelessWidget {
  final ValueNotifier<int> activeIndex;
  final List<_SheetTab> tabs;
  final ValueChanged<_SheetTab> onTap;

  const _TabsScroller({
    super.key,
    required this.activeIndex,
    required this.tabs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: activeIndex,
      builder: (context, active, _) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _UserProfilePalette.panel,
            borderRadius: BorderRadius.circular(_UserProfilePalette.rPill),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                children: [
                  for (int i = 0; i < tabs.length; i++) ...[
                    _SegmentTabPill(
                      label: tabs[i].label,
                      selected: i == active,
                      onTap: () {
                        activeIndex.value = i;
                        onTap(tabs[i]);
                      },
                    ),
                    if (i != tabs.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SegmentTabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegmentTabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _UserProfilePalette.surface : Colors.transparent;
    final fg = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_UserProfilePalette.rPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_UserProfilePalette.rPill),
            boxShadow: selected ? _UserProfilePalette.softShadow : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: fg,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _StickyTabsDelegate extends SliverPersistentHeaderDelegate {
  final ValueNotifier<int> activeIndex;
  final ValueChanged<_ProfileSection> onTapSection;

  _StickyTabsDelegate({
    required this.activeIndex,
    required this.onTapSection,
  });

  @override
  double get minExtent => _kPinnedTabsExtent;

  @override
  double get maxExtent => _kPinnedTabsExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final tabs = <_SheetTab>[
      const _SheetTab(label: 'About', section: _ProfileSection.about),
      const _SheetTab(label: 'Availability', section: _ProfileSection.availability),
      const _SheetTab(label: 'Experience', section: _ProfileSection.experience),
      const _SheetTab(label: 'Reviews', section: _ProfileSection.reviews),
    ];

    return SizedBox(
      height: maxExtent,
      child: ColoredBox(
        color: _UserProfilePalette.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _UserProfilePalette.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: activeIndex,
                builder: (context, active, _) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 0),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _UserProfilePalette.panel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _UserProfilePalette.border),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Row(
                          children: [
                            for (int i = 0; i < tabs.length; i++) ...[
                              _SegmentTabPill(
                                label: tabs[i].label,
                                selected: i == active,
                                onTap: () {
                                  activeIndex.value = i;
                                  onTapSection(tabs[i].section);
                                },
                              ),
                              if (i != tabs.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyTabsDelegate oldDelegate) {
    return false;
  }
}

class HeaderSection extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final String subtitle;
  final bool verified;
  final String kmChip;
  final String fromPrice;
  final int experienceYears;
  final int worksCount;
  final double rating;
  final int reviewsCount;
  final int followersCount;
  final VoidCallback onBack;
  final VoidCallback onShare;

  const HeaderSection({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.subtitle,
    required this.verified,
    required this.kmChip,
    required this.fromPrice,
    required this.experienceYears,
    required this.worksCount,
    required this.rating,
    required this.reviewsCount,
    required this.followersCount,
    required this.onBack,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = UrlUtils.normalizeMediaUrl(avatarUrl).trim();
    final ratingText = rating <= 0 ? '--' : rating.toStringAsFixed(1);
    final expText =
        experienceYears > 0 ? '$experienceYears years of experience' : subtitle;

    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 360;
    final heroSize = (w * 0.52).clamp(160.0, 240.0).toDouble();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFDDB4), _UserProfilePalette.bg],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Column(
          children: [
            ProfileTopBar(
              title: name,
              subtitle: subtitle,
              onBack: onBack,
              onShare: onShare,
              compact: compact,
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: heroSize,
                  height: heroSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _UserProfilePalette.surface,
                        boxShadow: _UserProfilePalette.cardShadow,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: NetworkAvatarWithFallback(
                          url: avatar,
                          size: heroSize,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ProfileHeaderInfo(
                      name: name,
                      verified: verified,
                      kmChip: kmChip,
                      expText: expText,
                      fromPrice: fromPrice,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StatsRow(
              worksCount: worksCount,
              ratingText: ratingText,
              reviewsCount: reviewsCount,
              followersCount: followersCount,
            ),
          ],
        ),
      ),
    );
  }
}

class StatsRow extends StatelessWidget {
  final int worksCount;
  final String ratingText;
  final int reviewsCount;
  final int followersCount;

  const StatsRow({
    super.key,
    required this.worksCount,
    required this.ratingText,
    required this.reviewsCount,
    required this.followersCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            borderColor: _UserProfilePalette.accent,
            badgeColor: _UserProfilePalette.accentSoft,
            badgeIcon: Icons.auto_graph_rounded,
            value: _fmtCount(worksCount),
            label: 'Works',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            borderColor: _UserProfilePalette.accent,
            badgeColor: _UserProfilePalette.accentSoft,
            badgeIcon: Icons.star_rounded,
            value: ratingText,
            label: reviewsCount > 0 ? '${_fmtCount(reviewsCount)} reviews' : 'Rating',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            borderColor: _UserProfilePalette.accent,
            badgeColor: _UserProfilePalette.accentSoft,
            badgeIcon: Icons.groups_2_rounded,
            value: _fmtCount(followersCount),
            label: 'Followers',
          ),
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  final Color borderColor;
  final Color badgeColor;
  final IconData badgeIcon;
  final String value;
  final String label;

  const StatCard({
    super.key,
    required this.borderColor,
    required this.badgeColor,
    required this.badgeIcon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _UserProfilePalette.border),
        boxShadow: _UserProfilePalette.softShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor.withAlpha(90)),
              ),
              child: Icon(badgeIcon, color: borderColor, size: 18),
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
                      fontSize: 22,
                      color: AppColors.textPrimary,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
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

class FloatingProfileBar extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final String subtitle;
  final ValueListenable<int> activeIndex;
  final String reelsLabel;
  final String photosLabel;
  final ValueChanged<int> onTabTapIndex;
  final VoidCallback onChatTap;
  final VoidCallback onCallTap;

  const FloatingProfileBar({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.subtitle,
    required this.activeIndex,
    required this.reelsLabel,
    required this.photosLabel,
    required this.onTabTapIndex,
    required this.onChatTap,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    final url = UrlUtils.normalizeMediaUrl(avatarUrl).trim();
    return Container(
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 6,
              decoration: BoxDecoration(
                color: _UserProfilePalette.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _UserProfilePalette.surfaceTint,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _UserProfilePalette.border),
                  ),
                  child: NetworkAvatarWithFallback(
                    url: url,
                    size: 44,
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _CircleIconButton(icon: Icons.chat_bubble_outline_rounded, onTap: onChatTap),
                const SizedBox(width: 10),
                _CircleIconButton(icon: Icons.call_outlined, onTap: onCallTap),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: _UserProfilePalette.panel,
                borderRadius: BorderRadius.circular(22),
              ),
              child: ProfileTabsRow(
                activeIndex: activeIndex,
                reelsLabel: reelsLabel,
                photosLabel: photosLabel,
                onTapIndex: onTabTapIndex,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FloatingProfileCard extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final String subtitle;
  final ValueListenable<int> activeIndex;
  final String reelsLabel;
  final String photosLabel;
  final ValueChanged<int> onTabTapIndex;
  final VoidCallback onChatTap;
  final VoidCallback onCallTap;

  const FloatingProfileCard({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.subtitle,
    required this.activeIndex,
    required this.reelsLabel,
    required this.photosLabel,
    required this.onTabTapIndex,
    required this.onChatTap,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingProfileBar(
      avatarUrl: avatarUrl,
      name: name,
      subtitle: subtitle,
      activeIndex: activeIndex,
      reelsLabel: reelsLabel,
      photosLabel: photosLabel,
      onTabTapIndex: onTabTapIndex,
      onChatTap: onChatTap,
      onCallTap: onCallTap,
    );
  }
}

class ProfileTabsRow extends StatelessWidget {
  final ValueListenable<int> activeIndex;
  final String reelsLabel;
  final String photosLabel;
  final ValueChanged<int> onTapIndex;

  const ProfileTabsRow({
    super.key,
    required this.activeIndex,
    required this.reelsLabel,
    required this.photosLabel,
    required this.onTapIndex,
  });

  @override
  Widget build(BuildContext context) {
    return TabsRow(
      activeIndex: activeIndex,
      reelsLabel: reelsLabel,
      photosLabel: photosLabel,
      onTapIndex: onTapIndex,
    );
  }
}

class TabsRow extends StatelessWidget {
  final ValueListenable<int> activeIndex;
  final String reelsLabel;
  final String photosLabel;
  final ValueChanged<int> onTapIndex;

  const TabsRow({
    super.key,
    required this.activeIndex,
    required this.reelsLabel,
    required this.photosLabel,
    required this.onTapIndex,
  });

  @override
  Widget build(BuildContext context) {
    String labelForIndex(int i) {
      return switch (i) {
        0 => 'About',
        1 => reelsLabel,
        2 => photosLabel,
        _ => 'Availability',
      };
    }

    return ValueListenableBuilder<int>(
      valueListenable: activeIndex,
      builder: (context, active, _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              for (int i = 0; i < 4; i++) ...[
                _TabPill(
                  selected: i == active,
                  label: labelForIndex(i),
                  onTap: () => onTapIndex(i),
                ),
                if (i != 3) const SizedBox(width: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class AboutSection extends StatelessWidget {
  final String profileName;
  final String avatarUrl;
  final String description;
  final String chip;
  final String locationTitle;
  final bool verified;
  final VoidCallback onChatTap;
  final VoidCallback onCallTap;

  const AboutSection({
    super.key,
    required this.profileName,
    required this.avatarUrl,
    required this.description,
    required this.chip,
    required this.locationTitle,
    required this.verified,
    required this.onChatTap,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About $profileName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Overview & services',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          AboutSectionCard(description: description, chip: chip),
          const SizedBox(height: 12),
          StickyProfileSummaryHeader(
            avatarUrl: avatarUrl,
            name: profileName,
            subtitle: chip,
            verified: verified,
            onChatTap: onChatTap,
            onCallTap: onCallTap,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InfoMiniCard(
                  icon: Icons.place_outlined,
                  title: locationTitle,
                  subtitle: 'Location',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InfoMiniCard(
                  icon: Icons.verified_outlined,
                  title: verified ? 'Verified' : 'Unverified',
                  subtitle: 'Status',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ReviewsSection extends StatelessWidget {
  final List<_ReviewRow> reviews;
  final double avgRating;
  final int totalReviews;

  const ReviewsSection({
    super.key,
    required this.reviews,
    required this.avgRating,
    required this.totalReviews,
  });

  @override
  Widget build(BuildContext context) {
    final ratingText = (avgRating <= 0) ? '--' : avgRating.toStringAsFixed(1);
    final showCount = totalReviews > 0 ? totalReviews : reviews.length;
    final topN = reviews.length > 3 ? 3 : reviews.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reviews',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              ratingText,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            _StarRow(rating: avgRating <= 0 ? 0 : avgRating),
            const SizedBox(width: 10),
            Text(
              showCount > 0 ? '(${_fmtCount(showCount)})' : '(0)',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (reviews.isEmpty)
          _PremiumCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _UserProfilePalette.surfaceTint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _UserProfilePalette.border),
                  ),
                  child: const Icon(
                    Icons.reviews_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
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
          _PremiumCard(
            child: _RatingBreakdown(reviews: reviews),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < topN; i++) ...[
            _ReviewCard(row: reviews[i]),
            if (i != topN - 1) const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class AboutSectionCard extends StatelessWidget {
  final String description;
  final String chip;
  const AboutSectionCard({super.key, required this.description, required this.chip});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(_UserProfilePalette.rCard),
        boxShadow: _UserProfilePalette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          _TagChip(label: chip),
        ],
      ),
    );
  }
}

class BottomCTA extends StatelessWidget {
  final String label;
  final VoidCallback onPrimaryTap;
  final VoidCallback onFavTap;
  final bool favOn;

  const BottomCTA({
    super.key,
    required this.label,
    required this.onPrimaryTap,
    required this.onFavTap,
    required this.favOn,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _UserProfilePalette.surface,
            borderRadius: BorderRadius.circular(26),
            boxShadow: _UserProfilePalette.cardShadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: Material(
                    color: _UserProfilePalette.accent,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      onTap: onPrimaryTap,
                      borderRadius: BorderRadius.circular(22),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.calendar_month_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: _UserProfilePalette.surface,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  onTap: onFavTap,
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _UserProfilePalette.border,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.rate_review_outlined,
                      color: _UserProfilePalette.accent,
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

class StickyBottomBookingBar extends StatelessWidget {
  final String label;
  final VoidCallback onPrimaryTap;
  final VoidCallback onFavTap;
  final bool favOn;

  const StickyBottomBookingBar({
    super.key,
    required this.label,
    required this.onPrimaryTap,
    required this.onFavTap,
    required this.favOn,
  });

  @override
  Widget build(BuildContext context) {
    return BottomCTA(
      label: label,
      onPrimaryTap: onPrimaryTap,
      onFavTap: onFavTap,
      favOn: favOn,
    );
  }
}

class _FloatingProfileBarDelegate extends SliverPersistentHeaderDelegate {
  final String avatarUrl;
  final String name;
  final String subtitle;
  final ValueListenable<int> activeIndex;
  final String reelsLabel;
  final String photosLabel;
  final ValueChanged<int> onTabTapIndex;
  final VoidCallback onChatTap;
  final VoidCallback onCallTap;

  _FloatingProfileBarDelegate({
    required this.avatarUrl,
    required this.name,
    required this.subtitle,
    required this.activeIndex,
    required this.reelsLabel,
    required this.photosLabel,
    required this.onTabTapIndex,
    required this.onChatTap,
    required this.onCallTap,
  });

  @override
  double get minExtent => _kStickyProfileHeaderExtent;

  @override
  double get maxExtent => _kStickyProfileHeaderExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // A SliverPersistentHeader delegate must lay out to exactly `maxExtent`,
    // otherwise the sliver geometry can become invalid (layoutExtent > paintExtent).
    return SizedBox(
      height: maxExtent,
      child: ColoredBox(
        color: _UserProfilePalette.bg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FloatingProfileCard(
            avatarUrl: avatarUrl,
            name: name,
            subtitle: subtitle,
            activeIndex: activeIndex,
            reelsLabel: reelsLabel,
            photosLabel: photosLabel,
            onTabTapIndex: onTabTapIndex,
            onChatTap: onChatTap,
            onCallTap: onCallTap,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopIconButton({required this.icon, required this.onTap});

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
            color: _UserProfilePalette.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _UserProfilePalette.softShadow,
          ),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class ServiceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const ServiceChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(_UserProfilePalette.rPill),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  final String label;
  const _PriceBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _UserProfilePalette.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: Colors.white,
          fontSize: 14,
          height: 1.0,
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String value;
  final String label;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _UserProfilePalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor ?? AppColors.textPrimary, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _UserProfilePalette.surface,
            shape: BoxShape.circle,
            border: Border.all(color: _UserProfilePalette.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 16,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Icon(icon, color: _UserProfilePalette.accent, size: 20),
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _TabPill({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _UserProfilePalette.surface : Colors.transparent;
    final fg = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 16,
                      offset: Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: fg,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _UserProfilePalette.accentSoft,
        borderRadius: BorderRadius.circular(_UserProfilePalette.rPill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: _UserProfilePalette.accent,
          fontSize: 12,
        ),
      ),
    );
  }
}

class InfoMiniCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const InfoMiniCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(_UserProfilePalette.rCard),
        boxShadow: _UserProfilePalette.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _UserProfilePalette.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 18, color: _UserProfilePalette.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
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

class _CompactMediaSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _CompactMediaSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MediaPreviewStrip extends StatelessWidget {
  final bool loading;
  final Object? error;
  final String emptyText;
  final List<Widget> children;

  const _MediaPreviewStrip({
    required this.loading,
    required this.error,
    required this.emptyText,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Container(
        height: 140,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _UserProfilePalette.surface,
          borderRadius: BorderRadius.circular(_UserProfilePalette.rCard),
          boxShadow: _UserProfilePalette.cardShadow,
        ),
        child: Text(
          apiErrorMessage(error!),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    if (children.isEmpty) {
      return Container(
        height: 140,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _UserProfilePalette.surface,
          borderRadius: BorderRadius.circular(_UserProfilePalette.rCard),
          boxShadow: _UserProfilePalette.cardShadow,
        ),
        child: Text(
          emptyText,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => children[i],
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  final String nextText;
  const _AvailabilityCard({required this.nextText});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(_UserProfilePalette.rCard),
        boxShadow: _UserProfilePalette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nextText,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _DaySlotPill(day: 'Mon', hours: '10:00–19:00'),
              _DaySlotPill(day: 'Tue', hours: '10:00–19:00'),
              _DaySlotPill(day: 'Wed', hours: '10:00–19:00'),
              _DaySlotPill(day: 'Thu', hours: '10:00–19:00'),
              _DaySlotPill(day: 'Fri', hours: '10:00–19:00'),
              _DaySlotPill(day: 'Sat', hours: '11:00–16:00'),
              _DaySlotPill(day: 'Sun', hours: 'Closed', closed: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  final String avatarUrl;
  const _HeroBackdrop({required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final url = UrlUtils.normalizeMediaUrl(avatarUrl).trim();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFE9CF),
            _UserProfilePalette.bg,
            Color(0xFFF7F0E6),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(6),
                    Colors.transparent,
                    _UserProfilePalette.bg,
                  ],
                ),
              ),
            ),
          ),
          if (url.isNotEmpty)
            Positioned(
              left: -40,
              right: -40,
              top: -60,
              height: 420,
              child: Opacity(
                opacity: 0.18,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(60),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 160),
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 54,
        height: 5,
        decoration: BoxDecoration(
          color: _UserProfilePalette.border.withAlpha(180),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _SheetTopMiniProfile extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final String subtitle;
  final VoidCallback onChatTap;
  final VoidCallback onCallTap;

  const _SheetTopMiniProfile({
    required this.avatarUrl,
    required this.name,
    required this.subtitle,
    required this.onChatTap,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    final url = UrlUtils.normalizeMediaUrl(avatarUrl).trim();
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _UserProfilePalette.surfaceTint,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _UserProfilePalette.border),
          ),
          child: NetworkAvatarWithFallback(
            url: url,
            size: 44,
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _CircleActionIcon(icon: Icons.chat_bubble_outline_rounded, onTap: onChatTap),
        const SizedBox(width: 10),
        _CircleActionIcon(icon: Icons.call_outlined, onTap: onCallTap),
      ],
    );
  }
}

class _CircleActionIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleActionIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _UserProfilePalette.surfaceTint,
            shape: BoxShape.circle,
            border: Border.all(color: _UserProfilePalette.border),
          ),
          child: Icon(icon, color: _UserProfilePalette.accent, size: 20),
        ),
      ),
    );
  }
}

class _SectionTabSpec {
  final _ProfileSection key;
  final String label;
  final IconData icon;
  const _SectionTabSpec({
    required this.key,
    required this.label,
    required this.icon,
  });
}

class _SectionTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<_SectionTabSpec> tabs;
  final ValueListenable<int> activeIndex;
  final Color background;
  final ValueChanged<_ProfileSection> onTap;

  _SectionTabsHeaderDelegate({
    required this.tabs,
    required this.activeIndex,
    this.background = _UserProfilePalette.bg,
    required this.onTap,
  });

  static const double _extent = 56;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: maxExtent,
      child: ColoredBox(
        color: background,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _UserProfilePalette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _UserProfilePalette.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 22,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: activeIndex,
              builder: (context, active, _) {
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  itemCount: tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final spec = tabs[i];
                    final selected = i == active;
                    return _SectionTabPill(
                      label: spec.label,
                      icon: spec.icon,
                      selected: selected,
                      onTap: () => onTap(spec.key),
                    );
                  },
                );
              },
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

class _SectionTabPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SectionTabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _UserProfilePalette.accent : Colors.transparent;
    final fg = selected ? Colors.white : AppColors.textPrimary;
    final border =
        selected ? Colors.transparent : _UserProfilePalette.border.withAlpha(180);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SectionHeading({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _UserProfilePalette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _UserProfilePalette.border),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PremiumCard extends StatelessWidget {
  final Widget child;
  const _PremiumCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _UserProfilePalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ChipPill extends StatelessWidget {
  final String label;
  const _ChipPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surfaceTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _UserProfilePalette.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 11,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surfaceTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _UserProfilePalette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _UserProfilePalette.accent.withAlpha(18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _UserProfilePalette.accent.withAlpha(40)),
            ),
            child: Icon(icon, size: 18, color: _UserProfilePalette.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
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

class _DaySlotPill extends StatelessWidget {
  final String day;
  final String hours;
  final bool closed;

  const _DaySlotPill({
    required this.day,
    required this.hours,
    this.closed = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = closed ? const Color(0xFFFAF4EE) : _UserProfilePalette.surfaceTint;
    final border = closed
        ? _UserProfilePalette.border.withAlpha(140)
        : _UserProfilePalette.border;
    final fg = closed ? AppColors.textSecondary : AppColors.textPrimary;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hours,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _TimelineRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _UserProfilePalette.accent.withAlpha(18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _UserProfilePalette.accent.withAlpha(40)),
          ),
          child: Icon(icon, size: 16, color: _UserProfilePalette.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _BottomCtaBar extends StatelessWidget {
  final String label;
  final VoidCallback onPrimaryTap;
  final VoidCallback onFavTap;
  final bool favOn;

  const _BottomCtaBar({
    required this.label,
    required this.onPrimaryTap,
    required this.onFavTap,
    required this.favOn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface.withAlpha(245),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _UserProfilePalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 26,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: _UserProfilePalette.brand,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onPrimaryTap,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.event_available_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: _UserProfilePalette.surfaceTint,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onFavTap,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 52,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _UserProfilePalette.border),
                ),
                child: Icon(
                  favOn ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: favOn ? _UserProfilePalette.brand : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow {
  final String id;
  final String name;
  final String comment;
  final int rating;
  final DateTime? createdAt;

  const _ReviewRow({
    required this.id,
    required this.name,
    required this.comment,
    required this.rating,
    required this.createdAt,
  });

  factory _ReviewRow.fromJson(Map<String, dynamic> j) {
    final user = j['user'];
    final userMap = user is Map ? Map<String, dynamic>.from(user) : const <String, dynamic>{};
    final dt = DateTime.tryParse((j['createdAt'] ?? j['date'] ?? '').toString());
    return _ReviewRow(
      id: (j['id'] ?? j['_id'] ?? '').toString(),
      name: (userMap['name'] ?? j['name'] ?? 'Customer').toString(),
      comment: (j['comment'] ?? j['message'] ?? '').toString(),
      rating: (j['rating'] is num) ? (j['rating'] as num).round() : int.tryParse((j['rating'] ?? '').toString()) ?? 0,
      createdAt: dt,
    );
  }
}

class _StarRow extends StatelessWidget {
  final double rating;
  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    final full = rating.floor().clamp(0, 5);
    final half = ((rating - full) >= 0.5) && full < 5;
    return Row(
      children: [
        for (int i = 0; i < 5; i++)
          Icon(
            i < full
                ? Icons.star_rounded
                : (half && i == full ? Icons.star_half_rounded : Icons.star_border_rounded),
            color: _UserProfilePalette.accent,
            size: 18,
          ),
      ],
    );
  }
}

class _RatingBreakdown extends StatelessWidget {
  final List<_ReviewRow> reviews;
  const _RatingBreakdown({required this.reviews});

  @override
  Widget build(BuildContext context) {
    final total = reviews.length;
    if (total <= 0) return const SizedBox.shrink();
    final counts = List<int>.filled(5, 0);
    for (final r in reviews) {
      final idx = (r.rating.clamp(1, 5) - 1);
      counts[idx] += 1;
    }

    Widget row(int stars) {
      final c = counts[stars - 1];
      final p = c / total;
      return Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              '$stars★',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: p,
                minHeight: 8,
                backgroundColor: _UserProfilePalette.border.withAlpha(120),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(_UserProfilePalette.accent),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text(
              '$c',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        for (int s = 5; s >= 1; s--) ...[
          row(s),
          if (s != 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final _ReviewRow row;
  const _ReviewCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(row.name);
    final date = row.createdAt == null
        ? ''
        : '${row.createdAt!.day.toString().padLeft(2, '0')}-${row.createdAt!.month.toString().padLeft(2, '0')}-${row.createdAt!.year}';

    return _PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _UserProfilePalette.accent.withAlpha(16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _UserProfilePalette.border),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _StarRow(rating: row.rating.toDouble()),
                  ],
                ),
              ),
              if (date.isNotEmpty)
                Text(
                  date,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          if (row.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              row.comment.trim(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
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
    final normalized = UrlUtils.normalizeMediaUrl(avatarUrl).trim();
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _UserProfilePalette.border, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: normalized.isEmpty
            ? _AvatarFallback(text: fallbackText)
            : CachedNetworkImage(
                imageUrl: normalized,
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
      color: _UserProfilePalette.accent.withAlpha(12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_rounded,
              color: _UserProfilePalette.accent.withAlpha(170),
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

class _ProfileHeader extends StatelessWidget {
  final String heroTag;
  final String avatarUrl;
  final String displayName;
  final String username;
  final bool verified;
  final bool isFollowed;
  final int posts;
  final int followers;
  final int following;
  final int likes;
  final int experienceYears;
  final double avgRating;
  final int totalReviews;
  final int serviceRadiusKm;
  final int? startingPrice;
  final VoidCallback onFollowTap;
  final VoidCallback onMessageTap;
  final double titleProgress;

  const _ProfileHeader({
    required this.heroTag,
    required this.avatarUrl,
    required this.displayName,
    required this.username,
    required this.verified,
    required this.isFollowed,
    required this.posts,
    required this.followers,
    required this.following,
    required this.likes,
    required this.experienceYears,
    required this.avgRating,
    required this.totalReviews,
    required this.serviceRadiusKm,
    required this.startingPrice,
    required this.onFollowTap,
    required this.onMessageTap,
    required this.titleProgress,
  });

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeIn.transform(
      ((titleProgress - 0.15) / 0.50).clamp(0.0, 1.0),
    );
    final price = startingPrice ?? 0;
    final showPrice = price > 0;
    final ratingText = (avgRating <= 0) ? '--' : avgRating.toStringAsFixed(1);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFFE9CF),
              _UserProfilePalette.bg,
              _UserProfilePalette.surfaceTint,
            ],
          ),
          border: Border.all(color: _UserProfilePalette.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 24,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _UserProfilePalette.accent.withAlpha(34),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Hero(
                        tag: heroTag,
                        child: _AvatarSquare(
                          avatarUrl: avatarUrl,
                          fallbackText: _initials(displayName),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Opacity(
                              opacity: 1 - t,
                              child: Transform.translate(
                                offset: Offset(0, -14 * t),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18,
                                          color: AppColors.textPrimary,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                    if (verified) ...[
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.verified,
                                        color: _UserProfilePalette.brand,
                                        size: 18,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                const _MiniBadge(
                                  icon: Icons.handyman_outlined,
                                  label: 'Professional service',
                                ),
                                if (experienceYears > 0)
                                  _MiniBadge(
                                    icon: Icons.work_outline_rounded,
                                    label: '$experienceYears yrs exp',
                                  ),
                                if (serviceRadiusKm > 0)
                                  _MiniBadge(
                                    icon: Icons.place_outlined,
                                    label: '$serviceRadiusKm km',
                                  ),
                                if (showPrice)
                                  _MiniBadge(
                                    icon: Icons.payments_outlined,
                                    label: 'From â‚¹$price',
                                    emphasized: true,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.auto_graph_rounded,
                          title: _fmtCount(posts),
                          subtitle: 'Works',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.star_rounded,
                          title: ratingText,
                          subtitle: totalReviews > 0
                              ? '${_fmtCount(totalReviews)} reviews'
                              : 'Rating',
                          iconColor: _UserProfilePalette.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.groups_2_outlined,
                          title: _fmtCount(followers),
                          subtitle: 'Followers',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _PillButton(
                          label: isFollowed ? 'Following' : 'Follow',
                          filled: !isFollowed,
                          block: true,
                          onTap: onFollowTap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PillButton(
                          label: 'Message',
                          block: true,
                          onTap: onMessageTap,
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
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasized;

  const _MiniBadge({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = emphasized
        ? _UserProfilePalette.accent.withAlpha(26)
        : _UserProfilePalette.surface.withAlpha(230);
    final border = emphasized
        ? _UserProfilePalette.accent.withAlpha(60)
        : _UserProfilePalette.border;
    final fg = emphasized ? _UserProfilePalette.accent : AppColors.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = iconColor ?? AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _UserProfilePalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final bool block;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.block = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg =
        filled ? _UserProfilePalette.accent : _UserProfilePalette.surface;
    final fg = filled ? Colors.white : AppColors.textPrimary;
    final border = filled ? Colors.transparent : _UserProfilePalette.border;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: block ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

String _formatHandle(String userId) {
  final raw = userId.trim();
  if (raw.isEmpty) return '@user';
  final cleaned = raw.replaceAll(RegExp(r'\\s+'), '');
  if (cleaned.length <= 18) return '@$cleaned';
  return '@${cleaned.substring(0, 8)}Ã¢â‚¬Â¦${cleaned.substring(cleaned.length - 6)}';
}

String _fmtCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
  return '$n';
}
