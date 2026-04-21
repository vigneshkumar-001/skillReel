import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/url_utils.dart';
import '../../../core/widgets/app_button.dart';
import '../providers/provider_state_provider.dart';

class ProviderProfileScreen extends ConsumerStatefulWidget {
  final String providerId;
  const ProviderProfileScreen({super.key, required this.providerId});

  @override
  ConsumerState<ProviderProfileScreen> createState() =>
      _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends ConsumerState<ProviderProfileScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _titleProgress = ValueNotifier<double>(0);

  static const double _titleThreshold = 92;

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
    final providerId = widget.providerId;
    final provAsync = ref.watch(providerDetailProvider(providerId));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: provAsync.when(
        loading: () => const CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Text('Provider'),
            ),
            SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        error: (e, _) => CustomScrollView(
          slivers: [
            const SliverAppBar(
              pinned: true,
              title: Text('Provider'),
            ),
            SliverFillRemaining(
              child: Center(child: Text(apiErrorMessage(e))),
            ),
          ],
        ),
        data: (p) {
          final avatarUrl = UrlUtils.normalizeMediaUrl(p.avatar);
          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: IconButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).maybePop();
                    },
                    icon: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.border.withAlpha(140),
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
                title: ValueListenableBuilder<double>(
                  valueListenable: _titleProgress,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (p.isVerified) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ],
                    ],
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
                          color: AppColors.border.withAlpha(120),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  color: AppColors.surface,
                  child: Column(
                    children: [
                      Hero(
                        tag: 'provider_profile_avatar_$providerId',
                        child: CircleAvatar(
                          radius: 44,
                          foregroundImage: avatarUrl.isNotEmpty
                              ? NetworkImage(avatarUrl)
                              : null,
                          onForegroundImageError: (_, __) {},
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.1),
                          child: avatarUrl.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 44,
                                  color: AppColors.primary,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<double>(
                        valueListenable: _titleProgress,
                        builder: (context, progress, _) {
                          final t = Curves.easeIn.transform(
                            ((progress - 0.15) / 0.50).clamp(0.0, 1.0),
                          );
                          return Opacity(
                            opacity: 1 - t,
                            child: Transform.translate(
                              offset: Offset(0, -16 * t),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    p.displayName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (p.isVerified) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.verified,
                                      color: AppColors.primary,
                                      size: 18,
                                    ),
                                  ]
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.skills.join(' Â· '),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Stat(
                            label: 'Rating',
                            value: p.averageRating.toStringAsFixed(1),
                          ),
                          _Stat(label: 'Reviews', value: '${p.totalReviews}'),
                          _Stat(
                            label: 'Followers',
                            value: '${p.followerCount}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: 'Follow',
                              onTap: () => ref
                                  .read(providerActionProvider)
                                  .follow(providerId),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppButton(
                              label: 'Enquire',
                              outlined: true,
                              onTap: () => context.push(
                                '/enquiry/new',
                                extra: providerId,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (p.bio != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(p.bio!),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.rate_review_outlined),
                    title: const Text('Leave a review'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/review/new', extra: providerId),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
