import 'package:flutter/material.dart';

import '../../../core/widgets/reel_card.dart';
import '../../reels/models/reel_model.dart';

class TrendingTab extends StatelessWidget {
  const TrendingTab({super.key});

  @override
  Widget build(BuildContext context) {
    final reels = <ReelModel>[
      ReelModel(
        id: 'placeholder-1',
        title: 'Trending reel #1',
        description: null,
        mediaUrl: '',
        thumbnailUrl: 'https://via.placeholder.com/600x400',
        mediaType: 'image',
        likes: 0,
        comments: 0,
        saves: 0,
        isBoosted: false,
        skillTags: const [],
        providerId: '',
        providerName: null,
      ),
      ReelModel(
        id: 'placeholder-2',
        title: 'Trending reel #2',
        description: null,
        mediaUrl: '',
        thumbnailUrl: 'https://via.placeholder.com/600x400',
        mediaType: 'image',
        likes: 0,
        comments: 0,
        saves: 0,
        isBoosted: false,
        skillTags: const [],
        providerId: '',
        providerName: null,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: reels
          .map(
            (reel) => ReelCard(
              reel: reel,
              onTap: () {},
            ),
          )
          .toList(),
    );
  }
}
