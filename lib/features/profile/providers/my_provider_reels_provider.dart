import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/models/my_provider_reels_model.dart';
import 'profile_provider.dart';

class MyProviderReelsQuery {
  final String? cursor;
  final int limit;

  const MyProviderReelsQuery({this.cursor, this.limit = 12});

  @override
  bool operator ==(Object other) =>
      other is MyProviderReelsQuery &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(cursor, limit);
}

final myProviderReelsProvider =
    FutureProvider.family<MyProviderReelsResponse, MyProviderReelsQuery>(
  (ref, q) async {
    // Ensure profile is loaded first (auth redirect/token etc).
    await ref.watch(myProfileProvider.future);
    final repo = ref.read(appRepoProvider);
    return repo.fetchMyProviderReels(cursor: q.cursor, limit: q.limit);
  },
);
