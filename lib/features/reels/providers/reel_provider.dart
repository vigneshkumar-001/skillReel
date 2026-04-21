import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/reel_repository.dart';
import '../models/reel_model.dart';

final reelRepoProvider = Provider((_) => ReelRepository());

final reelsProvider = FutureProvider<List<ReelModel>>((ref) {
  return ref.read(reelRepoProvider).getReels();
});