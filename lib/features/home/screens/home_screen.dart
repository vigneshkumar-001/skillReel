import 'package:flutter/material.dart';

import '../../reels/widgets/reels_viewer.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
