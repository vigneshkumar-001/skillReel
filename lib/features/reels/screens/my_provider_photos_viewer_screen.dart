import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../profile/providers/my_provider_photos_provider.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/network/models/my_provider_photos_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/url_utils.dart';

class MyProviderPhotosViewerScreen extends ConsumerStatefulWidget {
  final String? initialPhotoId;

  const MyProviderPhotosViewerScreen({super.key, this.initialPhotoId});

  @override
  ConsumerState<MyProviderPhotosViewerScreen> createState() =>
      _MyProviderPhotosViewerScreenState();
}

class _MyProviderPhotosViewerScreenState
    extends ConsumerState<MyProviderPhotosViewerScreen> {
  PageController? _controller;
  int _index = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      myProviderPhotosProvider(const MyProviderPhotosQuery(limit: 12)),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: async.when(
        loading: () => const Center(
          child: CupertinoActivityIndicator(radius: 14),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              apiErrorMessage(e),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        data: (res) {
          final items = res.data;
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'No photos yet',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          }

          final initialId = (widget.initialPhotoId ?? '').trim();
          final initialIndex = initialId.isEmpty
              ? 0
              : items.indexWhere((p) => p.id == initialId);
          final target = (initialIndex >= 0) ? initialIndex : 0;

          if (_controller == null) {
            _index = target;
            _controller = PageController(initialPage: target);
          }

          return Stack(
            children: [
              PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: items.length,
                itemBuilder: (context, i) => _PhotoPage(item: items[i]),
              ),
              Positioned(
                left: 12,
                top: MediaQuery.of(context).padding.top + 10,
                child: _GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.pop();
                  },
                ),
              ),
              Positioned(
                right: 12,
                top: MediaQuery.of(context).padding.top + 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(120),
                    border: Border.all(color: Colors.white.withAlpha(28)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      '${_index + 1}/${items.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
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

class _PhotoPage extends StatelessWidget {
  final MyProviderPhotoItem item;
  const _PhotoPage({required this.item});

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
    final url = UrlUtils.normalizeMediaUrl(
      (item.playbackUrl ?? item.mediaUrl ?? item.coverUrl ?? '').toString(),
    ).trim();
    final heroTag = 'photo_thumb_${item.id}';

    return Stack(
      children: [
        Positioned.fill(
          child: url.isEmpty
              ? const Center(
                  child: Icon(
                    Icons.image_not_supported_rounded,
                    color: Colors.white38,
                    size: 48,
                  ),
                )
              : Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (context, url) => const Center(
                        child: CupertinoActivityIndicator(radius: 14),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: Colors.white38,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 18,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title.trim().isEmpty ? 'Untitled' : item.title.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatPill(
                      icon: Icons.remove_red_eye_outlined,
                      label: '${_compact(item.viewCount)} views',
                    ),
                    const SizedBox(width: 10),
                    _StatPill(
                      icon: Icons.favorite_rounded,
                      iconColor: AppColors.accent,
                      label: '${_compact(item.likeCount)} likes',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;

  const _StatPill({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(140),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(26)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor ?? Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220).withAlpha(170),
          border: Border.all(color: Colors.white.withAlpha(28)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white, size: 18),
          tooltip: 'Back',
        ),
      ),
    );
  }
}
