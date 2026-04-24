import 'package:flutter/material.dart';

import '../widgets/reels_viewer.dart';

class ReelsFeedScreen extends StatelessWidget {
  final String? initialReelId;
  final String? heroTag;

  const ReelsFeedScreen({super.key, this.initialReelId, this.heroTag});

  @override
  Widget build(BuildContext context) {
    return ReelsViewer(
      showUploadButton: false,
      showNotificationsButton: false,
      feedType: 'trending',
      showTopBar: false,
      initialReelId: initialReelId,
      initialHeroTag: heroTag,
    );
  }
}
