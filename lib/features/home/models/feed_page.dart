import '../../reels/models/reel_model.dart';

class FeedPage {
  final List<ReelModel> reels;
  final String? nextCursor;
  final bool hasMore;

  const FeedPage({
    required this.reels,
    required this.nextCursor,
    required this.hasMore,
  });
}
