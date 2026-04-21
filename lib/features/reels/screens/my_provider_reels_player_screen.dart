import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../widgets/reels_viewer.dart';
import '../../../core/utils/url_utils.dart';

class MyProviderReelsPlayerScreen extends StatefulWidget {
  final String? initialReelId;
  final String? heroTag;
  final String? heroThumbUrl;

  const MyProviderReelsPlayerScreen({
    super.key,
    this.initialReelId,
    this.heroTag,
    this.heroThumbUrl,
  });

  @override
  State<MyProviderReelsPlayerScreen> createState() =>
      _MyProviderReelsPlayerScreenState();
}

class _MyProviderReelsPlayerScreenState
    extends State<MyProviderReelsPlayerScreen> {
  bool _showHeroOverlay = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showHeroOverlay = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = (widget.heroTag ?? '').trim();
    final thumbUrl = UrlUtils.normalizeMediaUrl(widget.heroThumbUrl).trim();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: ReelsViewer(
              embed: true,
              showTopBar: false,
              showUploadButton: false,
              showNotificationsButton: false,
              feedType: 'my_provider',
              interactionSurface: 'profile',
              title: 'My reels',
              initialReelId: widget.initialReelId,
            ),
          ),
          if (heroTag.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showHeroOverlay ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: Hero(
                    tag: heroTag,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF0B1220),
                            const Color(0xFF0B1220).withAlpha(210),
                          ],
                        ),
                      ),
                      child: thumbUrl.isEmpty
                          ? const Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                size: 72,
                                color: Colors.white38,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: thumbUrl,
                              fit: BoxFit.cover,
                              fadeInDuration: const Duration(milliseconds: 120),
                              placeholder: (context, url) =>
                                  const SizedBox.shrink(),
                              errorWidget: (context, url, error) =>
                                  const Center(
                                child: Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 72,
                                  color: Colors.white38,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            top: MediaQuery.of(context).padding.top + 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(120),
                  border: Border.all(color: Colors.white.withAlpha(28)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: IconButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showHeroOverlay = true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      context.pop();
                    });
                  },
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  tooltip: 'Back',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
