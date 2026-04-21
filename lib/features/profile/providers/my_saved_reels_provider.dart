import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/models/my_saved_reels_model.dart';
import 'profile_provider.dart';

class MySavedReelsQuery {
  final String? cursor;
  final int limit;

  const MySavedReelsQuery({this.cursor, this.limit = 12});

  @override
  bool operator ==(Object other) =>
      other is MySavedReelsQuery &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(cursor, limit);
}

final mySavedReelsProvider =
    FutureProvider.family<MySavedReelsResponse, MySavedReelsQuery>(
        (ref, q) async {
  await ref.watch(myProfileProvider.future);
  final repo = ref.read(appRepoProvider);
  return repo.fetchMySavedReels(cursor: q.cursor, limit: q.limit);
});
