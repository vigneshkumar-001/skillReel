import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/url_utils.dart';

typedef UserProfileSeed = ({
  String name,
  String? avatarUrl,
  bool verified,
  String heroTag,
  bool isFollowed,
});

class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  final UserProfileSeed? seed;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.seed,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  late bool _isFollowed = widget.seed?.isFollowed ?? false;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _titleProgress = ValueNotifier<double>(0);

  static const double _titleThreshold = 86;

  Future<void> _toggleFollow() async {
    HapticFeedback.selectionClick();
    setState(() => _isFollowed = !_isFollowed);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final next = (_scrollController.offset / _titleThreshold).clamp(0.0, 1.0);
    _titleProgress.value = next;
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
    final seed = widget.seed;
    final displayName = (seed?.name ?? 'Profile').trim().isEmpty
        ? 'Profile'
        : seed!.name.trim();

    final avatarUrl = UrlUtils.normalizeMediaUrl(seed?.avatarUrl);
    final heroTag = seed?.heroTag ?? 'user_profile_avatar_${widget.userId}';
    final username = _formatHandle(widget.userId);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _UserProfilePalette.bg,
        body: ScrollConfiguration(
          behavior: const _BouncyScrollBehavior(),
          child: NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                pinned: true,
                expandedHeight: kToolbarHeight,
                clipBehavior: Clip.none,
                backgroundColor: _UserProfilePalette.bg,
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
                        color: _UserProfilePalette.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _UserProfilePalette.border.withAlpha(140),
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
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (seed?.verified == true) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ],
                        ],
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
                          color: _UserProfilePalette.border.withAlpha(120),
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
                            padding: const EdgeInsets.only(right: 6),
                            child: _AppBarPillButton(
                              label: _isFollowed ? 'Following' : 'Follow',
                              filled: !_isFollowed,
                              onTap: _toggleFollow,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('More options coming soon')),
                      );
                    },
                    tooltip: 'More',
                  ),
                  const SizedBox(width: 6),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _titleProgress,
                    builder: (context, progress, _) {
                      return _ProfileHeader(
                        heroTag: heroTag,
                        avatarUrl: avatarUrl,
                        displayName: displayName,
                        username: username,
                        verified: seed?.verified == true,
                        isFollowed: _isFollowed,
                        posts: _seededCount(widget.userId, 2100, 4800),
                        followers: _seededCount(widget.userId, 180000, 980000),
                        following: _seededCount(widget.userId, 120, 4200),
                        likes: _seededCount(widget.userId, 230000, 2900000),
                        onFollowTap: _toggleFollow,
                        onMessageTap: () {
                          HapticFeedback.selectionClick();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Message coming soon')),
                          );
                        },
                        titleProgress: progress,
                      );
                    },
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabHeaderDelegate(
                  const TabBar(
                    indicatorColor: _UserProfilePalette.accent,
                    dividerColor: Colors.transparent,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    tabs: [
                      Tab(
                        icon: Icon(Icons.photo_library_outlined),
                        text: 'Photos',
                      ),
                      Tab(
                        icon: Icon(Icons.videocam_outlined),
                        text: 'Reels',
                      ),
                      Tab(
                        icon: Icon(Icons.bookmark_border_rounded),
                        text: 'Saved reels',
                      ),
                    ],
                  ),
                ),
              ),
            ],
            body: const TabBarView(
              children: [
                _MediaGrid(items: _demoTiles, style: _GridStyle.photos),
                _MediaGrid(items: _demoTiles, style: _GridStyle.reels),
                _MediaGrid(items: _demoTiles, style: _GridStyle.saved),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppBarPillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _AppBarPillButton({
    required this.label,
    required this.onTap,
    this.filled = true,
  });

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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: filled ? AppColors.primary : _UserProfilePalette.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: filled
                  ? AppColors.primary.withAlpha(30)
                  : _UserProfilePalette.border.withAlpha(160),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: filled ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserProfilePalette {
  static const bg = AppColors.surface; // pure white
  static const surface = AppColors.bg; // subtle contrast blocks
  static const border = AppColors.border;

  static const accent = AppColors.primary;
}

class _BouncyScrollBehavior extends MaterialScrollBehavior {
  const _BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabHeaderDelegate(this.tabBar);

  static const double _extent = 62;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      height: maxExtent,
      child: ColoredBox(
        color: _UserProfilePalette.bg,
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
                  blurRadius: 18,
                  offset: Offset(0, 10),
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
  bool shouldRebuild(covariant _TabHeaderDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
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
        color: _UserProfilePalette.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _UserProfilePalette.border, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
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
      color: Color(0x1A6C5CE7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_rounded,
              color: AppColors.primary.withAlpha(180),
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary.withAlpha(120),
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
    required this.onFollowTap,
    required this.onMessageTap,
    required this.titleProgress,
  });

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeIn.transform(
      ((titleProgress - 0.15) / 0.50).clamp(0.0, 1.0),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _UserProfilePalette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _UserProfilePalette.border),
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
                          offset: Offset(0, -16 * t),
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
                                  color: AppColors.primary,
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
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
            const SizedBox(height: 12),
            _StatStrip(
              items: [
                _StatItem(label: 'Posts', value: _fmtCount(posts)),
                _StatItem(label: 'Followers', value: _fmtCount(followers)),
                _StatItem(label: 'Following', value: _fmtCount(following)),
                _StatItem(label: 'Likes', value: _fmtCount(likes)),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: _UserProfilePalette.border.withAlpha(120),
            ),
            const SizedBox(height: 12),
            const _BioLines(
              lines: [
                'Entrepreneur | Investor | Visionary',
                'Founder • Building the future',
                'Visit our website',
              ],
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: _UserProfilePalette.border.withAlpha(120),
            ),
            const SizedBox(height: 10),
            const _WebsiteRow(
              url: 'https://skilreel.app',
            ),
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
              color: _UserProfilePalette.accent,
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

class _StatItem {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});
}

class _StatStrip extends StatelessWidget {
  final List<_StatItem> items;
  const _StatStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  items[i].value,
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
                  items[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (i != items.length - 1) ...[
            Container(
              width: 1,
              height: 34,
              color: _UserProfilePalette.border.withAlpha(160),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ],
    );
  }
}

class _BioLines extends StatelessWidget {
  final List<String> lines;
  const _BioLines({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < lines.length; i++) ...[
          Row(
            children: [
              Icon(
                i == 0
                    ? Icons.bolt_rounded
                    : (i == 1 ? Icons.star_rounded : Icons.link_rounded),
                size: 16,
                color: _UserProfilePalette.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lines[i],
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (i != lines.length - 1) ...[
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: _UserProfilePalette.border.withAlpha(120),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

enum _GridStyle { photos, reels, saved }

class _MediaGrid extends StatelessWidget {
  final List<_DemoTile> items;
  final _GridStyle style;

  const _MediaGrid({required this.items, required this.style});

  int get _crossAxisCount => 2;

  double get _childAspectRatio {
    switch (style) {
      case _GridStyle.photos:
      case _GridStyle.saved:
        return 0.62;
      case _GridStyle.reels:
        return 0.62;
    }
  }

  double get _radius {
    switch (style) {
      case _GridStyle.photos:
      case _GridStyle.saved:
        return 26;
      case _GridStyle.reels:
        return 26;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _UserProfilePalette.bg,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: _childAspectRatio,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _DemoTileCard(
          item: items[i],
          radius: _radius,
          showViewsPill: style == _GridStyle.reels,
        ),
      ),
    );
  }
}

class _DemoTileCard extends StatelessWidget {
  final _DemoTile item;
  final double radius;
  final bool showViewsPill;
  const _DemoTileCard({
    required this.item,
    required this.radius,
    required this.showViewsPill,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(radius),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: item.gradient,
                    ),
                  ),
                ),
              ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!showViewsPill)
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    if (showViewsPill)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(110),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
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

class _DemoTile {
  final String title;
  final String subtitle;
  final List<Color> gradient;
  const _DemoTile({
    required this.title,
    required this.subtitle,
    required this.gradient,
  });
}

const _demoTiles = <_DemoTile>[
  _DemoTile(
    title: 'Road trip',
    subtitle: '1.2M views',
    gradient: [Color(0xFFF59E0B), Color(0xFFEF4444)],
  ),
  _DemoTile(
    title: 'Mountains',
    subtitle: '12M views',
    gradient: [Color(0xFF22C55E), Color(0xFF3B82F6)],
  ),
  _DemoTile(
    title: 'Aviation',
    subtitle: '8.8M views',
    gradient: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
  ),
  _DemoTile(
    title: 'Portrait',
    subtitle: '980K views',
    gradient: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
  ),
  _DemoTile(
    title: 'City life',
    subtitle: '2.4M views',
    gradient: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
  ),
  _DemoTile(
    title: 'Minimal',
    subtitle: '620K views',
    gradient: [Color(0xFF10B981), Color(0xFFF59E0B)],
  ),
];

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
  return '@${cleaned.substring(0, 8)}…${cleaned.substring(cleaned.length - 6)}';
}

String _fmtCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
  return '$n';
}

int _seededCount(String seed, int min, int max) {
  final s = seed.trim();
  var hash = 2166136261;
  for (final codeUnit in s.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  final span = (max - min).clamp(1, 1 << 30);
  return min + (hash % span);
}
