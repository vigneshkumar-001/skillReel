import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../reels/widgets/reels_viewer.dart';

class CategoryReelsScreen extends StatelessWidget {
  final String categoryKey;
  final String title;

  const CategoryReelsScreen({
    super.key,
    required this.categoryKey,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final t = title.trim().isEmpty ? 'Reels' : title.trim();
    final encoded = Uri.encodeComponent(categoryKey.trim());
    final feedType = 'search_category:$encoded';

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
              feedType: feedType,
              interactionSurface: 'search',
              title: t,
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
                    context.pop();
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

