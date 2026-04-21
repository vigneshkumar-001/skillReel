import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/feed_repository.dart';
import '../models/feed_model.dart';

final feedRepoProvider = Provider((_) => FeedRepository());

final feedProvider = FutureProvider.family<FeedModel, String>((ref, type) {
  return ref.read(feedRepoProvider).getFeed(type);
});