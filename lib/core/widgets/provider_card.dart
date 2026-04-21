import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../features/providers_module/models/provider_model.dart';
import '../theme/app_colors.dart';
import '../utils/url_utils.dart';

class ProviderCard extends StatelessWidget {
  final ProviderModel provider;
  final VoidCallback onTap;
  final bool compact;

  const ProviderCard({
    super.key,
    required this.provider,
    required this.onTap,
    this.compact = false,
  });
  const ProviderCard.compact({
    super.key,
    required this.provider,
    required this.onTap,
  }) : compact = true;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = UrlUtils.normalizeMediaUrl(provider.avatar);
    final subtitle = provider.skills.isNotEmpty
        ? provider.skills.join(', ')
        : [
            if ((provider.city ?? '').trim().isNotEmpty) provider.city!.trim(),
            if ((provider.state ?? '').trim().isNotEmpty)
              provider.state!.trim(),
          ].join(', ').trim();

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: CachedNetworkImage(
                  imageUrl: avatarUrl,
                  width: compact ? 46 : 56,
                  height: compact ? 46 : 56,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: compact ? 46 : 56,
                    height: compact ? 46 : 56,
                    color: AppColors.primary.withOpacity(0.10),
                    child: const Icon(Icons.person, color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            provider.displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? 14 : 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (provider.isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            color: AppColors.primary,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (!compact) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.star,
                              size: 14, color: AppColors.star),
                          const SizedBox(width: 3),
                          Text(
                            provider.averageRating.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${provider.followerCount} followers',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
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
