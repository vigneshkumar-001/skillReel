import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/url_utils.dart';
import '../../../core/widgets/provider_card.dart';
import '../../providers_module/models/provider_model.dart';
import '../../reels/models/reel_model.dart';
import '../models/search_category_model.dart';
import '../providers/search_provider.dart';

class _SearchPalette {
  // Match the warm premium system used in `profile_screen.dart`.
  static const bg = Color(0xFFFBF7F1);
  static const surfaceTint = Color(0xFFFCF8F2);
  static const border = Color(0xFFEAE2D7);
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _didResetOnOpen = false;

  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    ref.invalidate(searchCategoriesProvider);
    ref.invalidate(searchResultsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  void _search(String q) {
    ref.read(searchQueryProvider.notifier).state = q.trim();
  }

  void _setQuery(String q) {
    final next = q.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).state = next;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didResetOnOpen) return;
      _didResetOnOpen = true;
      _debounce?.cancel();
      _ctrl.clear();
      ref.read(searchQueryProvider.notifier).state = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(searchQueryProvider).trim();
    final bottomPad = MediaQuery.of(context).padding.bottom + 120;

    return Scaffold(
      backgroundColor: _SearchPalette.bg,
      body: RefreshIndicator.adaptive(
        onRefresh: _refresh,
        notificationPredicate: (n) => n.depth == 0,
        child: ScrollConfiguration(
          behavior: const _BouncyScrollBehavior(),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: _SearchPalette.bg,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                titleSpacing: 16,
                title: const Text(
                  'Search',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(66),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _SearchBar(
                      controller: _ctrl,
                      onChanged: _setQuery,
                      onSubmitted: _search,
                      onClear: () {
                        HapticFeedback.selectionClick();
                        _debounce?.cancel();
                        _ctrl.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                ),
              ),
              if (q.isEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                _ExploreCategoriesSliver(bottomPad: bottomPad),
              ] else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: _SectionHeader(
                      title: 'Results',
                      subtitle: 'for "$q"',
                    ),
                  ),
                ),
                _SearchResultsSliver(query: q, bottomPad: bottomPad),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChanged);
  bool _focused = false;

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shadowColor =
        _focused ? AppColors.primary.withAlpha(12) : Colors.black.withAlpha(10);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: _focused ? 22 : 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.search_rounded,
              color: _focused ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                focusNode: _focusNode,
                controller: widget.controller,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                onTapOutside: (_) => _focusNode.unfocus(),
                textAlignVertical: TextAlignVertical.center,
                cursorColor: AppColors.primary,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.1,
                ),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withAlpha(180),
                    fontWeight: FontWeight.w700,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final enabled = value.text.trim().isNotEmpty;
                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: enabled ? 1 : 0.35,
                  child: IconButton(
                    onPressed: enabled ? widget.onClear : null,
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Clear',
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _ExploreCategoriesSliver extends ConsumerWidget {
  final double bottomPad;
  const _ExploreCategoriesSliver({required this.bottomPad});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(searchCategoriesProvider);

    return catsAsync.when(
      loading: () => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PopularHeaderRow(),
              const SizedBox(height: 14),
              const _PopularGridSkeleton(count: 6),
              SizedBox(height: bottomPad),
            ],
          ),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPad),
          child: _InlineState(
            icon: Icons.wifi_off_rounded,
            title: 'Couldn\'t load categories',
            subtitle: apiErrorMessage(e),
          ),
        ),
      ),
      data: (cats) {
        final categories =
            cats.where((c) => c.category.trim().isNotEmpty).toList();

        final popular = List<SearchCategoryModel>.from(categories)
          ..sort((a, b) => b.skills.compareTo(a.skills));
        final popularShown = popular.take(6).toList(growable: false);

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (categories.isEmpty)
                  const _InlineState(
                    icon: Icons.category_outlined,
                    title: 'No categories',
                    subtitle: 'Try again in a moment.',
                  )
                else ...[
                  const _PopularHeaderRow(),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: popularShown.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 18,
                      childAspectRatio: 0.76,
                    ),
                    itemBuilder: (context, i) {
                      final c = popularShown[i];
                      return _PopularCategoryCard(
                        category: c,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.push(
                            '/search/category/${Uri.encodeComponent(c.category.trim())}',
                            extra: c.category.trim(),
                          );
                        },
                      );
                    },
                  ),
                ],
                SizedBox(height: bottomPad),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PopularHeaderRow extends StatelessWidget {
  const _PopularHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Popular',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 38,
              color: AppColors.textPrimary,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}

