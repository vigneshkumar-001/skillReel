import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../features/reels/models/reel_model.dart';
import '../theme/app_colors.dart';
import '../utils/url_utils.dart';

class ReelCard extends StatelessWidget {
  final ReelModel reel;
  final VoidCallback onTap;
  final VoidCallback? onLike;
  final VoidCallback? onSave;

  const ReelCard({
    super.key,
    required this.reel,
    required this.onTap,
    this.onLike,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrlRaw =
        reel.thumbnailUrl.isNotEmpty ? reel.thumbnailUrl : reel.mediaUrl;
    final imageUrl = UrlUtils.normalizeMediaUrl(imageUrlRaw);

    final location = [
      if ((reel.providerCity ?? '').trim().isNotEmpty)
        reel.providerCity!.trim(),
      if ((reel.providerState ?? '').trim().isNotEmpty)
        reel.providerState!.trim(),
    ].join(', ').trim();

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  children: [
                    if (imageUrl.isEmpty)
                      Container(
                        height: 210,
                        width: double.infinity,
                        color: AppColors.border,
                        child: const Icon(
                          Icons.image_outlined,
                          color: AppColors.textSecondary,
                          size: 36,
                        ),
                      )
                    else
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 210,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          height: 210,
                          color: AppColors.border,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 210,
                          color: AppColors.border,
                          child: const Icon(Icons.broken_image,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    if (reel.isBoosted)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Boosted',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reel.providerName ?? 'Provider',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (location.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  location,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (reel.price != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.25),
                              ),
                            ),
                            child: Text(
                              '₹${reel.price}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      reel.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((reel.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        reel.description!.trim(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (reel.skillTags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: reel.skillTags
                            .take(3)
                            .map(
                              (t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.bg,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  t,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        InkWell(
                          onTap: onLike,
                          borderRadius: BorderRadius.circular(999),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.favorite_border,
                                size: 18, color: AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${reel.likes}',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 14),
                        const Icon(Icons.comment_outlined,
                            size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${reel.comments}',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 14),
                        const Icon(Icons.bookmark_border,
                            size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${reel.saves}',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                        const Spacer(),
                        if (reel.viewCount > 0) ...[
                          const Icon(Icons.visibility_outlined,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '${reel.viewCount}',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 10),
                        ],
                        InkWell(
                          onTap: onSave,
                          borderRadius: BorderRadius.circular(999),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.more_horiz,
                                size: 20, color: AppColors.textSecondary),
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
      ),
    );
  }
}
