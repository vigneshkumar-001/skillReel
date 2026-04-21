import 'package:flutter/material.dart';

import '../widgets/reels_viewer.dart';

class ReelsFeedScreen extends StatelessWidget {
  const ReelsFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReelsViewer(
      showUploadButton: false,
      showNotificationsButton: false,
      feedType: 'trending',
      showTopBar: false,
    );
  }
}