class _PopularGridSkeleton extends StatelessWidget {
  final int count;
  const _PopularGridSkeleton({required this.count});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
        childAspectRatio: 0.76,
      ),
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF5),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _SearchPalette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Center(child: CupertinoActivityIndicator(radius: 12)),
      ),
    );
  }
}

class _PopularCategoryCard extends StatelessWidget {
  final SearchCategoryModel category;
  final VoidCallback onTap;

  const _PopularCategoryCard({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final img = UrlUtils.normalizeMediaUrl(category.imageUrl ?? '').trim();
    final title = category.category.trim().isEmpty
        ? 'Category'
        : category.category.trim();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: img.isEmpty
                  ? ColoredBox(
                      color: _SearchPalette.surfaceTint,
                      child: Center(
                        child: Icon(
                          Icons.category_outlined,
                          size: 64,
                          color: AppColors.textSecondary.withAlpha(170),
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: img,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
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
                      Colors.black.withAlpha(150),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultsSliver extends ConsumerWidget {
  final String query;
  final double bottomPad;
  const _SearchResultsSliver({
    required this.query,
    required this.bottomPad,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);

    return resultsAsync.when(
      loading: () => SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
          child: const Center(child: CupertinoActivityIndicator(radius: 14)),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
          child: _InlineState(
            icon: Icons.search_off_rounded,
            title: 'Search failed',
            subtitle: apiErrorMessage(e),
          ),
        ),
      ),
      data: (results) {
        final providers = results?.providers ?? const <ProviderModel>[];
        final reels = results?.reels ?? const <ReelModel>[];

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (providers.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const _MiniHeader(title: 'Providers'),
                  const SizedBox(height: 10),
                  for (final p in providers.take(10)) ...[
                    ProviderCard.compact(
                      provider: p,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (p.isCurrentProvider) {
                          context.push('/profile/view');
                          return;
                        }
                        context.push('/user/${p.id}');
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (reels.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const _MiniHeader(title: 'Reels'),
                  const SizedBox(height: 10),
                  _ReelsGrid(
                    reels: reels,
                    onTapReel: (reel) {
                      HapticFeedback.selectionClick();
                      final feedType =
                          'search_q:${Uri.encodeComponent(query.trim())}';
                      context.push('/reel/${reel.id}', extra: feedType);
                    },
                  ),
                ],
                if (providers.isEmpty && reels.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: _InlineState(
                      icon: Icons.inbox_outlined,
                      title: 'No results',
                      subtitle: 'Try a different keyword.',
                    ),
                  ),
                SizedBox(height: bottomPad),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InlineState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InlineState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppColors.primary),
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
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
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

class _ReelsGrid extends StatelessWidget {
  final List<ReelModel> reels;
  final void Function(ReelModel reel) onTapReel;

  const _ReelsGrid({
    required this.reels,
    required this.onTapReel,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: reels.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.63,
      ),
      itemBuilder: (context, i) => _ReelThumbTile(
        reel: reels[i],
        onTap: () => onTapReel(reels[i]),
      ),
    );
  }
}

class _ReelThumbTile extends StatelessWidget {
  final ReelModel reel;
  final VoidCallback onTap;

  const _ReelThumbTile({required this.reel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb =
        (reel.thumbnailUrl.isNotEmpty ? reel.thumbnailUrl : reel.mediaUrl)
            .trim();
    final url = UrlUtils.normalizeMediaUrl(thumb);
    final showPlaceholder = url.isEmpty || _looksLikeVideoUrl(url);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(8),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF111827).withAlpha(230),
                          AppColors.primary.withAlpha(22),
                          AppColors.secondary.withAlpha(18),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!showPlaceholder)
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  )
                else
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white70,
                      size: 42,
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withAlpha(60),
                          Colors.transparent,
                          Colors.black.withAlpha(150),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(top: 8, left: 8, child: _PlayPill()),
                if (reel.isLiked || reel.isSaved)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (reel.isLiked)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.favorite_rounded,
                              size: 16,
                              color: AppColors.accent,
                            ),
                          ),
                        if (reel.isSaved)
                          const Icon(
                            Icons.bookmark_rounded,
                            size: 16,
                            color: Color(0xFFFFD166),
                          ),
                      ],
                    ),
                  ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Text(
                    reel.title.trim().isEmpty ? 'Untitled' : reel.title.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _looksLikeVideoUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('.mp4') ||
        u.contains('.m3u8') ||
        u.contains('.mov') ||
        u.contains('.webm') ||
        u.contains('.mkv');
  }
}

class _PlayPill extends StatelessWidget {
  const _PlayPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(90),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'Reel',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniHeader extends StatelessWidget {
  final String title;
  const _MiniHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
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
