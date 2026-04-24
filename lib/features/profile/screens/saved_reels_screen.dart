import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/my_saved_reels_provider.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/network/models/my_saved_reels_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/url_utils.dart';

class SavedReelsScreen extends ConsumerWidget {
  const SavedReelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async =
        ref.watch(mySavedReelsProvider(const MySavedReelsQuery(limit: 12)));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Saved reels'),
      ),
      body: async.when(
        loading: () =>
            const Center(child: CupertinoActivityIndicator(radius: 14)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              apiErrorMessage(e),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        data: (res) {
          final items = res.data;
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing saved yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }

          return GridView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
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
                            fadeInDuration: const Duration(milliseconds: 120),
                            placeholder: (context, url) =>
                                const SizedBox.shrink(),
                            errorWidget: (context, url, error) => const Center(
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
                        color: AppColors.accent,
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
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withAlpha(22)),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
